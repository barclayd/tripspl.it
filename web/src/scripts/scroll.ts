// Scroll engine. Every [data-sc] section gets --p (0 → 1) as it scrolls through its sticky stage;
// CSS turns that into motion. A few numbers on the page are text, so they are bound here.

const clamp = (v: number, lo = 0, hi = 1) => Math.max(lo, Math.min(hi, v));

const gbp = (v: number) =>
  `£${v.toLocaleString('en-GB', { minimumFractionDigits: v % 1 ? 2 : 0, maximumFractionDigits: 2 })}`;

type Progress = Record<string, number>;

// The title page (globe and torn paper) is visible until the hero has torn fully open.
let titleOpen = true;
const titleListeners = new Set<(open: boolean) => void>();

/** Calls back whenever the hero's title page is torn away or comes back. */
export function onTitleVisibility(cb: (open: boolean) => void) {
  titleListeners.add(cb);
  cb(titleOpen);
}

/** Text values bound to [data-bind] and [data-bind-style] elements. */
function values(p: Progress, heroB: number): Record<string, string> {
  const soloSpent = (
    [
      [2.5, 1180],
      [3.5, 96],
      [4.5, 140],
      [5.5, 85],
    ] as const
  ).reduce((sum, [k, v]) => sum + (heroB * 7 - k >= 0.6 ? v : 0), 0);
  const soloLeft = 5000 - soloSpent;

  const groupP = Math.min(1, (p.group ?? 0) * 1.4);
  const budgetP = Math.min(1, (p.budget ?? 0) * 1.4);

  const amounts = [10, 24, 42, 85, 120];
  const euros = amounts[Math.min(amounts.length - 1, Math.floor((p.convert ?? 0) * amounts.length))] ?? 120;
  const pounds = euros * 0.862;

  return {
    soloLeft: gbp(soloLeft),
    soloPct: `${soloLeft / 50}%`,
    soloDay: `${gbp(Math.round(soloLeft / 12))} a day`,
    groupTotal: gbp(Math.round(3659 * groupP)),
    dayTotal: gbp(Math.round(58.97 * budgetP * 100) / 100),
    dayLeft: `${gbp(Math.round(300 - 58.97 * budgetP))} left today`,
    cvIn: `€${euros}`,
    cvOut: gbp(Math.round(pounds * 100) / 100),
    cvPct: `${Math.round((pounds / 300) * 100)}% of a day's budget`,
    cvBar: `${Math.min(100, (pounds / 300) * 100)}%`,
  };
}

const setText = (el: Element, text: string) => {
  if (el.textContent !== text) el.textContent = text;
};

/** The receipt prints character by character as the split section scrolls. */
function printReceipt(rc: HTMLElement, sp: number) {
  const lines = [...rc.querySelectorAll<HTMLElement>('[data-ln]')];
  const total = lines.reduce((sum, ln) => {
    if (ln.dataset.ln === 'dash') return sum + 4;
    return sum + (ln.dataset.l ?? '').length + (ln.dataset.r ?? '').length;
  }, 0);
  let budget = Math.floor(clamp((sp - 0.04) / 0.56) * total);

  let parentShown = false;
  for (const ln of lines) {
    const kind = ln.dataset.ln;
    if (kind === 'sub') {
      // A payer line is printed straight after its item, and its face drops in from below.
      ln.hidden = !parentShown;
      const label = ln.dataset.l ?? '';
      const m = parentShown ? clamp(budget, 0, label.length) : 0;
      if (parentShown) budget -= label.length;
      const q = parentShown && budget >= 0 ? Math.min(1, budget / 14 + 0.25) : 0;
      const [left] = ln.children;
      if (left) setText(left, label.slice(0, m));
      const face = ln.querySelector<HTMLElement>('[data-face]');
      if (face) {
        face.hidden = m <= 0;
        face.style.opacity = String(Math.min(1, m / 4));
        face.style.transform = `translateY(${((1 - q) * 70).toFixed(1)}vh) rotate(${(Math.sin(q * 9) * (1 - q) * 14).toFixed(1)}deg)`;
        const string = face.querySelector<HTMLElement>('.string');
        if (string) string.style.height = `${Math.round((1 - q) * 46)}px`;
      }
      continue;
    }

    parentShown = budget > 0;
    ln.hidden = !parentShown;
    if (!parentShown) continue;
    if (kind === 'dash') {
      budget -= 4;
      continue;
    }
    const l = ln.dataset.l ?? '';
    const r = ln.dataset.r ?? '';
    const n = Math.min(budget, l.length + r.length);
    budget -= l.length + r.length;
    const [left, right] = ln.children;
    if (left) setText(left, l.slice(0, Math.min(n, l.length)));
    if (right) setText(right, n > l.length ? r.slice(0, n - l.length) : '');
  }
}

export function initScroll() {
  const sections = [...document.querySelectorAll<HTMLElement>('[data-sc]')];
  if (!sections.length) return;
  const binds = [...document.querySelectorAll<HTMLElement>('[data-bind]')];
  const styleBinds = [...document.querySelectorAll<HTMLElement>('[data-bind-style]')];
  const receipt = document.querySelector<HTMLElement>('[data-rc]');

  let frame = 0;
  const set = (el: HTMLElement, name: string, v: string) => {
    if (el.style.getPropertyValue(name) !== v) el.style.setProperty(name, v);
  };

  const update = () => {
    frame = 0;
    const vw = innerWidth;
    const vh = innerHeight;
    const fit = clamp(vh / (vw < 900 ? 1180 : 820), 0.6, 1).toFixed(3);
    const fitB = clamp((vh - 90) / 600, 0.55, 1).toFixed(3);
    const p: Progress = {};
    let heroB = 0;

    for (const el of sections) {
      const r = el.getBoundingClientRect();
      const v = clamp(-r.top / Math.max(1, r.height - vh));
      const name = el.dataset.sc ?? '';
      p[name] = v;
      set(el, '--p', v.toFixed(4));
      set(el, '--fit', fit);
      set(el, '--fitB', fitB);

      if (name === 'hero') {
        const narrow = vw < 700;
        const ps = narrow ? Math.min(0.56, (vw - 36) / 680) : clamp((vw - 380) / 680, 0.55, 1);
        const phS = narrow ? Math.min(0.62, (vh - 330) / 620) : 1;
        const t = Math.min(1, v / 0.2);
        heroB = clamp((v - 0.6) / 0.36);
        set(el, '--pscale', ps.toFixed(3));
        set(el, '--phS', phS.toFixed(3));
        set(el, '--px', `${(narrow ? 170 * ps + 4 : 170 + 170 * ps).toFixed(1)}px`);
        set(el, '--py', `${(narrow ? 310 * phS + 80 * ps + 10 : 112).toFixed(1)}px`);
        set(el, '--fitB', clamp((vh - 90) / 560, 0.55, 1).toFixed(3));
        set(el, '--t', t.toFixed(4));
        set(el, '--te', (t ** 1.7).toFixed(4));
        set(el, '--a', clamp((v - 0.12) / 0.4).toFixed(4));
        set(el, '--b', heroB.toFixed(4));
        const open = t < 1;
        if (open !== titleOpen) {
          titleOpen = open;
          for (const cb of titleListeners) cb(open);
        }
      }
    }

    const vals = values(p, heroB);
    for (const el of binds) {
      const key = el.dataset.bind;
      const text = key ? vals[key] : undefined;
      if (text !== undefined) setText(el, text);
    }
    for (const el of styleBinds) {
      const [prop, key] = (el.dataset.bindStyle ?? '').split(':');
      const v = key ? vals[key] : undefined;
      if (prop && v !== undefined && el.style.getPropertyValue(prop) !== v) el.style.setProperty(prop, v);
    }
    if (receipt) printReceipt(receipt, p.split ?? 0);
  };

  const schedule = () => {
    if (!frame) frame = requestAnimationFrame(update);
  };
  addEventListener('scroll', schedule, { passive: true });
  addEventListener('resize', schedule);
  update();
}
