import { onSectionDepth } from './scroll';

// Split-flap departure board. Cells are server-rendered with their final text; this blanks them and, once the
// board has pinned, flips each one through the drum to its letter as the reader scrolls. Nothing runs on a timer:
// the scroll position sets a board clock, and every letter and leaf angle follows from it.

const DRUM = ' ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+-./:';
/** One flip on the board clock (ms). Each cell starts a tick after its left neighbour and flips once a tick. */
const TICK = 64;
/**
 * Where the clock runs, in viewport heights scrolled into the section: [start, length]. It starts as the board
 * pins, and the section's height in Departures.astro keeps the board pinned until every cell has landed.
 */
const FLIP = [0, 1.5] as const;

type Cell = {
  top: HTMLElement;
  bot: HTMLElement;
  /** The falling top half of the old letter and the dropping bottom half of the new one. */
  leafTop: HTMLElement;
  leafBot: HTMLElement;
  /** Board clock of this cell's first flip. */
  start: number;
  /** Flips from blank to its letter. */
  steps: number;
  target: string;
  /** The flip shown: 0 before the first, steps + 1 once landed. */
  flip: number;
};

const show = (ch: string) => (ch === ' ' ? ' ' : ch);
/** The letter a cell shows k flips from blank. */
const charAt = (c: Cell, k: number) => (k >= c.steps ? c.target : (DRUM[k] ?? ' '));

function setGlyph(h: HTMLElement, ch: string) {
  const g = h.firstElementChild;
  const text = show(ch);
  if (g && g.textContent !== text) g.textContent = text;
}

function setStyle(el: HTMLElement, prop: 'transform' | 'visibility', v: string) {
  if (el.style[prop] !== v) el.style[prop] = v;
}

function leaf(cell: HTMLElement, kind: 'top' | 'bot') {
  const h = document.createElement('span');
  h.className = `half ${kind} leaf`;
  h.style.visibility = 'hidden';
  const g = document.createElement('span');
  g.className = 'glyph';
  h.append(g);
  cell.append(h);
  return h;
}

function cellsOf(flap: HTMLElement, leaves: boolean): Cell[] {
  const text = (flap.dataset.flap ?? '').toUpperCase();
  const len = Number(flap.dataset.len ?? text.length);
  const delay = Number(flap.dataset.delay ?? 0);
  const target = text.padEnd(len, ' ').slice(0, len).split('');
  return [...flap.querySelectorAll<HTMLElement>('.cell')].map((el, i) => {
    const ch = target[i] ?? ' ';
    const at = DRUM.indexOf(ch);
    const top = el.querySelector<HTMLElement>('.half.top') as HTMLElement;
    const bot = el.querySelector<HTMLElement>('.half.bot') as HTMLElement;
    setGlyph(top, ' ');
    setGlyph(bot, ' ');
    return {
      top,
      bot,
      leafTop: leaves ? leaf(el, 'top') : top,
      leafBot: leaves ? leaf(el, 'bot') : bot,
      start: delay + (i + 1) * TICK,
      steps: at >= 0 ? at : 1,
      target: ch,
      flip: -1,
    };
  });
}

/** Shows a cell u flips into its run (fractional while a leaf is mid-fall). */
function paint(c: Cell, u: number, leaves: boolean) {
  const flip = u < 0 ? 0 : Math.min(c.steps + 1, Math.floor(u) + 1);
  const moving = flip >= 1 && flip <= c.steps;
  const f = moving ? u - (flip - 1) : 0;

  if (!leaves) {
    // Reduced motion: letters swap halfway through each flip, with no leaves.
    const ch = charAt(c, moving ? flip - (f < 0.5 ? 1 : 0) : flip && c.steps);
    setGlyph(c.top, ch);
    setGlyph(c.bot, ch);
    return;
  }

  if (flip !== c.flip) {
    c.flip = flip;
    const from = moving ? charAt(c, flip - 1) : charAt(c, flip && c.steps);
    const to = moving ? charAt(c, flip) : from;
    setGlyph(c.top, to);
    setGlyph(c.bot, from);
    setGlyph(c.leafTop, from);
    setGlyph(c.leafBot, to);
    setStyle(c.leafTop, 'visibility', moving ? '' : 'hidden');
    setStyle(c.leafBot, 'visibility', moving ? '' : 'hidden');
  }
  if (moving) {
    // The old letter's top half falls away (easing in), then the new letter's bottom half drops over the old one
    // (easing out). A leaf at angle θ from flat shows cos θ of its height; a 2D scale keeps every leaf off its own
    // compositor layer, which 3D rotateX would put up to 184 of on screen at once.
    const fold = (t: number) => Math.cos((Math.PI / 2) * t ** 2).toFixed(3);
    setStyle(c.leafTop, 'transform', `scaleY(${f < 0.5 ? fold(2 * f) : 0})`);
    setStyle(c.leafBot, 'transform', `scaleY(${f < 0.5 ? 0 : fold(2 - 2 * f)})`);
  }
}

export function initFlaps() {
  const board = document.querySelector<HTMLElement>('[data-board]');
  if (!board) return;
  // Reduced motion keeps the scrubbing (it follows the reader's own scrolling) but drops the falling leaves.
  const leaves = !matchMedia('(prefers-reduced-motion: reduce)').matches;
  const cells = [...board.querySelectorAll<HTMLElement>('[data-flap]')].flatMap((f) => cellsOf(f, leaves));
  // The clock runs until the last cell's last flip has landed.
  const end = Math.max(...cells.map((c) => c.start + c.steps * TICK));

  onSectionDepth('dep', (s) => {
    const clock = Math.min(1, Math.max(0, (s - FLIP[0]) / FLIP[1])) * end;
    for (const c of cells) paint(c, (clock - c.start) / TICK, leaves);
  });
}
