import { describe, expect, it } from 'vitest';
import examples from '../../contracts/money-examples.json';
import { allocate, convert, currencyDigits, ledger, rateFraction } from '../src/utils/money';
import { decimalLexeme } from '../src/services/fx';
import { draft, expense } from './fixtures';

describe('shared exact-money contract', () => {
  for (const value of examples.allocationCases) it(value.name, () => expect(allocate(value.amountMinor, value.travellerIds)).toEqual(value.expected));
  for (const value of examples.conversionCases) it(value.name, () => {
    expect(currencyDigits(value.from)).toBe(value.fromExponent); expect(currencyDigits(value.to)).toBe(value.toExponent);
    expect(convert(value.amountMinor, value.from, value.to, value.rate)).toBe(value.expectedMinor);
  });
  for (const value of examples.ledgerCases) it(value.name, () => {
    const trip = draft(); trip.travellers = value.travellerIds.map(id => ({ id, name: id, hue: 0, archived: false, revision: 1 }));
    trip.expenses = value.expenses.map(item => ({ ...expense(item.id), status: item.status as 'paid' | 'planned', paidBy: item.paidBy, splitWith: item.splitWith, amountMinor: item.homeAmountMinor ?? '1', currency: item.homeAmountMinor === null ? 'USD' : 'GBP' }));
    trip.repayments = value.repayments.map((item, index) => ({ id: `repayment${index}`, revision: 1, fromTravellerId: item.fromTravellerId, toTravellerId: item.toTravellerId, amountMinor: item.homeAmountMinor, currency: 'GBP', paidOn: '2026-10-01', conversion: null, note: '' }));
    const actual = ledger(trip);
    expect({ paidMinor: actual.actualMinor, plannedMinor: actual.plannedMinor, expectedMinor: actual.expectedMinor, balances: actual.balances, paidShares: actual.shares, isComplete: actual.complete, settlements: actual.settlements.map(s => ({ fromTravellerId: s.from, toTravellerId: s.to, amountMinor: s.amountMinor })) }).toEqual(value.expected);
  });
  it('keeps provider decimal lexemes exact, including exponent notation', () => {
    expect(decimalLexeme('0.123456789012345678')).toBe('0.123456789012345678');
    expect(decimalLexeme('5e-7')).toBe('0.0000005');
    expect(() => rateFraction('0.1234567890123456789')).toThrow();
    expect(() => convert('1000000000000', 'GBP', 'GBP', '1')).toThrow();
  });
});
