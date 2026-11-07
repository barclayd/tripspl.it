import { DurableObject } from 'cloudflare:workers';
import type { Expense, Invitation, LiveHint, NudgeResult, Operation, OperationResult, Repayment, Success, SyncRequest, SyncResponse, Traveller, TripReschedule, TripSnapshot } from '../types/contract';
import { AppError, assert, errorResponse } from '../utils/errors';
import { canonical, randomToken, sha256 } from '../utils/crypto';
import { normalizeConversion, normalizeRecords } from '../services/fx';
import { parse, snapshotSchema, syncSchema, validateTrip } from '../schemas/trip';
import { authenticate, registerTarget, type Principal } from '../services/auth';
import type { PushMessage } from '../services/push';
import { display, ledger } from '../utils/money';

type Meta = Omit<TripSnapshot, 'travellers' | 'stops' | 'days' | 'legs' | 'expenses' | 'repayments' | 'currentTravellerId' | 'role'>;
type TripRow = { data: string; revision: number; epoch: string; recovery_epoch: number; purged: number };
type Member = { user_id: string; traveller_id: string; role: 'owner' | 'member'; active: number; joined_at: number };
type Entity = { id: string; kind: string; revision: number; data: string | null; deleted: number };
type Receipt = { hash: string; user_id: string; revision: number };
type SocketAttachment = { userId: string; sessionId: string; expiresAt: number };
type Outbox = { user_id: string; revision: number; active: number; updated_at: string; trip_id: string };
const TABLES = ['stops', 'days', 'legs'] as const;

export type RoomAction =
  | { type: 'read' } | { type: 'create'; operationId: string; trip: TripSnapshot }
  | { type: 'sync'; request: SyncRequest } | { type: 'invite'; travellerId: string }
  | { type: 'accept'; inviteId: string; token: string } | { type: 'revokeInvite'; inviteId: string }
  | { type: 'removeMember'; travellerId: string } | { type: 'delete' } | { type: 'nudge'; travellerId: string };
/** A nudge, and who to buzz. The worker sends the push so APNs latency stays out of the room. */
export type Nudge = NudgeResult & { push: { userId: string; message: PushMessage } | null };
type RoomValue = TripSnapshot | SyncResponse | Invitation | Success | Nudge;
type RoomResult = { ok: true; value: RoomValue } | { ok: false; error: { status: number; code: string; message: string; retryable: boolean } };

export class TripRoom extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS trip(singleton INTEGER PRIMARY KEY CHECK(singleton=1), data TEXT NOT NULL, revision INTEGER NOT NULL, epoch TEXT NOT NULL, recovery_epoch INTEGER NOT NULL DEFAULT 1, purged INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS entities(kind TEXT NOT NULL, id TEXT NOT NULL, revision INTEGER NOT NULL, data TEXT, deleted INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(kind,id));
        CREATE TABLE IF NOT EXISTS stops(id TEXT PRIMARY KEY, position INTEGER NOT NULL, data TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS days(id TEXT PRIMARY KEY, position INTEGER NOT NULL, data TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS legs(id TEXT PRIMARY KEY, position INTEGER NOT NULL, data TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS members(user_id TEXT PRIMARY KEY, traveller_id TEXT NOT NULL, role TEXT NOT NULL, active INTEGER NOT NULL, joined_at INTEGER NOT NULL);
        CREATE UNIQUE INDEX IF NOT EXISTS claimed_traveller ON members(traveller_id) WHERE active=1;
        CREATE TABLE IF NOT EXISTS deleted_accounts(user_id TEXT PRIMARY KEY);
        CREATE TABLE IF NOT EXISTS invites(id TEXT PRIMARY KEY, traveller_id TEXT NOT NULL, token_hash TEXT NOT NULL, expires_at INTEGER NOT NULL, revoked INTEGER NOT NULL DEFAULT 0, accepted_by TEXT);
        CREATE TABLE IF NOT EXISTS operation_receipts(id TEXT PRIMARY KEY, hash TEXT NOT NULL, user_id TEXT NOT NULL, revision INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS changes(revision INTEGER PRIMARY KEY, operation_id TEXT, actor TEXT NOT NULL, type TEXT NOT NULL, entity_id TEXT NOT NULL, before_json TEXT, after_json TEXT, created_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS nudges(sender TEXT NOT NULL, recipient TEXT NOT NULL, day TEXT NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY(sender,recipient,day));
        CREATE TABLE IF NOT EXISTS directory_outbox(user_id TEXT PRIMARY KEY, trip_id TEXT NOT NULL, revision INTEGER NOT NULL, active INTEGER NOT NULL, updated_at TEXT NOT NULL);
      `);
    });
  }
  // RPC transports plain error envelopes; custom Error properties are not preserved across isolates.
  async execute(user: Principal, action: RoomAction): Promise<RoomResult> {
    try {
      if (this.env.MAINTENANCE_MODE === '1') throw new AppError(503, 'MAINTENANCE', 'TripSplit is temporarily unavailable for maintenance.', true);
      if (action.type !== 'create' && action.type !== 'accept') { this.member(user.id); await this.armMaintenance(); this.ensureRecovery(); }
      let value: RoomValue;
      switch (action.type) {
        case 'read': value = await this.read(user.id); break;
        case 'create': value = await this.create(user.id, action.operationId, action.trip); break;
        case 'sync': value = await this.sync(user.id, action.request); break;
        case 'invite': value = await this.invite(user.id, action.travellerId); break;
        case 'accept': value = await this.accept(user.id, action.inviteId, action.token); break;
        case 'revokeInvite': await this.revokeInvite(user.id, action.inviteId); value = { ok: true }; break;
        case 'removeMember': await this.removeMember(user.id, action.travellerId); value = { ok: true }; break;
        case 'delete': await this.deleteTrip(user.id); value = { ok: true }; break;
        case 'nudge': value = this.nudge(user.id, action.travellerId); break;
      }
      return { ok: true, value };
    } catch (error) {
      if (!(error instanceof AppError)) {
        console.error(JSON.stringify({ event: 'trip_request_failed', kind: error instanceof Error ? error.name : 'unknown' }));
        return { ok: false, error: { status: 500, code: 'INTERNAL_ERROR', message: 'The service could not complete this request.', retryable: true } };
      }
      return { ok: false, error: { status: error.status, code: error.code, message: error.message, retryable: error.retryable } };
    }
  }
  private async armMaintenance(): Promise<void> {
    // Persist an alarm before the transaction; an eviction immediately after commit cannot strand the outbox.
    const alarm = await this.ctx.storage.getAlarm();
    if (alarm === null || alarm > Date.now() + 60_000) await this.ctx.storage.setAlarm(Date.now() + 60_000);
  }
  private tripRow(): TripRow {
    const row = this.ctx.storage.sql.exec<TripRow>('SELECT * FROM trip WHERE singleton=1').toArray()[0];
    assert(row && !row.purged, 'TRIP_NOT_FOUND', 'This trip is unavailable.', 404);
    return row;
  }
  private member(userId: string, owner = false): Member {
    assert(!this.ctx.storage.sql.exec('SELECT user_id FROM deleted_accounts WHERE user_id=?', userId).toArray().length, 'MEMBERSHIP', 'You no longer have access to this trip.', 403);
    const member = this.ctx.storage.sql.exec<Member>('SELECT * FROM members WHERE user_id=? AND active=1', userId).toArray()[0];
    assert(member, 'MEMBERSHIP', 'You no longer have access to this trip.', 403);
    assert(!owner || member.role === 'owner', 'OWNER_REQUIRED', 'Only the trip owner can perform this action.', 403);
    return member;
  }
  private epoch(row: TripRow): string { return `${row.epoch}.${this.env.RECOVERY_EPOCH}`; }
  private allEntities<T>(kind: string): T[] {
    return this.ctx.storage.sql.exec<{ data: string }>('SELECT data FROM entities WHERE kind=? AND deleted=0 ORDER BY id', kind).toArray().map(row => JSON.parse(row.data) as T);
  }
  private snapshot(userId: string): TripSnapshot {
    const member = this.member(userId), row = this.tripRow(), meta = JSON.parse(row.data) as Meta;
    const itinerary = Object.fromEntries(TABLES.map(table => [table, this.ctx.storage.sql.exec<{ data: string }>(`SELECT data FROM ${table} ORDER BY position`).toArray().map(item => JSON.parse(item.data))]));
    return { ...meta, revision: row.revision, syncEpoch: this.epoch(row), currentTravellerId: member.traveller_id, role: member.role, travellers: this.allEntities<Traveller>('traveller'), expenses: this.allEntities<Expense>('expense'), repayments: this.allEntities<Repayment>('repayment'), stops: itinerary.stops as TripSnapshot['stops'], days: itinerary.days as TripSnapshot['days'], legs: itinerary.legs as TripSnapshot['legs'] };
  }
  private ensureRecovery(): void {
    const version = Number(this.env.RECOVERY_EPOCH);
    assert(Number.isSafeInteger(version) && version > 0, 'RECOVERY_CONFIG', 'Recovery epoch is not configured correctly.', 503);
    const row = this.ctx.storage.sql.exec<TripRow>('SELECT * FROM trip').toArray()[0];
    if (!row || row.purged || row.recovery_epoch === version) return;
    assert(version > row.recovery_epoch, 'RECOVERY_CONFIG', 'Recovery epoch cannot move backwards.', 503);
    this.ctx.storage.transactionSync(() => {
      const meta = JSON.parse(row.data) as Meta;
      meta.revision = row.revision + 1; meta.updatedAt = new Date().toISOString();
      this.ctx.storage.sql.exec('UPDATE trip SET data=?,revision=?,recovery_epoch=? WHERE singleton=1', JSON.stringify(meta), meta.revision, version);
      this.queueProjection(meta.id, meta.revision, meta.updatedAt);
      this.audit(meta.revision, 'server', 'server.recovery', meta.id, null, { recoveryEpoch: version });
    });
  }
  async read(userId: string): Promise<TripSnapshot> { this.member(userId); await this.armMaintenance(); this.ensureRecovery(); this.scheduleMaintenance(); return this.snapshot(userId); }
  private writeEntity(kind: string, value: Traveller | Expense | Repayment): void {
    this.ctx.storage.sql.exec('INSERT INTO entities(kind,id,revision,data,deleted) VALUES(?,?,?,?,0) ON CONFLICT(kind,id) DO UPDATE SET revision=excluded.revision,data=excluded.data,deleted=0', kind, value.id, value.revision, JSON.stringify(value));
  }
  private writeItinerary(trip: Pick<TripSnapshot, 'stops' | 'days' | 'legs'>): void {
    for (const table of TABLES) {
      this.ctx.storage.sql.exec(`DELETE FROM ${table}`);
      trip[table].forEach((item, index) => this.ctx.storage.sql.exec(`INSERT INTO ${table}(id,position,data) VALUES(?,?,?)`, item.id, index, JSON.stringify(item)));
    }
  }
  /** What a reschedule changes, for the audit log. */
  private dates(trip: TripSnapshot): Pick<TripSnapshot, 'startsOn' | 'days' | 'legs'> & { nights: Record<string, number> } {
    return { startsOn: trip.startsOn, nights: Object.fromEntries(trip.stops.map(stop => [stop.id, stop.nights])), days: trip.days, legs: trip.legs };
  }
  /**
   * Moves a trip to new dates without changing where it goes. Days keep their IDs, so their
   * expenses move with them; a day that leaves the trip hands its expenses to the kept day the
   * client chose, including any it hadn't seen yet. Returns the IDs of the expenses it moved.
   */
  private reschedule(trip: TripSnapshot, payload: TripReschedule): string[] {
    assert(payload.stops.length === trip.stops.length && payload.stops.every((stop, index) => stop.id === trip.stops[index]!.id), 'RESCHEDULE', 'Rescheduling keeps the trip’s stops in order. Change them in trip settings.');
    const legs = new Map(trip.legs.map(leg => [leg.id, leg]));
    assert(payload.legs.length === trip.legs.length && payload.legs.every(leg => { const old = legs.get(leg.id); return old?.kind === leg.kind && old.fromStopId === leg.fromStopId && old.toStopId === leg.toStopId; }), 'RESCHEDULE', 'Rescheduling only moves the trip’s legs to new dates.');
    const kept = new Set(payload.days.map(day => day.id)), dropped = trip.days.filter(day => !kept.has(day.id));
    const moves = new Map(payload.moves.map(move => [move.fromDayId, move.toDayId]));
    assert(moves.size === payload.moves.length && moves.size === dropped.length && dropped.every(day => kept.has(moves.get(day.id) ?? '')), 'DAY_MOVES', 'Every day that leaves the trip must name a kept day for its expenses.');
    const nights = new Map(payload.stops.map(stop => [stop.id, stop.nights]));
    Object.assign(trip, { startsOn: payload.startsOn, stops: trip.stops.map(stop => ({ ...stop, nights: nights.get(stop.id)! })), days: payload.days, legs: payload.legs });
    const moved: Expense[] = [];
    trip.expenses = trip.expenses.map(expense => {
      const target = expense.attachment.kind === 'day' ? moves.get(expense.attachment.id) : undefined;
      const changedDays = expense.dayIds?.some(id => moves.has(id)) ?? false;
      if (target === undefined && !changedDays) return expense;
      const value = { ...expense, attachment: { kind: 'day' as const, id: target ?? expense.attachment.id }, revision: expense.revision + 1 };
      if (expense.dayIds) {
        const selected = new Set(expense.dayIds.map(id => moves.get(id) ?? id));
        const ordered = trip.days.map(day => day.id).filter(id => selected.has(id));
        value.attachment.id = ordered[0]!;
        if (ordered.length > 1) value.dayIds = ordered;
        else delete value.dayIds;
      }
      moved.push(value); return value;
    });
    validateTrip(trip); this.writeItinerary(trip);
    for (const expense of moved) this.writeEntity('expense', expense);
    return moved.map(expense => expense.id);
  }
  private meta(trip: TripSnapshot): Meta {
    const { travellers: _travellers, expenses: _expenses, repayments: _repayments, stops: _stops, days: _days, legs: _legs, currentTravellerId: _current, role: _role, ...meta } = trip;
    return meta;
  }
  private queueProjection(tripId: string, revision: number, updatedAt: string, active?: number): void {
    for (const member of this.ctx.storage.sql.exec<Member>('SELECT * FROM members').toArray()) {
      this.ctx.storage.sql.exec('INSERT INTO directory_outbox(user_id,trip_id,revision,active,updated_at) VALUES(?,?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET revision=excluded.revision,active=excluded.active,updated_at=excluded.updated_at', member.user_id, tripId, revision, active ?? member.active, updatedAt);
    }
  }
  private audit(revision: number, userId: string, type: string, entityId: string, before: unknown, after: unknown, operationId: string | null = null): void {
    this.ctx.storage.sql.exec('INSERT INTO changes(revision,operation_id,actor,type,entity_id,before_json,after_json,created_at) VALUES(?,?,?,?,?,?,?,?)', revision, operationId, userId, type, entityId, before == null ? null : JSON.stringify(before), after == null ? null : JSON.stringify(after), new Date().toISOString());
  }
  private bump(trip: TripSnapshot): number {
    trip.revision += 1; trip.updatedAt = new Date().toISOString();
    this.ctx.storage.sql.exec('UPDATE trip SET data=?,revision=? WHERE singleton=1', JSON.stringify(this.meta(trip)), trip.revision);
    this.queueProjection(trip.id, trip.revision, trip.updatedAt);
    return trip.revision;
  }
  private async accountActive(userId: string): Promise<void> {
    const user = await this.env.DB.prepare('SELECT id FROM users WHERE id=? AND deleting=0').bind(userId).first();
    assert(user, 'ACCOUNT_DELETING', 'This account is no longer active.', 403);
  }
  async create(userId: string, operationId: string, raw: TripSnapshot): Promise<TripSnapshot> {
    await this.armMaintenance();
    const draft = parse(snapshotSchema, raw), hash = await sha256(canonical({ type: 'create', trip: raw }));
    await this.accountActive(userId);
    const existing = this.ctx.storage.sql.exec<TripRow>('SELECT * FROM trip').toArray()[0];
    if (existing) {
      this.member(userId);
      const receipt = this.ctx.storage.sql.exec<Receipt>('SELECT * FROM operation_receipts WHERE id=?', operationId).toArray()[0];
      assert(receipt && receipt.user_id === userId && receipt.hash === hash, 'TRIP_EXISTS', 'This trip ID is already in use.', 409);
      return this.snapshot(userId);
    }
    assert(draft.revision === 0 && draft.syncEpoch === 'local', 'CREATE_REVISION', 'Create a cloud trip from a local draft.');
    const records = await normalizeRecords(this.env, [...draft.expenses, ...draft.repayments], draft.homeCurrency);
    draft.expenses = records.slice(0, draft.expenses.length) as Expense[];
    draft.repayments = records.slice(draft.expenses.length) as Repayment[];
    this.ctx.storage.transactionSync(() => {
      if (this.ctx.storage.sql.exec('SELECT * FROM trip').toArray().length) {
        this.member(userId);
        const receipt = this.ctx.storage.sql.exec<Receipt>('SELECT * FROM operation_receipts WHERE id=?', operationId).toArray()[0];
        assert(receipt && receipt.user_id === userId && receipt.hash === hash, 'TRIP_EXISTS', 'This trip ID is already in use.', 409);
        return;
      }
      assert(!this.ctx.storage.sql.exec('SELECT * FROM deleted_accounts WHERE user_id=?', userId).toArray().length, 'ACCOUNT_DELETING', 'This account is no longer active.', 403);
      validateTrip(draft);
      draft.revision = 1; draft.updatedAt = new Date().toISOString();
      const epoch = crypto.randomUUID(); draft.syncEpoch = `${epoch}.${this.env.RECOVERY_EPOCH}`;
      this.ctx.storage.sql.exec('INSERT INTO trip(singleton,data,revision,epoch,recovery_epoch) VALUES(1,?,?,?,?)', JSON.stringify(this.meta(draft)), 1, epoch, Number(this.env.RECOVERY_EPOCH));
      for (const value of draft.travellers) this.writeEntity('traveller', { ...value, revision: 1 });
      for (const value of draft.expenses) this.writeEntity('expense', { ...value, revision: 1 });
      for (const value of draft.repayments) this.writeEntity('repayment', { ...value, revision: 1 });
      this.writeItinerary(draft);
      this.ctx.storage.sql.exec('INSERT INTO members(user_id,traveller_id,role,active,joined_at) VALUES(?,?,?,1,?)', userId, draft.ownerTravellerId, 'owner', Date.now());
      this.ctx.storage.sql.exec('INSERT INTO operation_receipts(id,hash,user_id,revision) VALUES(?,?,?,1)', operationId, hash, userId);
      this.audit(1, userId, 'trip.create', draft.id, null, this.meta(draft), operationId);
      this.queueProjection(draft.id, 1, draft.updatedAt);
    });
    this.scheduleMaintenance();
    return this.snapshot(userId);
  }
  async sync(userId: string, raw: SyncRequest): Promise<SyncResponse> {
    await this.armMaintenance();
    const request = parse(syncSchema, raw);
    this.member(userId);
    const results: OperationResult[] = [];
    for (const operation of request.operations) {
      try { results.push(await this.apply(userId, operation)); }
      catch (error) {
        if (!(error instanceof AppError)) throw error;
        if (error.status === 403 || error.status === 429 || error.status >= 500 || error.retryable) throw error;
        results.push({ id: operation.id, status: error.status === 409 ? 'conflict' : 'rejected', revision: null, code: error.code, message: error.message });
      }
    }
    const snapshot = this.snapshot(userId);
    this.scheduleMaintenance();
    if (results.some(r => r.status === 'accepted')) this.ctx.waitUntil(this.notify());
    return { cursor: snapshot.revision, syncEpoch: snapshot.syncEpoch, snapshot: request.cursor !== snapshot.revision || request.syncEpoch !== snapshot.syncEpoch || results.length > 0 ? snapshot : null, results };
  }
  private async apply(userId: string, operation: Operation): Promise<OperationResult> {
    this.member(userId, operation.type.startsWith('trip.') || operation.type.startsWith('traveller.'));
    const before = this.snapshot(userId), hash = await sha256(canonical(operation));
    assert(operation.syncEpoch === before.syncEpoch, 'SYNC_EPOCH', 'Server recovery requires a fresh snapshot and review of pending edits.', 409);
    const priorReceipt = this.ctx.storage.sql.exec<Receipt>('SELECT * FROM operation_receipts WHERE id=?', operation.id).toArray()[0];
    if (priorReceipt) {
      assert(priorReceipt.hash === hash && priorReceipt.user_id === userId, 'OPERATION_REUSED', 'This operation ID has already been used with different content.', 409);
      this.member(userId, operation.type.startsWith('trip.') || operation.type.startsWith('traveller.'));
      return { id: operation.id, status: 'duplicate', revision: priorReceipt.revision, code: null, message: null };
    }
    let normalized: Expense | Repayment | null = null;
    if (operation.type === 'expense.upsert' || operation.type === 'repayment.upsert') normalized = await normalizeConversion(this.env, operation.payload, before.homeCurrency);
    return this.ctx.storage.transactionSync(() => {
      this.member(userId, operation.type.startsWith('trip.') || operation.type.startsWith('traveller.'));
      const trip = this.snapshot(userId);
      assert(operation.syncEpoch === trip.syncEpoch, 'SYNC_EPOCH', 'Server recovery requires a fresh snapshot and review of pending edits.', 409);
      const receipt = this.ctx.storage.sql.exec<Receipt>('SELECT * FROM operation_receipts WHERE id=?', operation.id).toArray()[0];
      if (receipt) {
        assert(receipt.hash === hash && receipt.user_id === userId, 'OPERATION_REUSED', 'This operation ID has already been used with different content.', 409);
        return { id: operation.id, status: 'duplicate', revision: receipt.revision, code: null, message: null };
      }
      assert(trip.homeCurrency === before.homeCurrency, 'REVISION_CONFLICT', 'Trip currency changed. Refresh before editing.', 409);
      let previous: unknown = null, after: unknown = null;
      if (operation.type === 'trip.update' || operation.type === 'trip.archive' || operation.type === 'trip.reschedule') {
        assert(operation.entityId === trip.id && operation.expectedRevision === trip.revision, 'REVISION_CONFLICT', 'Trip settings changed on another device.', 409);
        previous = this.meta(trip);
        if (operation.type === 'trip.reschedule') {
          previous = this.dates(trip);
          const moved = this.reschedule(trip, operation.payload);
          after = { ...this.dates(trip), movedExpenseIds: moved };
        } else if (operation.type === 'trip.update') {
          assert(operation.payload.homeCurrency === trip.homeCurrency || trip.expenses.length + trip.repayments.length === 0, 'HOME_CURRENCY_LOCKED', 'Reporting currency cannot change after financial records are added.');
          // Stable IDs protect existing financial attachments. Date shifts require explicit record edits.
          for (const expense of trip.expenses) {
            for (const dayId of expense.dayIds ?? []) {
              const oldDay = trip.days.find(day => day.id === dayId);
              const newDay = operation.payload.days.find(day => day.id === dayId);
              assert(oldDay && newDay && oldDay.date === newDay.date, 'REFERENCED_ITINERARY', 'Move attached expenses explicitly before changing or deleting their day or leg.');
            }
            const oldEntity = (expense.attachment.kind === 'day' ? trip.days : trip.legs).find(item => item.id === expense.attachment.id);
            const newEntity = (expense.attachment.kind === 'day' ? operation.payload.days : operation.payload.legs).find(item => item.id === expense.attachment.id);
            assert(oldEntity && newEntity && oldEntity.date === newEntity.date, 'REFERENCED_ITINERARY', 'Move attached expenses explicitly before changing or deleting their day or leg.');
          }
          // Older clients omit `origin`, so Object.assign keeps the saved one; they also omit
          // this additive stop field. Preserve it by stable stop ID without
          // modifying the submitted operation: receipts must still hash the original payload.
          const existingStops = new Map(trip.stops.map(stop => [stop.id, stop]));
          const stops = operation.payload.stops.map(stop => {
            const previousTimeZone = existingStops.get(stop.id)?.timeZone;
            return stop.timeZone === undefined && previousTimeZone !== undefined
              ? { ...stop, timeZone: previousTimeZone } : stop;
          });
          Object.assign(trip, operation.payload, { stops });
          validateTrip(trip); this.writeItinerary(trip);
        } else trip.archived = operation.payload.archived;
        if (operation.type !== 'trip.reschedule') after = this.meta(trip);
      } else {
        const [kind, action] = operation.type.split('.') as ['expense' | 'repayment' | 'traveller', 'upsert' | 'delete'];
        const row = this.ctx.storage.sql.exec<Entity>('SELECT * FROM entities WHERE kind=? AND id=?', kind, operation.entityId).toArray()[0];
        assert(operation.expectedRevision === null ? !row : row && !row.deleted && row.revision === operation.expectedRevision, row?.deleted ? 'ENTITY_DELETED' : 'REVISION_CONFLICT', 'This record has changed. Review the latest snapshot.', 409);
        previous = row?.data ? JSON.parse(row.data) : null;
        if (action === 'delete') {
          this.ctx.storage.sql.exec('UPDATE entities SET revision=revision+1,data=NULL,deleted=1 WHERE kind=? AND id=?', kind, operation.entityId);
        } else {
          assert(operation.payload && 'id' in operation.payload && operation.payload.id === operation.entityId, 'ENTITY_ID', 'Payload and operation entity IDs must match.');
          const value = { ...(normalized ?? operation.payload), revision: (row?.revision ?? 0) + 1 } as Traveller | Expense | Repayment;
          if (kind === 'expense') trip.expenses = [...trip.expenses.filter(e => e.id !== value.id), value as Expense];
          if (kind === 'repayment') trip.repayments = [...trip.repayments.filter(e => e.id !== value.id), value as Repayment];
          if (kind === 'traveller') {
            const traveller = value as Traveller;
            assert(trip.travellers.length < 40 || row, 'TRAVELLER_LIMIT', 'A trip can have at most 40 travellers.');
            assert(!traveller.archived || !this.ctx.storage.sql.exec('SELECT 1 FROM members WHERE traveller_id=? AND active=1', traveller.id).toArray().length, 'MEMBER_ACTIVE', 'Remove this traveller’s account membership before archiving them.');
            trip.travellers = [...trip.travellers.filter(t => t.id !== traveller.id), traveller];
          }
          validateTrip(trip);
          assert(trip.expenses.length + trip.repayments.length <= 10_000, 'RECORD_LIMIT', 'A trip can have at most 10,000 financial records.');
          this.writeEntity(kind, value); after = value;
        }
      }
      const revision = this.bump(trip);
      this.audit(revision, userId, operation.type, operation.entityId, previous, after, operation.id);
      this.ctx.storage.sql.exec('INSERT INTO operation_receipts(id,hash,user_id,revision) VALUES(?,?,?,?)', operation.id, hash, userId, revision);
      return { id: operation.id, status: 'accepted', revision, code: null, message: null };
    });
  }
  async invite(userId: string, travellerId: string): Promise<Invitation> {
    await this.armMaintenance();
    this.member(userId, true);
    const token = randomToken(), hash = await sha256(token), id = crypto.randomUUID(), expires = Date.now() + 7 * 86_400_000;
    this.ctx.storage.transactionSync(() => {
      this.member(userId, true);
      const trip = this.snapshot(userId), traveller = trip.travellers.find(t => t.id === travellerId);
      assert(traveller && !traveller.archived, 'TRAVELLER', 'Choose an active traveller.');
      assert(!this.ctx.storage.sql.exec('SELECT 1 FROM members WHERE traveller_id=? AND active=1', travellerId).toArray().length, 'TRAVELLER_CLAIMED', 'This traveller already has an account.', 409);
      this.ctx.storage.sql.exec('UPDATE invites SET revoked=1 WHERE traveller_id=? AND accepted_by IS NULL', travellerId);
      this.ctx.storage.sql.exec('INSERT INTO invites(id,traveller_id,token_hash,expires_at) VALUES(?,?,?,?)', id, travellerId, hash, expires);
      const revision = this.bump(trip); this.audit(revision, userId, 'invite.create', id, null, { travellerId });
    });
    this.scheduleMaintenance(); this.ctx.waitUntil(this.notify());
    const trip = this.snapshot(userId);
    let url: string | null = null;
    if (this.env.INVITE_ORIGIN) {
      const origin = new URL(this.env.INVITE_ORIGIN);
      assert(origin.protocol === 'https:', 'INVITE_ORIGIN', 'Invite origin must use HTTPS.', 503);
      url = `${origin.origin}/invite/${encodeURIComponent(trip.id)}/${id}#token=${token}`;
    }
    return { id, token, expiresAt: new Date(expires).toISOString(), url };
  }
  async accept(userId: string, inviteId: string, token: string): Promise<TripSnapshot> {
    await this.armMaintenance();
    const hash = await sha256(token);
    const candidate = this.ctx.storage.sql.exec<{ token_hash: string; revoked: number }>('SELECT token_hash,revoked FROM invites WHERE id=?', inviteId).toArray()[0];
    assert(candidate && !candidate.revoked && crypto.subtle.timingSafeEqual(new TextEncoder().encode(candidate.token_hash), new TextEncoder().encode(hash)), 'INVITE_INVALID', 'This invitation is invalid or has been revoked.', 403);
    await registerTarget(this.env, userId, (JSON.parse(this.tripRow().data) as Meta).id);
    await this.accountActive(userId);
    this.ctx.storage.transactionSync(() => {
      assert(!this.ctx.storage.sql.exec('SELECT 1 FROM deleted_accounts WHERE user_id=?', userId).toArray().length, 'ACCOUNT_DELETING', 'This account is no longer active.', 403);
      const invite = this.ctx.storage.sql.exec<{ traveller_id: string; token_hash: string; expires_at: number; revoked: number; accepted_by: string | null }>('SELECT * FROM invites WHERE id=?', inviteId).toArray()[0];
      assert(invite && !invite.revoked && crypto.subtle.timingSafeEqual(new TextEncoder().encode(invite.token_hash), new TextEncoder().encode(hash)), 'INVITE_INVALID', 'This invitation is invalid or has been revoked.', 403);
      if (invite.accepted_by === userId) { this.member(userId); return; }
      assert(!invite.accepted_by && invite.expires_at > Date.now(), 'INVITE_EXPIRED', 'This invitation has expired or has already been accepted.', 403);
      assert(!this.ctx.storage.sql.exec('SELECT 1 FROM members WHERE active=1 AND (user_id=? OR traveller_id=?)', userId, invite.traveller_id).toArray().length, 'ALREADY_MEMBER', 'The account or traveller already has a membership.', 409);
      const row = this.ctx.storage.sql.exec<{ data: string }>('SELECT data FROM entities WHERE kind=? AND id=? AND deleted=0', 'traveller', invite.traveller_id).toArray()[0];
      assert(row && !(JSON.parse(row.data) as Traveller).archived, 'TRAVELLER', 'This traveller is no longer active.');
      this.ctx.storage.sql.exec('INSERT INTO members(user_id,traveller_id,role,active,joined_at) VALUES(?,?,?,1,?) ON CONFLICT(user_id) DO UPDATE SET traveller_id=excluded.traveller_id,role=excluded.role,active=1,joined_at=excluded.joined_at', userId, invite.traveller_id, 'member', Date.now());
      this.ctx.storage.sql.exec('UPDATE invites SET accepted_by=? WHERE id=?', userId, inviteId);
      const trip = this.snapshot(userId), revision = this.bump(trip); this.audit(revision, userId, 'member.join', invite.traveller_id, null, { travellerId: invite.traveller_id });
    });
    this.scheduleMaintenance(); this.ctx.waitUntil(this.notify());
    return this.snapshot(userId);
  }
  async revokeInvite(userId: string, inviteId: string): Promise<void> {
    await this.armMaintenance();
    this.ctx.storage.transactionSync(() => {
      this.member(userId, true);
      const changed = this.ctx.storage.sql.exec<{ id: string }>('UPDATE invites SET revoked=1 WHERE id=? AND revoked=0 RETURNING id', inviteId).toArray();
      if (changed.length) { const trip = this.snapshot(userId), revision = this.bump(trip); this.audit(revision, userId, 'invite.revoke', inviteId, null, null); }
    });
    this.scheduleMaintenance(); this.ctx.waitUntil(this.notify());
  }
  async removeMember(userId: string, travellerId: string): Promise<void> {
    await this.armMaintenance();
    this.ctx.storage.transactionSync(() => {
      this.member(userId, true);
      const trip = this.snapshot(userId);
      assert(travellerId !== trip.ownerTravellerId, 'OWNER_REQUIRED', 'The owner cannot remove their own membership.');
      const changed = this.ctx.storage.sql.exec('UPDATE members SET active=0 WHERE traveller_id=? AND active=1 RETURNING user_id', travellerId).toArray();
      this.ctx.storage.sql.exec('UPDATE invites SET revoked=1 WHERE traveller_id=?', travellerId);
      if (changed.length) { const revision = this.bump(trip); this.audit(revision, userId, 'member.remove', travellerId, null, null); }
    });
    this.scheduleMaintenance(); this.ctx.waitUntil(this.notify());
  }
  /**
   * Deletes the trip for every traveller. Members keep their rows so they see the trip as gone
   * (404) rather than lose access to it (403), and a retry by the owner succeeds.
   */
  async deleteTrip(userId: string): Promise<void> {
    await this.armMaintenance();
    const tripId = this.ctx.storage.transactionSync(() => {
      this.member(userId, true);
      const row = this.ctx.storage.sql.exec<TripRow>('SELECT * FROM trip').one(), meta = JSON.parse(row.data) as Meta;
      if (row.purged) return meta.id;
      meta.revision = row.revision + 1; meta.updatedAt = new Date().toISOString();
      this.purge(meta);
      this.ctx.storage.sql.exec('UPDATE trip SET data=?,revision=?,purged=1 WHERE singleton=1', JSON.stringify(meta), meta.revision);
      this.queueProjection(meta.id, meta.revision, meta.updatedAt, 0);
      return meta.id;
    });
    // Frees every traveller's trip allowance; repeated on retry if this write fails.
    await this.env.DB.prepare('DELETE FROM user_trip_targets WHERE trip_id=?').bind(tripId).run();
    this.scheduleMaintenance(); await this.notify();
  }
  /**
   * Nudges a traveller who owes the sender, at most once per pair per trip day. A traveller with no
   * account on the trip can't be buzzed, so that isn't recorded and doesn't use up the day.
   */
  nudge(userId: string, travellerId: string): Nudge {
    return this.ctx.storage.transactionSync(() => {
      const sender = this.member(userId), trip = this.snapshot(userId);
      const traveller = trip.travellers.find(t => t.id === travellerId);
      assert(traveller && !traveller.archived && travellerId !== sender.traveller_id, 'TRAVELLER', 'Choose someone else on this trip.');
      const owed = ledger(trip).settlements.find(s => s.from === travellerId && s.to === sender.traveller_id);
      assert(owed, 'NOTHING_OWED', `${traveller.name} doesn't owe you anything right now.`, 409);
      const nudgedOn = civilDate(trip.timeZone, Date.now());
      const recipient = this.ctx.storage.sql.exec<{ user_id: string }>('SELECT user_id FROM members WHERE traveller_id=? AND active=1', travellerId).toArray()[0];
      if (!recipient) return { status: 'notJoined', nudgedOn, push: null };
      const recorded = this.ctx.storage.sql.exec('INSERT INTO nudges(sender,recipient,day,created_at) VALUES(?,?,?,?) ON CONFLICT DO NOTHING RETURNING day', sender.traveller_id, travellerId, nudgedOn, Date.now()).toArray();
      assert(recorded.length, 'NUDGE_LIMIT', `You've already nudged ${traveller.name} today.`, 429);
      this.ctx.storage.sql.exec('DELETE FROM nudges WHERE day<?', civilDate(trip.timeZone, Date.now() - 7 * 86_400_000));
      const name = trip.travellers.find(t => t.id === sender.traveller_id)?.name ?? 'Someone';
      return {
        status: 'sent', nudgedOn,
        push: { userId: recipient.user_id, message: {
          title: `${name} nudged you`, body: `You owe ${name} ${display(owed.amountMinor, trip.homeCurrency)} for ${trip.name}.`,
          category: 'tripsplit.nudge', threadId: trip.id, collapseId: `nudge.${trip.id}.${sender.traveller_id}`,
          data: { trip: trip.id, traveller: sender.traveller_id },
        } },
      };
    });
  }
  /** Empties the trip but keeps receipts and tombstones, so restored devices can't bring it back. */
  private purge(meta: Meta): void {
    meta.name = 'Deleted trip'; meta.archived = true; meta.budgetMinor = '0';
    meta.startsOn = '1970-01-01'; meta.timeZone = 'UTC'; meta.homeCurrency = 'GBP'; meta.ownerTravellerId = 'deleted';
    this.ctx.storage.sql.exec('UPDATE entities SET data=NULL,deleted=1,revision=revision+1');
    for (const table of TABLES) this.ctx.storage.sql.exec(`DELETE FROM ${table}`);
    this.ctx.storage.sql.exec('DELETE FROM changes'); this.ctx.storage.sql.exec('DELETE FROM invites'); this.ctx.storage.sql.exec('DELETE FROM nudges');
  }
  async removeAccount(userId: string): Promise<void> {
    await this.armMaintenance();
    this.ctx.storage.transactionSync(() => {
      if (this.ctx.storage.sql.exec('SELECT 1 FROM deleted_accounts WHERE user_id=?', userId).toArray().length) return;
      this.ctx.storage.sql.exec('INSERT OR IGNORE INTO deleted_accounts(user_id) VALUES(?)', userId);
      const member = this.ctx.storage.sql.exec<Member>('SELECT * FROM members WHERE user_id=?', userId).toArray()[0];
      const row = this.ctx.storage.sql.exec<TripRow>('SELECT * FROM trip').toArray()[0];
      if (!member || !row || row.purged) return;
      const meta = JSON.parse(row.data) as Meta, travellerRow = this.ctx.storage.sql.exec<Entity>('SELECT * FROM entities WHERE kind=? AND id=?', 'traveller', member.traveller_id).one();
      const traveller = JSON.parse(travellerRow.data!) as Traveller;
      this.writeEntity('traveller', { ...traveller, name: 'Deleted traveller', archived: true, revision: traveller.revision + 1 });
      this.ctx.storage.sql.exec('UPDATE members SET active=0 WHERE user_id=?', userId);
      this.ctx.storage.sql.exec('UPDATE invites SET revoked=1 WHERE traveller_id=?', member.traveller_id);
      const others = this.ctx.storage.sql.exec<Member>('SELECT * FROM members WHERE active=1 ORDER BY joined_at,user_id').toArray();
      if (member.role === 'owner' && others.length) {
        const next = others[0]!; meta.ownerTravellerId = next.traveller_id;
        this.ctx.storage.sql.exec('UPDATE members SET role=? WHERE user_id=?', 'owner', next.user_id);
      }
      meta.revision = row.revision + 1; meta.updatedAt = new Date().toISOString();
      if (!others.length) {
        this.purge(meta);
      } else {
        // Names and deleted account IDs are not retained in historical JSON.
        this.ctx.storage.sql.exec('UPDATE changes SET before_json=NULL,after_json=NULL WHERE entity_id=? OR actor=?', member.traveller_id, userId);
        this.ctx.storage.sql.exec('UPDATE changes SET actor=? WHERE actor=?', 'deleted-account', userId);
        this.audit(meta.revision, 'deleted-account', 'account.remove', member.traveller_id, null, null);
      }
      this.ctx.storage.sql.exec('UPDATE trip SET data=?,revision=?,purged=? WHERE singleton=1', JSON.stringify(meta), meta.revision, others.length ? 0 : 1);
      this.queueProjection(meta.id, meta.revision, meta.updatedAt);
    });
    this.scheduleMaintenance(); await this.notify();
  }
  /** Trusted operator RPC only; never exposed by the HTTP router. */
  async repairDirectory(): Promise<{ tripId: string | null }> {
    assert(this.env.MAINTENANCE_MODE === '1', 'MAINTENANCE_REQUIRED', 'Directory recovery requires maintenance mode.', 403);
    await this.armMaintenance(); this.ensureRecovery();
    const row = this.ctx.storage.sql.exec<TripRow>('SELECT * FROM trip').toArray()[0];
    if (!row) return { tripId: null };
    const meta = JSON.parse(row.data) as Meta;
    if (row.purged) {
      await this.env.DB.prepare('DELETE FROM user_trip_targets WHERE trip_id=?').bind(meta.id).run();
      return { tripId: meta.id };
    }
    for (const member of this.ctx.storage.sql.exec<Member>('SELECT * FROM members WHERE active=1').toArray()) {
      const account = await this.env.DB.prepare('SELECT deleting FROM users WHERE id=?').bind(member.user_id).first<{ deleting: number }>();
      assert(account, 'RECOVERY_ACCOUNT_MISSING', 'An account missing from D1 must be recovered before rebuilding this trip.', 409);
      if (account.deleting) { await this.removeAccount(member.user_id); continue; }
      await this.env.DB.prepare('INSERT OR IGNORE INTO user_trip_targets(user_id,trip_id) VALUES(?,?)').bind(member.user_id, meta.id).run();
    }
    const latest = this.ctx.storage.sql.exec<TripRow>('SELECT * FROM trip').one();
    this.queueProjection(meta.id, latest.revision, new Date().toISOString());
    await this.flushDirectory();
    return { tripId: meta.id };
  }
  /** Cloud-only PITR; use a trusted operator Worker with the namespace binding. */
  async recoveryBookmark(timestamp?: number): Promise<string> {
    assert(this.env.MAINTENANCE_MODE === '1', 'MAINTENANCE_REQUIRED', 'Recovery requires maintenance mode.', 403);
    if (timestamp === undefined) return this.ctx.storage.getCurrentBookmark();
    assert(Number.isSafeInteger(timestamp) && timestamp >= 0 && timestamp <= Date.now(), 'RECOVERY_TIME', 'Use a valid past timestamp.');
    return this.ctx.storage.getBookmarkForTime(timestamp);
  }
  async restoreBookmark(bookmark: string): Promise<void> {
    assert(this.env.MAINTENANCE_MODE === '1', 'MAINTENANCE_REQUIRED', 'Recovery requires maintenance mode.', 403);
    assert(bookmark.length > 0 && bookmark.length <= 256, 'RECOVERY_BOOKMARK', 'Use a valid storage bookmark.');
    await this.ctx.storage.onNextSessionRestoreBookmark(bookmark);
    this.ctx.abort('Operator point-in-time restore; increase RECOVERY_EPOCH before resuming traffic.');
  }
  private scheduleMaintenance(): void {
    this.ctx.waitUntil((async () => {
      const alarm = await this.ctx.storage.getAlarm();
      if (alarm === null || alarm > Date.now() + 1000) await this.ctx.storage.setAlarm(Date.now() + 1000);
    })());
  }
  async flushDirectory(): Promise<void> {
    const rows = this.ctx.storage.sql.exec<Outbox>('SELECT * FROM directory_outbox LIMIT 80').toArray();
    for (const row of rows) {
      await this.env.DB.prepare(`INSERT INTO user_trips(user_id,trip_id,revision,recovery_epoch,active,updated_at) SELECT ?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM users WHERE id=? AND deleting=0)
        ON CONFLICT(user_id,trip_id) DO UPDATE SET revision=excluded.revision,recovery_epoch=excluded.recovery_epoch,active=excluded.active,updated_at=excluded.updated_at WHERE excluded.recovery_epoch>user_trips.recovery_epoch OR (excluded.recovery_epoch=user_trips.recovery_epoch AND excluded.revision>=user_trips.revision)`).bind(row.user_id, row.trip_id, row.revision, Number(this.env.RECOVERY_EPOCH), row.active, row.updated_at, row.user_id).run();
      this.ctx.storage.sql.exec('DELETE FROM directory_outbox WHERE user_id=? AND revision=?', row.user_id, row.revision);
    }
  }
  override async alarm(): Promise<void> {
    if (this.env.MAINTENANCE_MODE === '1') {
      for (const socket of this.ctx.getWebSockets()) socket.close(1012, 'Server maintenance');
      await this.ctx.storage.setAlarm(Date.now() + 60_000); return;
    }
    try { await this.flushDirectory(); await this.notify(false); }
    catch { console.error(JSON.stringify({ event: 'trip_maintenance_retry' })); }
    finally {
      const pending = this.ctx.storage.sql.exec('SELECT 1 FROM directory_outbox LIMIT 1').toArray().length > 0;
      if (pending || this.ctx.getWebSockets().length) await this.ctx.storage.setAlarm(Date.now() + 60_000);
    }
  }
  // WebSocket upgrades use fetch: WebSocket handles cannot cross an RPC serialization boundary.
  override async fetch(request: Request): Promise<Response> {
    try {
      if (this.env.MAINTENANCE_MODE === '1') throw new AppError(503, 'MAINTENANCE', 'TripSplit is temporarily unavailable for maintenance.', true);
      assert(request.headers.get('Upgrade')?.toLowerCase() === 'websocket', 'UPGRADE_REQUIRED', 'Use a WebSocket upgrade.', 426);
      return await this.openLive(await authenticate(request, this.env));
    } catch (error) { return errorResponse(error); }
  }
  private async openLive(user: Principal): Promise<Response> {
    this.member(user.id); this.tripRow();
    assert(this.ctx.getWebSockets().length < 80, 'SOCKET_LIMIT', 'This trip has too many live connections.', 429);
    const pair = new WebSocketPair();
    const client = pair[0], server = pair[1];
    server.serializeAttachment({ userId: user.id, sessionId: user.sessionId, expiresAt: user.accessExpiresAt } satisfies SocketAttachment);
    this.ctx.acceptWebSocket(server, [user.id]);
    this.scheduleMaintenance();
    return new Response(null, { status: 101, webSocket: client });
  }
  private async socketAuthorized(socket: WebSocket): Promise<boolean> {
    if (this.env.MAINTENANCE_MODE === '1') return false;
    const attachment = socket.deserializeAttachment() as SocketAttachment | null;
    if (!attachment || attachment.expiresAt <= Date.now()) return false;
    try { this.member(attachment.userId); this.tripRow(); } catch { return false; }
    const session = await this.env.DB.prepare('SELECT 1 FROM sessions s JOIN users u ON s.user_id=u.id WHERE s.id=? AND s.user_id=? AND s.access_expires_at>? AND u.deleting=0').bind(attachment.sessionId, attachment.userId, Date.now()).first();
    // Recheck after external I/O: removal can happen while the D1 read is pending.
    try { this.member(attachment.userId); this.tripRow(); } catch { return false; }
    return Boolean(session);
  }
  private async notify(send = true): Promise<void> {
    for (const socket of this.ctx.getWebSockets()) {
      try {
        if (!await this.socketAuthorized(socket)) { socket.close(1008, 'Membership or session ended'); continue; }
        if (send) { const row = this.tripRow(); socket.send(JSON.stringify({ type: 'changed', revision: row.revision, syncEpoch: this.epoch(row) } satisfies LiveHint)); }
      } catch { socket.close(1011, 'Refresh required'); }
    }
  }
  override async webSocketMessage(socket: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (!await this.socketAuthorized(socket)) { socket.close(1008, 'Membership or session ended'); return; }
    if (typeof message !== 'string' || message !== 'ping') { socket.close(1003, 'Only ping is supported'); return; }
    socket.send('pong');
  }
  override async webSocketClose(socket: WebSocket, code: number): Promise<void> { socket.close(code); }
  override async webSocketError(socket: WebSocket): Promise<void> { socket.close(1011, 'Refresh required'); }
}

/** The civil date (YYYY-MM-DD) at a moment in an IANA time zone. */
function civilDate(timeZone: string, at: number): string {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-US', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(at).map(part => [part.type, part.value]));
  return `${parts.year}-${parts.month}-${parts.day}`;
}
