/** Transport contract v1. Money values are integer decimal strings; rates are decimal strings. */
export type ID = string;
export type CivilDate = string;
export type MinorUnits = string;
export type CurrencyCode = string;
export type Category = 'food' | 'coffee' | 'stay' | 'activity' | 'transport' | 'shopping' | 'flight' | 'train' | 'taxi' | 'other';
export interface Traveller { id: ID; name: string; hue: number; archived: boolean; revision: number }
export interface Stop { id: ID; countryCode: string; place: string; nights: number; currency: CurrencyCode; latitude: number; longitude: number }
export interface TripDay { id: ID; date: CivilDate; stopId: ID }
export interface TravelLeg { id: ID; kind: 'outbound' | 'transfer' | 'return'; date: CivilDate; fromStopId: ID | null; toStopId: ID | null; dayId: ID | null }
export interface Conversion {
  homeAmountMinor: MinorUnits;
  rate: string;
  rateDate: CivilDate;
  source: string;
  kind: 'reference' | 'manual';
  quoteId: ID | null;
}
export interface Expense {
  id: ID; revision: number;
  attachment: { kind: 'day' | 'leg'; id: ID };
  title: string; category: Category;
  amountMinor: MinorUnits; currency: CurrencyCode;
  status: 'planned' | 'paid'; paidOn: CivilDate | null;
  paidBy: ID; splitWith: ID[];
  conversion: Conversion | null;
}
export interface Repayment {
  id: ID; revision: number; fromTravellerId: ID; toTravellerId: ID;
  amountMinor: MinorUnits; currency: CurrencyCode; paidOn: CivilDate;
  conversion: Conversion | null; note: string;
}
export interface TripSnapshot {
  id: ID; revision: number; syncEpoch: string;
  name: string; startsOn: CivilDate; timeZone: string;
  homeCurrency: CurrencyCode; budgetMinor: MinorUnits;
  ownerTravellerId: ID; currentTravellerId: ID;
  role: 'owner' | 'member';
  travellers: Traveller[]; stops: Stop[]; days: TripDay[]; legs: TravelLeg[];
  expenses: Expense[]; repayments: Repayment[];
  archived: boolean; updatedAt: string;
}
export interface TripSettings {
  name: string; startsOn: CivilDate; timeZone: string;
  homeCurrency: CurrencyCode; budgetMinor: MinorUnits;
  stops: Stop[]; days: TripDay[]; legs: TravelLeg[];
}
export type Operation = { id: ID; syncEpoch: string } & (
  | { type: 'expense.upsert'; entityId: ID; expectedRevision: number | null; payload: Expense }
  | { type: 'expense.delete'; entityId: ID; expectedRevision: number; payload: null }
  | { type: 'repayment.upsert'; entityId: ID; expectedRevision: number | null; payload: Repayment }
  | { type: 'repayment.delete'; entityId: ID; expectedRevision: number; payload: null }
  | { type: 'traveller.upsert'; entityId: ID; expectedRevision: number | null; payload: Traveller }
  | { type: 'trip.update'; entityId: ID; expectedRevision: number; payload: TripSettings }
  | { type: 'trip.archive'; entityId: ID; expectedRevision: number; payload: { archived: boolean } }
);
export interface OperationResult {
  id: ID; status: 'accepted' | 'duplicate' | 'conflict' | 'rejected';
  revision: number | null; code: string | null; message: string | null;
}
export interface SyncRequest { cursor: number | null; syncEpoch: string | null; operations: Operation[] }
export interface SyncResponse { cursor: number; syncEpoch: string; snapshot: TripSnapshot | null; results: OperationResult[] }
export interface User { id: ID; displayName: string }
export interface Session { user: User; accessToken: string; refreshToken: string; expiresAt: string }
export interface AuthChallenge { id: ID; nonce: string; expiresAt: string }
export interface FXQuote {
  id: ID; from: CurrencyCode; to: CurrencyCode; rate: string;
  requestedDate: CivilDate; rateDate: CivilDate; source: string;
}
export interface APIError { error: { code: string; message: string; retryable: boolean } }
