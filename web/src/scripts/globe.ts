// The spinning globe behind the hero title, pinned with the places TripSplit has been.
// One canvas draws; the second half of the torn page copies it so the tear lines up.

import { type GeoPermissibleObjects, geoDistance, geoGraticule10, geoOrthographic, geoPath } from 'd3-geo';
import { feature } from 'topojson-client';
import type { GeometryCollection, Topology } from 'topojson-specification';
import { onTitleVisibility } from './scroll';

const CITIES: [string, number, number, string, string][] = [
  ['London', -0.13, 51.5, '🇬🇧', 'Jan 26'],
  ['New York', -74, 40.7, '🇺🇸', 'Mar 26'],
  ['Tokyo', 139.7, 35.7, '🇯🇵', 'Apr 25'],
  ['Bali', 115.2, -8.4, '🇮🇩', 'Aug 25'],
  ['Buenos Aires', -58.4, -34.6, '🇦🇷', 'Nov 24'],
  ['Mexico City', -99.13, 19.43, '🇲🇽', 'Feb 25'],
  ['Vancouver', -123.12, 49.28, '🇨🇦', 'Jun 24'],
  ['Sydney', 151.21, -33.87, '🇦🇺', 'Dec 24'],
  ['Auckland', 174.76, -36.85, '🇳🇿', 'Jan 25'],
  ['Beijing', 116.4, 39.9, '🇨🇳', 'Oct 25'],
  ['Taipei', 121.56, 25.03, '🇹🇼', 'Nov 27'],
  ['Kathmandu', 85.32, 27.72, '🇳🇵', 'Feb 28'],
  ['Lima', -77.04, -12.05, '🇵🇪', 'Mar 23'],
  ['Budapest', 19.04, 47.5, '🇭🇺', 'Sep 26'],
  ['Cape Town', 18.42, -33.92, '🇿🇦', 'Dec 28'],
  ['Mumbai', 72.88, 19.08, '🇮🇳', 'Mar 26'],
  ['Tunis', 10.18, 36.8, '🇹🇳', 'Jun 23'],
  ['Rabat', -6.84, 34.02, '🇲🇦', 'Sep 27'],
  ['Rio', -43.17, -22.91, '🇧🇷', 'Feb 29'],
];

const ACCENT = 'oklch(0.6 0.23 4)';
const GRATICULE = geoGraticule10();
const SPHERE: GeoPermissibleObjects = { type: 'Sphere' };

let land: GeoPermissibleObjects | null = null;

async function loadLand() {
  const topo = (await import('world-atlas/land-110m.json')).default as unknown as Topology<{
    land: GeometryCollection;
  }>;
  land = feature(topo, topo.objects.land);
}

function draw(canvas: HTMLCanvasElement, dark: boolean, now: number) {
  const S = canvas.clientWidth;
  if (!S) return;
  const dpr = Math.min(2, devicePixelRatio || 1);
  const px = Math.round(S * dpr);
  if (canvas.width !== px) {
    canvas.width = px;
    canvas.height = px;
  }
  const g = canvas.getContext('2d');
  if (!g) return;
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  g.clearRect(0, 0, S, S);

  const r = S / 2 - 4;
  const proj = geoOrthographic()
    .scale(r)
    .translate([S / 2, S / 2])
    .clipAngle(90)
    .rotate([((now / 1000) * 5) % 360, -14]);
  const path = geoPath(proj, g);

  const grd = g.createRadialGradient(S * 0.38, S * 0.32, r * 0.1, S / 2, S / 2, r);
  grd.addColorStop(0, dark ? 'rgba(60,40,48,0.55)' : 'rgba(255,255,255,0.9)');
  grd.addColorStop(1, dark ? 'rgba(30,20,26,0.35)' : 'rgba(252,233,238,0.55)');
  g.beginPath();
  path(SPHERE);
  g.fillStyle = grd;
  g.fill();
  g.lineWidth = 1;
  g.strokeStyle = dark ? 'rgba(255,255,255,0.10)' : 'rgba(22,18,15,0.08)';
  g.stroke();

  g.beginPath();
  path(GRATICULE);
  g.strokeStyle = dark ? 'rgba(255,255,255,0.05)' : 'rgba(22,18,15,0.045)';
  g.lineWidth = 0.6;
  g.stroke();

  if (land) {
    g.beginPath();
    path(land);
    g.fillStyle = dark ? 'rgba(255,255,255,0.10)' : 'rgba(229,38,107,0.10)';
    g.fill();
    g.strokeStyle = dark ? 'rgba(255,255,255,0.14)' : 'rgba(229,38,107,0.18)';
    g.lineWidth = 0.7;
    g.stroke();
  }

  const [rx, ry] = proj.rotate();
  const fs = Math.max(14, S * 0.04);
  const pulse = 7 + ((now / 400) % 4);
  for (const [name, lon, lat, flag, date] of CITIES) {
    const dist = geoDistance([lon, lat], [-rx, -ry]);
    if (dist > Math.PI / 2 - 0.05) continue;
    const p = proj([lon, lat]);
    if (!p) continue;
    const [x, y] = p;
    g.globalAlpha = Math.min(1, (Math.PI / 2 - dist) * 3);

    g.strokeStyle = ACCENT;
    g.lineWidth = 1.5;
    g.beginPath();
    g.moveTo(x, y);
    g.lineTo(x, y - fs * 1.1);
    g.stroke();

    g.fillStyle = ACCENT;
    g.beginPath();
    g.arc(x, y, 3.2, 0, Math.PI * 2);
    g.fill();
    g.fillStyle = 'rgba(229,38,107,0.18)';
    g.beginPath();
    g.arc(x, y, pulse, 0, Math.PI * 2);
    g.fill();

    g.font = `${fs}px "Twemoji Country Flags", system-ui`;
    g.textAlign = 'center';
    g.textBaseline = 'bottom';
    g.fillText(flag, x, y - fs * 1.05);

    g.font = `700 ${Math.round(fs * 0.55)}px -apple-system, system-ui, sans-serif`;
    g.fillStyle = dark ? 'rgba(244,242,238,0.7)' : 'rgba(22,18,15,0.55)';
    g.textBaseline = 'top';
    g.fillText(`${name} · ${date}`, x, y + 6);
    g.globalAlpha = 1;
  }
}

function copy(from: HTMLCanvasElement, to: HTMLCanvasElement) {
  if (to.width !== from.width) {
    to.width = from.width;
    to.height = from.height;
  }
  const g = to.getContext('2d');
  if (!g) return;
  g.clearRect(0, 0, to.width, to.height);
  g.drawImage(from, 0, 0);
}

export function initGlobe() {
  const main = document.querySelector<HTMLCanvasElement>('canvas[data-globe="main"]');
  if (!main) return;
  const mirrors = [...document.querySelectorAll<HTMLCanvasElement>('canvas[data-globe="mirror"]')];
  const darkQuery = matchMedia('(prefers-color-scheme: dark)');
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches;

  const frame = (now: number) => {
    draw(main, darkQuery.matches, now);
    for (const m of mirrors) copy(main, m);
  };

  let raf = 0;
  let titleOpen = true;
  const loop = (now: number) => {
    raf = 0;
    frame(now);
    if (!still && titleOpen && !document.hidden) raf = requestAnimationFrame(loop);
  };
  const kick = () => {
    if (!raf) raf = requestAnimationFrame(loop);
  };

  onTitleVisibility((open) => {
    titleOpen = open;
    if (open) kick();
  });
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) kick();
  });
  // A still globe still needs redrawing when its inputs change.
  addEventListener('resize', kick);
  darkQuery.addEventListener('change', kick);
  loadLand().then(kick, () => {});
  document.fonts?.load('16px "Twemoji Country Flags"', '🇬🇧').then(kick, () => {});
  kick();
}
