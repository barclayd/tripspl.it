import type { Expense, Repayment, TripSnapshot } from '../../../contracts/tripsplit-v1';
import { assert } from './errors';
import currencyMetadata from '../../../contracts/currencies.json';
const currencyMinorUnits: Readonly<Record<string, number>> = currencyMetadata.minorUnits;

export function currencyDigits(currency: string): number {
  assert(/^[A-Z]{3}$/.test(currency) && Object.hasOwn(currencyMinorUnits, currency), 'CURRENCY', 'Unsupported ISO 4217 currency.');
  const digits = currencyMinorUnits[currency];
  assert(digits !== undefined, 'CURRENCY', 'Unsupported ISO 4217 currency.');
  return digits;
}
export function minor(value: string): bigint {
  assert(/^(0|[1-9]\d{0,11})$/.test(value), 'AMOUNT', 'Money must be a nonnegative integer string of at most 12 digits.');
  return BigInt(value);
}
export function rateFraction(rate: string): [bigint, bigint] {
  assert(/^(0|[1-9]\d{0,11})(\.\d{1,18})?$/.test(rate), 'RATE', 'Rate must be an exact positive decimal.');
  const [whole = '0', fraction = ''] = rate.split('.');
  assert((whole + fraction).replace(/^0+/, '').length <= 18, 'RATE', 'Rates support at most 18 significant digits.');
  const numerator = BigInt(whole + fraction);
  assert(numerator > 0n, 'RATE', 'Rate must be positive.');
  return [numerator, 10n ** BigInt(fraction.length)];
}
export function convert(amount: string, from: string, to: string, rate: string): string {
  const [numerator, denominator] = rateFraction(rate);
  const n = minor(amount) * numerator * 10n ** BigInt(currencyDigits(to));
  const d = denominator * 10n ** BigInt(currencyDigits(from));
  const result = (n * 2n + d) / (d * 2n);
  assert(result <= 999_999_999_999n, 'AMOUNT', 'Converted amount is too large.');
  return result.toString();
}
export function allocate(amount: string, travellerIds: string[]): Record<string, string> {
  assert(travellerIds.length > 0 && new Set(travellerIds).size === travellerIds.length, 'BENEFICIARIES', 'Use a nonempty, unique beneficiary list.');
  const ids = [...travellerIds].sort();
  const total = minor(amount), count = BigInt(ids.length), base = total / count, remainder = total % count;
  return Object.fromEntries(ids.map((id, index) => [id, (base + (BigInt(index) < remainder ? 1n : 0n)).toString()]));
}
export function homeAmount(record: Expense | Repayment, homeCurrency: string): string | null {
  return record.currency === homeCurrency ? record.amountMinor : record.conversion?.homeAmountMinor ?? null;
}
export interface Ledger {
  actualMinor: string; plannedMinor: string; expectedMinor: string;
  complete: boolean; balancesComplete: boolean; unresolvedIds: string[];
  balances: Record<string, string>; shares: Record<string, string>;
  settlements: { from: string; to: string; amountMinor: string }[];
}
export function ledger(trip: TripSnapshot): Ledger {
  const balances = new Map(trip.travellers.map(t => [t.id, 0n]));
  const shares = new Map(trip.travellers.map(t => [t.id, 0n]));
  const unresolvedIds: string[] = [];
  let actual = 0n, planned = 0n, balancesComplete = true;
  for (const expense of trip.expenses) {
    const amount = homeAmount(expense, trip.homeCurrency);
    if (amount === null) { unresolvedIds.push(expense.id); if (expense.status === 'paid') balancesComplete = false; continue; }
    if (expense.status === 'planned') { planned += BigInt(amount); continue; }
    actual += BigInt(amount);
    balances.set(expense.paidBy, (balances.get(expense.paidBy) ?? 0n) + BigInt(amount));
    for (const [id, share] of Object.entries(allocate(amount, expense.splitWith))) {
      balances.set(id, (balances.get(id) ?? 0n) - BigInt(share));
      shares.set(id, (shares.get(id) ?? 0n) + BigInt(share));
    }
  }
  for (const payment of trip.repayments) {
    const amount = homeAmount(payment, trip.homeCurrency);
    if (amount === null) { unresolvedIds.push(payment.id); balancesComplete = false; continue; }
    balances.set(payment.fromTravellerId, (balances.get(payment.fromTravellerId) ?? 0n) + BigInt(amount));
    balances.set(payment.toTravellerId, (balances.get(payment.toTravellerId) ?? 0n) - BigInt(amount));
  }
  const balanceStrings = Object.fromEntries([...balances].map(([id, value]) => [id, value.toString()]));
  return { actualMinor: actual.toString(), plannedMinor: planned.toString(), expectedMinor: (actual + planned).toString(), complete: unresolvedIds.length === 0, balancesComplete, unresolvedIds, balances: balanceStrings, shares: Object.fromEntries([...shares].map(([id, value]) => [id, value.toString()])), settlements: balancesComplete ? settle(balanceStrings) : [] };
}
export function settle(balances: Record<string, string>): Ledger['settlements'] {
  const debtors: { id: string; amount: bigint }[] = [], creditors: { id: string; amount: bigint }[] = [];
  for (const [id, value] of Object.entries(balances)) {
    const amount = BigInt(value);
    if (amount < 0n) debtors.push({ id, amount: -amount });
    if (amount > 0n) creditors.push({ id, amount });
  }
  const sort = (a: { id: string; amount: bigint }, b: { id: string; amount: bigint }): number => a.amount === b.amount ? (a.id < b.id ? -1 : a.id > b.id ? 1 : 0) : a.amount > b.amount ? -1 : 1;
  const result: Ledger['settlements'] = [];
  debtors.sort(sort); creditors.sort(sort);
  while (debtors.length && creditors.length) {
    const debtor = debtors[0]!, creditor = creditors[0]!;
    const amount = debtor.amount < creditor.amount ? debtor.amount : creditor.amount;
    result.push({ from: debtor.id, to: creditor.id, amountMinor: amount.toString() });
    debtor.amount -= amount; creditor.amount -= amount;
    if (debtor.amount === 0n) debtors.shift();
    if (creditor.amount === 0n) creditors.shift();
  }
  assert(!debtors.length && !creditors.length, 'UNBALANCED', 'Balances must sum to zero.');
  return result;
}
