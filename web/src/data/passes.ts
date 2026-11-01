// Boarding pass art, ported from design/BoardingPasses.dc.html.
// Each flag maps to [primary, secondary, tertiary] colours as oklch [L, C, H].
// Primary is the header band; secondary is the stripe, body tint and accent text
// (falling back to primary when the secondary is white or yellow); tertiary is the plane.
type Lch = readonly [number, number, number];

const R: Lch = [0.56, 0.21, 27];
const B: Lch = [0.5, 0.17, 262];
const Y: Lch = [0.84, 0.17, 92];
const W: Lch = [0.7, 0.05, 250];

const FLAGS: Record<string, readonly [Lch, Lch, Lch]> = {
  '🇫🇷': [B, R, W],
  '🇪🇸': [R, Y, R],
  '🇺🇸': [[0.4, 0.14, 266], R, W],
  '🇬🇧': [[0.46, 0.17, 12], B, W],
};

const clamp01 = (v: number) => Math.max(0, Math.min(1, v));
const ok = ([l, c, h]: Lch, dl = 0, cm = 1) => `oklch(${clamp01(l + dl).toFixed(3)} ${(c * cm).toFixed(3)} ${h})`;

export interface PassPalette {
  pp: string;
  pt: string;
  ps: string;
  p3: string;
  pb: string;
}

export function palette(flag: string): PassPalette {
  const p = FLAGS[flag];
  if (!p) {
    return {
      pp: 'var(--ac)',
      pt: 'var(--acText)',
      ps: 'var(--acDeep)',
      p3: 'var(--ac)',
      pb: 'color-mix(in oklch, var(--ac) 5%, var(--sf))',
    };
  }
  const [a, b, c] = p;
  const band: Lch = a[0] > 0.6 ? [0.6, a[1], a[2]] : a;
  const t = b[1] >= 0.1 && b[0] <= 0.8 ? b : a;
  return {
    pp: ok(band),
    pt: `oklch(from var(--acText) l ${Math.max(0.04, Math.min(t[1], 0.2)).toFixed(3)} ${t[2]})`,
    ps: ok(b, b[0] > 0.8 ? 0 : 0.02),
    p3: ok(c, c[0] > 0.8 ? -0.1 : 0),
    pb: `color-mix(in oklch, ${ok(b)} ${b[1] < 0.06 ? 6 : 9}%, var(--sf))`,
  };
}

function hashStr(s: string) {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

/** A deterministic barcode drawn as a hard-stop linear gradient in currentColor. */
export function barcode(key: string, len = 62, dir = '90deg') {
  let a = hashStr(key || 'x');
  const r = () => {
    a = (a * 1664525 + 1013904223) >>> 0;
    return a / 4294967296;
  };
  const stops: string[] = [];
  let x = 0;
  while (x < len) {
    const w = 1 + Math.floor(r() * 3);
    const g = 1 + Math.floor(r() * 2);
    stops.push(`currentColor ${x}px ${x + w}px`, `transparent ${x + w}px ${x + w + g}px`);
    x += w + g;
  }
  return `linear-gradient(${dir}, ${stops.join(', ')})`;
}

export interface Pass {
  key: string;
  flag: string;
  leg: string;
  from: string;
  fromName: string;
  to: string;
  toName: string;
  fields: readonly [label: string, value: string][];
  stubL: string;
  stubV: string;
}

export const passes: readonly Pass[] = [
  {
    key: 'lp1',
    flag: '🇫🇷',
    leg: 'LEG 1 OF 4',
    from: 'LHR',
    fromName: 'London',
    to: 'CDG',
    toName: 'Paris',
    fields: [
      ['DATE', '12 MAY'],
      ['PAX', '2'],
      ['TRAVEL', '£86'],
    ],
    stubL: 'NIGHTS',
    stubV: '3',
  },
  {
    key: 'lp2',
    flag: '🇪🇸',
    leg: 'LEG 2 OF 4',
    from: 'CDG',
    fromName: 'Paris',
    to: 'MAD',
    toName: 'Madrid',
    fields: [
      ['DATE', '15 MAY'],
      ['PAX', '2'],
      ['TRAVEL', '£74'],
    ],
    stubL: 'NIGHTS',
    stubV: '4',
  },
  {
    key: 'lp3',
    flag: '🇺🇸',
    leg: 'LEG 3 OF 4',
    from: 'MAD',
    fromName: 'Madrid',
    to: 'JFK',
    toName: 'New York',
    fields: [
      ['DATE', '19 MAY'],
      ['PAX', '2'],
      ['TRAVEL', '£412'],
    ],
    stubL: 'NIGHTS',
    stubV: '7',
  },
  {
    key: 'lp4',
    flag: '🇬🇧',
    leg: 'LEG 4 OF 4',
    from: 'JFK',
    fromName: 'New York',
    to: 'LHR',
    toName: 'London',
    fields: [
      ['DATE', '26 MAY'],
      ['PAX', '2'],
      ['TRAVEL', '£398'],
    ],
    stubL: 'WELCOME',
    stubV: 'HOME',
  },
];
