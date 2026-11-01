import type { Conversion, Expense, FXQuote, Repayment } from '../../../contracts/tripsplit-v1';
import { AppError, assert } from '../utils/errors';
import { convert, currencyDigits, rateFraction } from '../utils/money';
import { civil, parse } from '../schemas/trip';

type QuoteRow = { id: string; from_currency: string; to_currency: string; requested_date: string; rate_date: string; rate: string; source: string };
function fromRow(row: QuoteRow): FXQuote { return { id: row.id, from: row.from_currency, to: row.to_currency, requestedDate: row.requested_date, rateDate: row.rate_date, rate: row.rate, source: row.source }; }
// Read the JSON numeric lexeme, never pass a financial rate through a binary float.
export function decimalLexeme(value: string): string {
  const match = /^(\d+)(?:\.(\d+))?(?:[eE]([+-]?\d+))?$/.exec(value);
  assert(match, 'FX_RESPONSE', 'Invalid provider rate.', 502);
  const digits = match[1]! + (match[2] ?? '');
  const decimalIndex = match[1]!.length + Number(match[3] ?? '0');
  assert(Math.abs(decimalIndex) < 32, 'FX_RESPONSE', 'Invalid provider rate.', 502);
  const expanded = decimalIndex <= 0 ? '0.' + '0'.repeat(-decimalIndex) + digits : decimalIndex >= digits.length ? digits + '0'.repeat(decimalIndex - digits.length) : digits.slice(0, decimalIndex) + '.' + digits.slice(decimalIndex);
  const normalized = expanded.replace(/^(0+)(?=\d)/, '').replace(/(\.\d*?)0+$/, '$1').replace(/\.$/, '');
  rateFraction(normalized);
  return normalized;
}
export async function getFX(env: Env, from: string, to: string, date: string): Promise<FXQuote> {
  currencyDigits(from); currencyDigits(to); parse(civil, date);
  assert(date <= new Date().toISOString().slice(0, 10), 'FX_DATE', 'Future rates are not available.');
  const cached = await env.DB.prepare('SELECT * FROM fx_quotes WHERE from_currency=? AND to_currency=? AND requested_date=?').bind(from, to, date).first<QuoteRow>();
  if (cached) return fromRow(cached);
  let rate = '1', rateDate = date;
  if (from !== to) {
    const url = new URL(`https://api.frankfurter.dev/v2/rate/${from.toLowerCase()}/${to.toLowerCase()}`); url.searchParams.set('date', date);
    let response: Response;
    try { response = await fetch(url, { signal: AbortSignal.timeout(8000), headers: { Accept: 'application/json' } }); }
    catch { throw new AppError(503, 'FX_UNAVAILABLE', 'A reference rate is temporarily unavailable. Keep the original amount or enter a manual conversion.', true); }
    if (!response.ok) throw new AppError(503, 'FX_UNAVAILABLE', 'No reference rate is available for this currency and date.', true);
    const text = await limitedText(response, 8192);
    let data: { date?: unknown; base?: unknown; quote?: unknown };
    try { data = JSON.parse(text); } catch { throw new AppError(502, 'FX_RESPONSE', 'Invalid rate provider response.', true); }
    assert(data.base === from && data.quote === to && typeof data.date === 'string', 'FX_RESPONSE', 'Rate provider returned an unexpected pair.', 502);
    rateDate = parse(civil, data.date);
    assert(rateDate <= date, 'FX_RESPONSE', 'Rate provider returned a future rate.', 502);
    const match = /"rate"\s*:\s*(\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)(?=\s*[,}])/.exec(text);
    assert(match, 'FX_RESPONSE', 'Rate provider did not return a numeric rate.', 502);
    rate = decimalLexeme(match[1]!);
  }
  const quote: FXQuote = { id: crypto.randomUUID(), from, to, requestedDate: date, rateDate, rate, source: from === to ? 'identity' : 'Frankfurter reference' };
  await env.DB.prepare('INSERT OR IGNORE INTO fx_quotes (id,from_currency,to_currency,requested_date,rate_date,rate,source) VALUES (?,?,?,?,?,?,?)').bind(quote.id, from, to, date, rateDate, rate, quote.source).run();
  const stored = await env.DB.prepare('SELECT * FROM fx_quotes WHERE from_currency=? AND to_currency=? AND requested_date=?').bind(from, to, date).first<QuoteRow>();
  assert(stored, 'FX_STORAGE', 'Could not store the reference quote.', 503);
  return fromRow(stored);
}
export async function limitedText(response: Response, maximum: number): Promise<string> {
  const reader = response.body?.getReader();
  assert(reader, 'PROVIDER_RESPONSE', 'The provider returned an empty response.', 502);
  let text = '', length = 0;
  const decoder = new TextDecoder();
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > maximum) { await reader.cancel(); throw new AppError(502, 'PROVIDER_RESPONSE', 'The provider returned too much data.', true); }
    text += decoder.decode(value, { stream: true });
  }
  return text + decoder.decode();
}
export async function normalizeConversion<T extends Expense | Repayment>(env: Env, record: T, homeCurrency: string, quotes?: Map<string, QuoteRow>): Promise<T> {
  if (record.currency === homeCurrency) return { ...record, conversion: null };
  const conversion = record.conversion;
  if (conversion === null) return record;
  let normalized: Conversion;
  if (conversion.kind === 'manual') {
    assert(conversion.quoteId === null, 'MANUAL_QUOTE', 'Manual conversions cannot claim a reference quote.');
    // Card charges may specify the actual home total independently of the indicative rate.
    normalized = { ...conversion, source: 'Manual: ' + conversion.source.replace(/^Manual: /, '').slice(0, 110) };
  } else {
    assert(conversion.quoteId, 'FX_QUOTE', 'A reference conversion needs a quote ID.');
    const row = quotes ? quotes.get(conversion.quoteId) : await env.DB.prepare('SELECT * FROM fx_quotes WHERE id=?').bind(conversion.quoteId).first<QuoteRow>();
    assert(row && row.from_currency === record.currency && row.to_currency === homeCurrency, 'FX_QUOTE', 'Reference quote does not match the currency pair.');
    normalized = { kind: 'reference', quoteId: row.id, rate: row.rate, rateDate: row.rate_date, source: row.source, homeAmountMinor: convert(record.amountMinor, record.currency, homeCurrency, row.rate) };
  }
  return { ...record, conversion: normalized };
}

export async function normalizeRecords(env: Env, records: (Expense | Repayment)[], homeCurrency: string): Promise<(Expense | Repayment)[]> {
  const ids = [...new Set(records.filter(record => record.currency !== homeCurrency && record.conversion?.kind === 'reference').map(record => record.conversion!.quoteId).filter((id): id is string => id !== null))];
  const quotes = new Map<string, QuoteRow>();
  for (let offset = 0; offset < ids.length; offset += 100) {
    const batch = ids.slice(offset, offset + 100);
    const result = await env.DB.prepare(`SELECT * FROM fx_quotes WHERE id IN (${batch.map(() => '?').join(',')})`).bind(...batch).all<QuoteRow>();
    for (const row of result.results) quotes.set(row.id, row);
  }
  const normalized: (Expense | Repayment)[] = [];
  for (const record of records) normalized.push(await normalizeConversion(env, record, homeCurrency, quotes));
  return normalized;
}
