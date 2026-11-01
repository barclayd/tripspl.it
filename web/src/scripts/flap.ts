// Split-flap departure board. Cells are server-rendered with their final text; this blanks them
// and flips each one through the drum to its letter when the board scrolls into view.

const DRUM = ' ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+-./:';
const TICK_MS = 64;
const NBSP = ' ';

type Cell = { el: HTMLElement; top: HTMLElement; bot: HTMLElement; cur: string; next: string; target: string };

const show = (ch: string) => (ch === ' ' ? NBSP : ch);
const step = (ch: string) => DRUM[(DRUM.indexOf(ch) + 1) % DRUM.length] ?? ' ';

function half(kind: 'top' | 'bot', ch: string, leaf: boolean) {
  const h = document.createElement('span');
  h.className = leaf ? `half ${kind} leaf` : `half ${kind}`;
  const g = document.createElement('span');
  g.className = 'glyph';
  g.textContent = show(ch);
  h.append(g);
  return h;
}

function setGlyph(h: HTMLElement, ch: string) {
  const g = h.firstElementChild;
  const text = show(ch);
  if (g && g.textContent !== text) g.textContent = text;
}

function render(c: Cell) {
  const flipping = c.cur !== c.next;
  setGlyph(c.top, flipping ? c.next : c.cur);
  setGlyph(c.bot, c.cur);
  for (const leaf of c.el.querySelectorAll('.leaf')) leaf.remove();
  if (flipping) c.el.append(half('top', c.cur, true), half('bot', c.next, true));
}

function run(flap: HTMLElement) {
  const text = (flap.dataset.flap ?? '').toUpperCase();
  const len = Number(flap.dataset.len ?? text.length);
  const target = text.padEnd(len, ' ').slice(0, len).split('');
  const cells: Cell[] = [...flap.querySelectorAll<HTMLElement>('.cell')].map((el, i) => ({
    el,
    top: el.querySelector<HTMLElement>('.half.top') as HTMLElement,
    bot: el.querySelector<HTMLElement>('.half.bot') as HTMLElement,
    cur: ' ',
    next: ' ',
    target: target[i] ?? ' ',
  }));
  for (const c of cells) render(c);

  let t = 0;
  let timer = 0;
  const tick = () => {
    let busy = false;
    cells.forEach((c, i) => {
      if (c.cur !== c.next) c.cur = c.next;
      if (c.cur !== c.target) {
        busy = true;
        if (t >= i) c.next = DRUM.includes(c.target) ? step(c.cur) : c.target;
      }
      render(c);
    });
    t++;
    if (!busy) clearInterval(timer);
  };
  setTimeout(
    () => {
      timer = window.setInterval(tick, TICK_MS);
    },
    Number(flap.dataset.delay ?? 0),
  );
}

export function initFlaps() {
  const board = document.querySelector<HTMLElement>('[data-board]');
  if (!board) return;
  // With reduced motion the board keeps the final text it was rendered with.
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  const flaps = [...board.querySelectorAll<HTMLElement>('[data-flap]')];
  for (const flap of flaps) {
    for (const g of flap.querySelectorAll('.glyph')) g.textContent = NBSP;
  }

  const io = new IntersectionObserver(
    (entries) => {
      if (!entries.some((e) => e.isIntersecting)) return;
      io.disconnect();
      for (const flap of flaps) run(flap);
    },
    { threshold: 0.6 },
  );
  io.observe(board);
}
