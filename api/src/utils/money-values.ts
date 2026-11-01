import { assert } from './errors';
import currencyMetadata from '../data/currencies.json';

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
