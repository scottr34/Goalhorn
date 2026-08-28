// Generates the .dc.html artboards for the Goalhorn main-screen redesign.
//   node design/main-screen/build.mjs
//
// The fixture is modelled on the classic rink goal light the user referenced:
// a TALL vertically-fluted red lens, a thin bright wire guard, and a heavy
// satin-aluminium base that flares out at the foot. Geometry (flute and cage
// azimuths, hoop perspective, cylinder shading) is computed here so every
// artboard stays consistent.
//
// No brand marks are reproduced - the reference carries a brewery logo on the
// mid band; that band is left as plain riveted hardware.

import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const OUT = dirname(fileURLToPath(import.meta.url));

const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const toHex = (rgb) =>
  '#' + rgb.map((v) => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0')).join('');
/** Scale a hex colour toward black by factor f (1 = unchanged). */
const dim = (h, f) => toHex(hex(h).map((v) => v * f));
const rad = (deg) => (deg * Math.PI) / 180;

// ------------------------------------------------------------ lamp geometry
// SVG user space: viewBox 0 0 440 700.
//   lens    R=118 about cx=220, hemispherical cap y 40..158, tube y 158..366
//   guard   R=125, standing proud of the lens
//   base    four tiers, y 356..654, each a CYLINDER (shaded left-to-right)
//   camera  eye level y=340, which sets hoop curvature and the tier ellipses

const CX = 220;
const R_LENS = 118;
const R_CAGE = 125;
const Y_APEX = 40;
const Y_SHOULDER = 158;
const Y_LENS_BOT = 406;
const Y_CAGE_APEX = 34;
const RV_CAGE = Y_SHOULDER - Y_CAGE_APEX;
const EYE = 340;

const LENS_PATH =
  `M ${CX - R_LENS},${Y_LENS_BOT} L ${CX - R_LENS},${Y_SHOULDER} ` +
  `A ${R_LENS},${Y_SHOULDER - Y_APEX} 0 0 1 ${CX + R_LENS},${Y_SHOULDER} ` +
  `L ${CX + R_LENS},${Y_LENS_BOT} Z`;

// --- vertical flutes -------------------------------------------------------
// The lens is a fluted Fresnel cylinder. Flutes are evenly spaced in ANGLE, so
// on screen they bunch toward the silhouette exactly like the guard wires do.
// This is the strongest single cue that the red thing is glass and not a shape.
const FLUTE_TOP = Y_SHOULDER - 30;
const FLUTE_H = Y_LENS_BOT - FLUTE_TOP;
const FLUTES = [];
for (let deg = -84; deg <= 84; deg += 8) {
  const c = Math.cos(rad(deg));
  FLUTES.push({
    groove: +(CX + R_LENS * Math.sin(rad(deg))).toFixed(2),
    gw: +Math.max(0.9, 2.6 * c).toFixed(2),
    ridge: +(CX + R_LENS * Math.sin(rad(deg + 4))).toFixed(2),
    rw: +Math.max(0.9, 3.1 * c).toFixed(2),
  });
}

// --- guard wires -----------------------------------------------------------
const PHI_RING = Math.asin(20 / R_CAGE);
const RING_TILT = 5;
const RING_CY = +(Y_CAGE_APEX + RV_CAGE * (1 - Math.cos(PHI_RING))).toFixed(2);

/** A point on the guard meridian at azimuth t, polar angle phi from the apex. */
function meridian(t, phi) {
  return [
    CX + R_CAGE * Math.sin(phi) * Math.sin(t),
    Y_CAGE_APEX + RV_CAGE * (1 - Math.cos(phi)) - RING_TILT * Math.cos(t) * Math.cos(phi),
  ];
}

const BAR_ANGLES = [0, 20, -20, 40, -40, 60, -60, 80, -80];
const BARS = BAR_ANGLES.map((deg, i) => {
  const t = rad(deg);
  const x = +(CX + R_CAGE * Math.sin(t)).toFixed(2);
  const k = Math.abs(Math.cos(t)); // how square-on this wire faces us
  const w = +(6.4 * (0.32 + 0.68 * k)).toFixed(2);
  let d = `M ${x},414 L ${x},${Y_SHOULDER - 2}`;
  const steps = 8;
  for (let j = 1; j <= steps; j++) {
    const phi = Math.PI / 2 + (PHI_RING - Math.PI / 2) * (j / steps);
    const [px, py] = meridian(t, phi);
    d += ` L ${px.toFixed(2)},${py.toFixed(2)}`;
  }
  return { id: `bar${i}`, x, w, k, d };
});

// A hoop above eye level shows its near half as the TOP of the projected
// ellipse (bulges up); below eye level the near half sags down.
const HOOPS = [84, 132, 206, 282, 358].map((y, i) => {
  const dy = Y_SHOULDER - y;
  const halfW = dy > 0 ? R_CAGE * Math.sqrt(Math.max(0, 1 - (dy / RV_CAGE) ** 2)) : R_CAGE + 6;
  const rise = ((EYE - y) / 300) * 13;
  return {
    id: `hoop${i}`,
    y,
    front: `M ${(CX - halfW).toFixed(1)},${y} Q ${CX},${(y - 2 * rise).toFixed(1)} ${(CX + halfW).toFixed(1)},${y}`,
    back: `M ${(CX - halfW).toFixed(1)},${y} Q ${CX},${(y + 2 * rise).toFixed(1)} ${(CX + halfW).toFixed(1)},${y}`,
  };
});

// --- base tiers ------------------------------------------------------------
// Each tier is a cylinder, so it is shaded ACROSS (dark edge, bright band,
// bounce on the far side) - a top-to-bottom ramp would read as a flat slab.
const T = {
  collar: { x: 90, w: 260, y: 396, h: 36 },
  body: { x: 96, w: 248, y: 430, h: 96 },
  band: { x: 88, w: 264, y: 522, h: 96 },
  skirtTopY: 614,
  skirtBotY: 674,
  skirtBotX: 54,
  skirtBotW: 332,
  lip: { x: 50, w: 340, y: 670, h: 24 },
};

// ------------------------------------------------------------------- defs

function defs() {
  const barGrads = BARS.map((b) => {
    const k = b.k;
    const stops = [
      [0, '#161513', 1],
      [0.16, '#6a655c', 0.6 + 0.4 * k],
      [0.38, '#e8e2d5', 0.55 + 0.45 * k],
      [0.56, '#a49d92', 0.58 + 0.42 * k],
      [0.78, '#48453f', 0.7 + 0.3 * k],
      [1, '#121110', 1],
    ]
      .map(([o, c, f]) => `<stop offset="${o}" stop-color="${dim(c, f)}"></stop>`)
      .join('');
    return `<linearGradient id="g_${b.id}" gradientUnits="userSpaceOnUse" x1="${(b.x - b.w / 2).toFixed(2)}" y1="0" x2="${(b.x + b.w / 2).toFixed(2)}" y2="0">${stops}</linearGradient>`;
  }).join('');

  const hoopGrads = HOOPS.map(
    (h) =>
      `<linearGradient id="g_${h.id}" gradientUnits="userSpaceOnUse" x1="0" y1="${h.y - 3.4}" x2="0" y2="${h.y + 3.4}">` +
      `<stop offset="0" stop-color="#171614"></stop>` +
      `<stop offset="0.3" stop-color="#ded8cb"></stop>` +
      `<stop offset="0.55" stop-color="#8e8880"></stop>` +
      `<stop offset="0.8" stop-color="#3c3a35"></stop>` +
      `<stop offset="1" stop-color="#131211"></stop>` +
      `</linearGradient>`
  ).join('');

  // Satin aluminium, shaded as a cylinder: key highlight left of centre, a dark
  // turn, then a weaker bounce off the room on the right.
  const metal = (id, f) =>
    `<linearGradient id="${id}" x1="0" y1="0" x2="1" y2="0">` +
    [
      [0, '#3f3b35'],
      [0.06, '#6b665d'],
      [0.22, '#cec8ba'],
      [0.34, '#b3ada0'],
      [0.5, '#8d887e'],
      [0.68, '#615d56'],
      [0.85, '#9c978c'],
      [1, '#3a3731'],
    ]
      .map(([o, c]) => `<stop offset="${o}" stop-color="${dim(c, f)}"></stop>`)
      .join('') +
    `</linearGradient>`;

  return `<defs>
  <clipPath id="clipLens"><path d="${LENS_PATH}"></path></clipPath>
  <linearGradient id="gFluteFade" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#fff" stop-opacity="0"></stop>
    <stop offset="0.24" stop-color="#fff" stop-opacity="1"></stop>
    <stop offset="1" stop-color="#fff" stop-opacity="1"></stop>
  </linearGradient>
  <mask id="fluteMask"><rect x="102" y="${FLUTE_TOP}" width="236" height="${FLUTE_H}" fill="url(#gFluteFade)"></rect></mask>

  <!-- Lens, unlit: deep cherry, near-black where it turns away. -->
  <radialGradient id="gGlass" cx="0.4" cy="0.3" r="0.9">
    <stop offset="0" stop-color="#a51e19"></stop>
    <stop offset="0.3" stop-color="#78100e"></stop>
    <stop offset="0.62" stop-color="#450807"></stop>
    <stop offset="1" stop-color="#1c0303"></stop>
  </radialGradient>
  <!-- Lens, lit: the lamp fills the tube and blows out low-centre. -->
  <radialGradient id="gHot" cx="0.5" cy="0.6" r="0.95">
    <stop offset="0" stop-color="#fff5ef"></stop>
    <stop offset="0.12" stop-color="#ffa082"></stop>
    <stop offset="0.36" stop-color="#ff2a12"></stop>
    <stop offset="0.68" stop-color="#c00806"></stop>
    <stop offset="1" stop-color="#5c0100"></stop>
  </radialGradient>
  <!-- Cylinder form: the left-right falloff that makes a tube read as a tube. -->
  <linearGradient id="gCyl" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#000" stop-opacity="0.74"></stop>
    <stop offset="0.13" stop-color="#000" stop-opacity="0.24"></stop>
    <stop offset="0.34" stop-color="#fff" stop-opacity="0.08"></stop>
    <stop offset="0.6" stop-color="#000" stop-opacity="0.12"></stop>
    <stop offset="0.86" stop-color="#000" stop-opacity="0.6"></stop>
    <stop offset="1" stop-color="#000" stop-opacity="0.82"></stop>
  </linearGradient>
  <linearGradient id="gCapDark" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#000" stop-opacity="0.3"></stop>
    <stop offset="0.16" stop-color="#000" stop-opacity="0"></stop>
    <stop offset="0.88" stop-color="#000" stop-opacity="0"></stop>
    <stop offset="1" stop-color="#000" stop-opacity="0.5"></stop>
  </linearGradient>
  <radialGradient id="gSpec"><stop offset="0" stop-color="#fff" stop-opacity="0.42"></stop><stop offset="0.55" stop-color="#fff" stop-opacity="0.11"></stop><stop offset="1" stop-color="#fff" stop-opacity="0"></stop></radialGradient>
  <radialGradient id="gSpecCap"><stop offset="0" stop-color="#fff" stop-opacity="0.34"></stop><stop offset="1" stop-color="#fff" stop-opacity="0"></stop></radialGradient>
  <radialGradient id="gShadow"><stop offset="0" stop-color="#000" stop-opacity="0.75"></stop><stop offset="0.55" stop-color="#000" stop-opacity="0.28"></stop><stop offset="1" stop-color="#000" stop-opacity="0"></stop></radialGradient>
  <radialGradient id="gColumn"><stop offset="0" stop-color="#fff2e8" stop-opacity="0.85"></stop><stop offset="0.55" stop-color="#ff7a4a" stop-opacity="0.3"></stop><stop offset="1" stop-color="#ff4a1e" stop-opacity="0"></stop></radialGradient>

  ${metal('gMetal', 1)}
  ${metal('gMetalHi', 1.12)}
  ${metal('gMetalLo', 0.78)}
  <radialGradient id="gRivet" cx="0.34" cy="0.3">
    <stop offset="0" stop-color="#e4ded1"></stop>
    <stop offset="0.5" stop-color="#8e8980"></stop>
    <stop offset="1" stop-color="#33302b"></stop>
  </radialGradient>
  <linearGradient id="gRing" gradientUnits="userSpaceOnUse" x1="0" y1="${RING_CY - 8}" x2="0" y2="${RING_CY + 8}">
    <stop offset="0" stop-color="#cac4b7"></stop>
    <stop offset="0.4" stop-color="#7d786f"></stop>
    <stop offset="1" stop-color="#26241f"></stop>
  </linearGradient>
  <linearGradient id="gHoopFade" gradientUnits="userSpaceOnUse" x1="${CX - R_CAGE - 6}" y1="0" x2="${CX + R_CAGE + 6}" y2="0">
    <stop offset="0" stop-color="#0a0908" stop-opacity="0.85"></stop>
    <stop offset="0.2" stop-color="#0a0908" stop-opacity="0.25"></stop>
    <stop offset="0.5" stop-color="#0a0908" stop-opacity="0"></stop>
    <stop offset="0.8" stop-color="#0a0908" stop-opacity="0.25"></stop>
    <stop offset="1" stop-color="#0a0908" stop-opacity="0.85"></stop>
  </linearGradient>

  <filter id="fb3" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="3"></feGaussianBlur></filter>
  <filter id="fb6" x="-45%" y="-45%" width="190%" height="190%"><feGaussianBlur stdDeviation="6"></feGaussianBlur></filter>
  <filter id="fb18" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="18"></feGaussianBlur></filter>
  <filter id="grainF"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="3" stitchTiles="stitch"></feTurbulence></filter>
  ${barGrads}${hoopGrads}
</defs>`;
}

// -------------------------------------------------------------- lamp markup

function flutes() {
  const out = FLUTES.map(
    (f) =>
      `<rect x="${(f.ridge - f.rw / 2).toFixed(2)}" y="${FLUTE_TOP}" width="${f.rw}" height="${FLUTE_H}" fill="#fff" opacity="0.16"></rect>` +
      `<rect x="${(f.groove - f.gw / 2).toFixed(2)}" y="${FLUTE_TOP}" width="${f.gw}" height="${FLUTE_H}" fill="#1a0000" opacity="0.36"></rect>`
  ).join('');
  return `<g mask="url(#fluteMask)">${out}</g>`;
}

function cage() {
  const barPaths = (stroke) =>
    BARS.map(
      (b) =>
        `<path d="${b.d}" fill="none" stroke="${stroke === null ? `url(#g_${b.id})` : stroke}" stroke-width="${b.w}" stroke-linecap="round"></path>`
    ).join('');
  const hoopPaths = (stroke) =>
    HOOPS.map(
      (h) =>
        `<path d="${h.front}" fill="none" stroke="${stroke === null ? `url(#g_${h.id})` : stroke}" stroke-width="6" stroke-linecap="round"></path>`
    ).join('');

  return `<g class="cage">
    <g clip-path="url(#clipLens)" transform="translate(2,3)" filter="url(#fb6)" opacity="0.18">
      ${barPaths('#000')}${hoopPaths('#000')}
    </g>
    ${hoopPaths(null)}
    ${hoopPaths('url(#gHoopFade)')}
    ${barPaths(null)}
    <ellipse cx="${CX}" cy="${RING_CY}" rx="24" ry="8" fill="url(#gRing)"></ellipse>
    <path d="M ${CX - 15},${RING_CY - 4} A 16,8 0 0 1 ${CX + 14},${RING_CY - 5}" fill="none" stroke="#efe9dc" stroke-opacity="0.55" stroke-width="1.8"></path>
    <g class="spill" style="mix-blend-mode:screen">${barPaths('#ff5330')}${hoopPaths('#ff5330')}</g>
  </g>`;
}

function base() {
  const rivets = Array.from({ length: 9 }, (_, i) => {
    const x = T.band.x + 22 + (i * (T.band.w - 44)) / 8;
    return `<circle cx="${x.toFixed(1)}" cy="${T.band.y + 15}" r="4.6" fill="url(#gRivet)"></circle>`;
  }).join('');

  return `<g class="housing">
    <!-- guard seat -->
    <rect x="${T.collar.x}" y="${T.collar.y}" width="${T.collar.w}" height="${T.collar.h}" rx="3" fill="url(#gMetalHi)"></rect>
    <ellipse cx="${CX}" cy="${T.collar.y + 2}" rx="${T.collar.w / 2}" ry="7" fill="url(#gMetal)"></ellipse>
    <rect x="${T.collar.x}" y="${T.collar.y + T.collar.h - 3}" width="${T.collar.w}" height="3" fill="#1d1b18" opacity="0.6"></rect>

    <!-- upper body with its raised boss and vent slot -->
    <rect x="${T.body.x}" y="${T.body.y}" width="${T.body.w}" height="${T.body.h}" rx="2" fill="url(#gMetal)"></rect>
    <rect x="${T.body.x}" y="${T.body.y}" width="${T.body.w}" height="2.5" fill="#e6e0d2" opacity="0.35"></rect>
    <rect x="132" y="456" width="176" height="30" rx="15" fill="url(#gMetalHi)"></rect>
    <rect x="132" y="456" width="176" height="30" rx="15" fill="none" stroke="#211f1b" stroke-opacity="0.45"></rect>
    <rect x="150" y="465" width="92" height="11" rx="5.5" fill="#141311" opacity="0.82"></rect>
    <rect x="150" y="465" width="92" height="4" rx="2" fill="#000" opacity="0.5"></rect>
    <rect x="${T.body.x}" y="${T.body.y + T.body.h - 3}" width="${T.body.w}" height="3" fill="#1d1b18" opacity="0.55"></rect>

    <!-- riveted mid band, left deliberately unbranded -->
    <rect x="${T.band.x}" y="${T.band.y}" width="${T.band.w}" height="${T.band.h}" rx="2" fill="url(#gMetal)"></rect>
    <rect x="${T.band.x}" y="${T.band.y}" width="${T.band.w}" height="2.5" fill="#e6e0d2" opacity="0.3"></rect>
    ${rivets}

    <!-- flared skirt -->
    <path d="M ${T.band.x},${T.skirtTopY} L ${T.band.x + T.band.w},${T.skirtTopY} L ${T.skirtBotX + T.skirtBotW},${T.skirtBotY} L ${T.skirtBotX},${T.skirtBotY} Z" fill="url(#gMetalLo)"></path>
    <rect x="${T.lip.x}" y="${T.lip.y}" width="${T.lip.w}" height="${T.lip.h}" rx="3" fill="url(#gMetal)"></rect>
    <rect x="${T.lip.x}" y="${T.lip.y}" width="${T.lip.w}" height="2.5" fill="#ddd7c9" opacity="0.3"></rect>

    <g class="spill" style="mix-blend-mode:screen">
      <rect x="${T.collar.x}" y="${T.collar.y}" width="${T.collar.w}" height="${T.collar.h}" rx="3" fill="#ff5330"></rect>
      <rect x="${T.body.x}" y="${T.body.y}" width="${T.body.w}" height="${T.body.h}" rx="2" fill="#d4300f"></rect>
      <rect x="${T.band.x}" y="${T.band.y}" width="${T.band.w}" height="${T.band.h}" rx="2" fill="#a82409"></rect>
    </g>
  </g>`;
}

function lampSVG({ variant }) {
  const caged = variant !== 'bare';
  const fluted = variant !== 'smooth';
  const backHoops = caged
    ? HOOPS.map((h) => `<path d="${h.back}" fill="none" stroke="#2a1e20" stroke-opacity="0.3" stroke-width="5.5"></path>`).join('')
    : '';

  return `<svg class="lamp" viewBox="0 0 440 740" xmlns="http://www.w3.org/2000/svg">
${defs()}

  <ellipse cx="${CX}" cy="706" rx="212" ry="18" fill="url(#gShadow)"></ellipse>

  <!-- ============ lens ============ -->
  <g class="lensGroup">
    <path d="${LENS_PATH}" fill="url(#gGlass)"></path>
    <path class="glassHot" d="${LENS_PATH}" fill="url(#gHot)"></path>
    <g clip-path="url(#clipLens)">
      ${backHoops}
      <!-- the lamp column filling the tube, with the reflector low inside it -->
      <ellipse class="column" cx="${CX}" cy="272" rx="74" ry="164" fill="url(#gColumn)" filter="url(#fb18)" style="mix-blend-mode:screen"></ellipse>
      <g class="reflector">
        <ellipse cx="${CX}" cy="384" rx="46" ry="15" fill="#1d0c0b" opacity="0.6"></ellipse>
        <path d="M ${CX - 46},383 A 46,24 0 0 1 ${CX + 46},383" fill="none" stroke="#e6cec4" stroke-opacity="0.16" stroke-width="2"></path>
        <ellipse class="filament" cx="${CX}" cy="370" rx="6" ry="9" fill="#4a1512"></ellipse>
        <ellipse class="core" cx="${CX}" cy="368" rx="42" ry="34" fill="#ffeade" filter="url(#fb18)"></ellipse>
      </g>
      ${fluted ? flutes() : ''}
      <rect x="102" y="${Y_APEX}" width="236" height="${Y_LENS_BOT - Y_APEX}" fill="url(#gCyl)"></rect>
      <rect x="102" y="${Y_APEX}" width="236" height="${Y_LENS_BOT - Y_APEX}" fill="url(#gCapDark)"></rect>
      <!-- specular: broad soft highlight down the tube, crisp core, cap sheen -->
      <ellipse cx="160" cy="272" rx="30" ry="118" transform="rotate(-4 160 272)" fill="url(#gSpec)"></ellipse>
      <ellipse cx="157" cy="218" rx="9" ry="52" transform="rotate(-5 157 218)" fill="#fff" opacity="0.28" filter="url(#fb3)"></ellipse>
      <ellipse cx="199" cy="82" rx="66" ry="26" fill="url(#gSpecCap)"></ellipse>
      <path d="M 322,150 Q 332,282 322,396" fill="none" stroke="#fff" stroke-opacity="0.14" stroke-width="11" filter="url(#fb6)"></path>
      <!-- inner rim darkening + the meniscus where the lens seats into the base -->
      <path d="${LENS_PATH}" fill="none" stroke="#000" stroke-opacity="0.72" stroke-width="24" filter="url(#fb6)"></path>
      <rect x="102" y="386" width="236" height="22" fill="#000" opacity="0.45"></rect>
      <path class="edgeGlow" d="M 105,404 L 105,158 A 115,115 0 0 1 335,158 L 335,404" fill="none" stroke="#ff7444" stroke-width="4.5" filter="url(#fb3)"></path>
    </g>
    <path d="M 103,402 L 103,158 A 117,117 0 0 1 152,73" fill="none" stroke="#ffb9a6" stroke-opacity="0.22" stroke-width="2.5" filter="url(#fb3)"></path>
    <path d="${LENS_PATH}" fill="none" stroke="#0a0a0d" stroke-opacity="0.85" stroke-width="2"></path>
  </g>

  ${caged ? cage() : ''}
  ${base()}
</svg>`;
}

// -------------------------------------------------------------------- icons

const ICONS = {
  puck: `<svg viewBox="0 0 24 24" width="24" height="24"><ellipse cx="12" cy="8.6" rx="8" ry="3.4" fill="currentColor"></ellipse><path d="M4 8.6v4.8c0 1.9 3.6 3.4 8 3.4s8-1.5 8-3.4V8.6c0 1.9-3.6 3.4-8 3.4S4 10.5 4 8.6z" fill="currentColor"></path></svg>`,
  songs: `<svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"><path d="M3 6h10M3 11h10M3 16h6"></path><path d="M20 5v9.2"></path><circle cx="17.6" cy="15.4" r="2.4" fill="currentColor" stroke="none"></circle></svg>`,
  sonos: `<svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="1.9"><rect x="5" y="2.5" width="14" height="19" rx="3"></rect><circle cx="12" cy="15.5" r="3.2"></circle><circle cx="12" cy="7.2" r="1.5"></circle></svg>`,
  lights: `<svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"><path d="M9 17.5h6M10 20.5h4"></path><path d="M12 2.8a6.2 6.2 0 0 0-3.6 11.2c.5.4.8 1 .8 1.6h5.6c0-.6.3-1.2.8-1.6A6.2 6.2 0 0 0 12 2.8z"></path></svg>`,
  note: `<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M19 4.5v10.3"></path><path d="M19 4.5 9 6.7v10.4"></path><circle cx="6.4" cy="17.6" r="2.6" fill="currentColor" stroke="none"></circle><circle cx="16.4" cy="15.2" r="2.6" fill="currentColor" stroke="none"></circle></svg>`,
  wave: `<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 10v4M8 7.5v9M12 4.5v15M16 8.5v7M20 11v2"></path></svg>`,
};

// ------------------------------------------------------------------ styles

function styles({ w, h, lampW, lampTop, chrome }) {
  const k = lampW / 440;
  const left = (w - lampW) / 2;
  const sx = (u) => +(left + u * k).toFixed(1);
  const sy = (v) => +(lampTop + v * k).toFixed(1);

  const cx = sx(CX);
  const lensTop = sy(Y_APEX);
  const lensBot = sy(Y_LENS_BOT);
  const bulbY = sy(300);
  const footBot = sy(694);

  const haloW = +(420 * k).toFixed(1);
  const haloH = +(lensBot - lensTop + 150 * k).toFixed(1);
  const beamSize = +(Math.max(w, h) * 2.6).toFixed(0);
  const poolW = +(760 * k).toFixed(1);
  const poolH = +(170 * k).toFixed(1);

  return `
  *, *::before, *::after { box-sizing: border-box; }
  body { margin: 0; background: #050506; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; }
  a { color: #ff5a45; } a:hover { color: #ff8071; }

  .stage {
    position: relative; width: ${w}px; height: ${h}px; overflow: hidden;
    isolation: isolate; user-select: none; -webkit-tap-highlight-color: transparent;
    background:
      radial-gradient(126% 84% at 50% ${((((lensTop + lensBot) / 2) / h) * 100).toFixed(1)}%, #26262b 0%, #16161a 34%, #0a0a0c 68%, #050506 100%);
  }

  /* ---- the room the light lives in ---- */
  .floor { position: absolute; left: 0; right: 0; top: ${(footBot - 5).toFixed(1)}px; bottom: 0;
    background: linear-gradient(180deg, rgba(255,255,255,0.05), rgba(0,0,0,0.34) 55%, rgba(0,0,0,0.64)); }
  .horizon { position: absolute; left: 0; right: 0; top: ${(footBot - 5).toFixed(1)}px; height: 1px;
    background: linear-gradient(90deg, transparent, rgba(255,255,255,0.14) 24%, rgba(255,255,255,0.14) 76%, transparent); }

  /* ---- volumetric beams: two opposing wedges off a spinning reflector ---- */
  .beams, .haze { position: absolute; width: ${beamSize}px; height: ${beamSize}px;
    left: ${cx}px; top: ${bulbY}px; margin-left: ${-beamSize / 2}px; margin-top: ${-beamSize / 2}px;
    pointer-events: none; mix-blend-mode: screen; opacity: 0; transition: opacity 480ms ease; }
  .beams b, .haze b { position: absolute; inset: 0; display: block; border-radius: 50%;
    animation: spin 1.05s linear infinite;
    -webkit-mask-image: radial-gradient(closest-side, #000 0%, rgba(0,0,0,0.92) 24%, rgba(0,0,0,0.46) 58%, transparent 86%);
    mask-image: radial-gradient(closest-side, #000 0%, rgba(0,0,0,0.92) 24%, rgba(0,0,0,0.46) 58%, transparent 86%); }
  .beams .wide { filter: blur(16px);
    background: conic-gradient(from 0deg,
      rgba(255,48,28,0) 0deg, rgba(255,78,46,0.72) 9deg, rgba(255,48,28,0) 30deg,
      rgba(255,48,28,0) 170deg, rgba(255,78,46,0.72) 189deg, rgba(255,48,28,0) 210deg,
      rgba(255,48,28,0) 360deg); }
  .beams .core { filter: blur(4px); opacity: 0.72;
    background: conic-gradient(from 0deg,
      rgba(255,150,120,0) 4deg, rgba(255,205,182,0.62) 9deg, rgba(255,150,120,0) 16deg,
      rgba(255,150,120,0) 182deg, rgba(255,205,182,0.62) 189deg, rgba(255,150,120,0) 196deg,
      rgba(255,150,120,0) 360deg); }
  .haze b { filter: blur(40px);
    -webkit-mask-image: radial-gradient(closest-side, rgba(0,0,0,0.55) 0%, rgba(0,0,0,0.32) 40%, transparent 80%);
    mask-image: radial-gradient(closest-side, rgba(0,0,0,0.55) 0%, rgba(0,0,0,0.32) 40%, transparent 80%);
    background: conic-gradient(from 0deg,
      rgba(255,60,36,0) 0deg, rgba(255,86,54,0.5) 12deg, rgba(255,60,36,0) 34deg,
      rgba(255,60,36,0) 168deg, rgba(255,86,54,0.5) 192deg, rgba(255,60,36,0) 214deg,
      rgba(255,60,36,0) 360deg); }

  /* ---- light landing on surfaces ---- */
  .halo { position: absolute; left: ${cx}px; top: ${(lensTop - 70 * k).toFixed(1)}px;
    width: ${haloW}px; height: ${haloH}px; margin-left: ${(-haloW / 2).toFixed(1)}px;
    border-radius: 46% / 50%; filter: blur(${(38 * k).toFixed(1)}px); mix-blend-mode: screen;
    background: radial-gradient(closest-side, rgba(255,58,32,0.95), rgba(255,34,18,0.42) 44%, rgba(255,24,12,0) 78%);
    opacity: 0.12; transition: opacity 380ms ease; }
  .pool { position: absolute; left: ${cx}px; top: ${(footBot - poolH * 0.34).toFixed(1)}px;
    width: ${poolW}px; height: ${poolH}px; margin-left: ${(-poolW / 2).toFixed(1)}px;
    border-radius: 50%; filter: blur(${(22 * k).toFixed(1)}px); mix-blend-mode: screen;
    background: radial-gradient(closest-side, rgba(255,66,40,0.66), rgba(255,42,24,0.22) 46%, transparent 78%);
    opacity: 0.07; transition: opacity 380ms ease; }
  .wash { position: absolute; inset: 0; mix-blend-mode: screen; opacity: 0; transition: opacity 320ms ease;
    background: radial-gradient(78% 50% at 50% ${(((bulbY - 30) / h) * 100).toFixed(1)}%, rgba(255,46,26,0.34), rgba(255,30,16,0.1) 50%, transparent 78%); }

  .grain { position: absolute; inset: 0; opacity: 0.06; mix-blend-mode: overlay; pointer-events: none; }

  /* ---- the fixture ---- */
  .lampWrap { position: absolute; left: ${left}px; top: ${lampTop}px; width: ${lampW}px; }
  .lamp { display: block; width: 100%; height: auto; }
  .glassHot { opacity: 0; transition: opacity 260ms ease; }
  .core, .column, .edgeGlow { opacity: 0; transition: opacity 260ms ease; }
  .spill { opacity: 0; transition: opacity 300ms ease; }
  .reflector { transform-box: fill-box; transform-origin: center; }

  /* ---- lit state ---- */
  .lit .beams { opacity: calc(var(--beam, 0.75) * 1); }
  .lit .haze { opacity: calc(var(--beam, 0.75) * 0.2); }
  .lit .halo { opacity: 1; animation: haloPulse 1.05s ease-in-out infinite; }
  .lit .pool { opacity: 0.92; animation: poolPulse 1.05s ease-in-out infinite; }
  .lit .wash { opacity: 1; animation: washPulse 1.05s ease-in-out infinite; }
  .lit .glassHot { opacity: 1; animation: hotPulse 1.05s ease-in-out infinite; }
  .lit .core { opacity: 1; }
  .lit .column { opacity: 0.55; }
  .lit .edgeGlow { opacity: 0.6; }
  .lit .filament { fill: #fff4ec; }
  .lit .spill { opacity: 0.2; animation: spillPulse 1.05s ease-in-out infinite; }
  .lit .housing .spill { opacity: 0.13; animation: spillPulseLow 1.05s ease-in-out infinite; }
  .lit .reflector { animation: swing 1.05s ease-in-out infinite; }

  @keyframes spin { to { transform: rotate(360deg); } }
  @keyframes swing { 0%, 100% { transform: translateX(-9%); } 50% { transform: translateX(9%); } }
  @keyframes haloPulse { 0%, 100% { opacity: 0.8; transform: scale(1); } 50% { opacity: 1; transform: scale(1.05); } }
  @keyframes poolPulse { 0%, 100% { opacity: 0.66; } 50% { opacity: 1; } }
  @keyframes washPulse { 0%, 100% { opacity: 0.62; } 50% { opacity: 1; } }
  @keyframes hotPulse { 0%, 100% { opacity: 0.84; } 50% { opacity: 1; } }
  @keyframes spillPulse { 0%, 100% { opacity: 0.13; } 50% { opacity: 0.26; } }
  @keyframes spillPulseLow { 0%, 100% { opacity: 0.08; } 50% { opacity: 0.17; } }

  /* ---- app chrome (values lifted from GoalLightView.swift / ContentView.swift) ---- */
  .settings { position: absolute; top: 18px; right: 20px; display: flex; align-items: flex-end; gap: 4px;
    padding: 8px; border-radius: 14px; background: rgba(255,255,255,0.08); }
  .settings i { display: block; width: 4px; border-radius: 2px; }

  .status { position: absolute; left: 0; right: 0; top: ${chrome.statusTop}px; height: 58px;
    display: flex; align-items: center; justify-content: center; text-align: center; }
  .status span { font-size: 20px; font-weight: 500; letter-spacing: 4px; color: #8a8a90; }
  .lit .status span { font-size: 48px; font-weight: 700; letter-spacing: 3px; color: #ff4d3d;
    text-shadow: 0 0 26px rgba(255,60,50,0.8), 0 0 60px rgba(255,40,30,0.5); }

  .ready { position: absolute; left: 0; right: 0; top: ${chrome.readyTop}px;
    display: flex; align-items: center; justify-content: center; gap: 8px; }
  .chip { display: flex; align-items: center; gap: 6px; padding: 7px 12px; border-radius: 999px;
    font-size: 12px; letter-spacing: 0.2px; color: #9a9aa1;
    background: rgba(255,255,255,0.055); border: 1px solid rgba(255,255,255,0.07); }
  .chip svg { color: #6f6f77; flex: none; }
  .noready .ready { display: none; }

  .tabbar { position: absolute; left: 0; right: 0; bottom: 0; height: 83px; padding-top: 8px;
    display: grid; grid-template-columns: repeat(4, minmax(0, 1fr));
    background: rgba(16,16,19,0.9); -webkit-backdrop-filter: blur(24px); backdrop-filter: blur(24px);
    border-top: 1px solid rgba(255,255,255,0.09); }
  .tab { display: flex; flex-direction: column; align-items: center; gap: 3px; color: #85858c; }
  .tab span { font-size: 10px; font-weight: 500; letter-spacing: 0.1px; }
  .tab.on { color: #e62d2d; }
  .homebar { position: absolute; left: 50%; bottom: 8px; width: 134px; height: 5px; margin-left: -67px;
    border-radius: 3px; background: rgba(255,255,255,0.32); }
  `;
}

// ------------------------------------------------------------------ screens

const grainSVG = `<svg class="grain" xmlns="http://www.w3.org/2000/svg"><rect width="100%" height="100%" filter="url(#grainF)"></rect></svg>`;

function room(variant, withFloor = true) {
  return `
  <div class="wash"></div>
  <div class="beams"><b class="wide"></b><b class="core"></b></div>
  <div class="halo"></div>
  <div class="pool"></div>
  ${withFloor ? '<div class="floor"></div>\n  <div class="horizon"></div>' : ''}
  <div class="lampWrap">${lampSVG({ variant })}</div>
  <div class="haze"><b></b></div>
  ${grainSVG}`;
}

function appChrome({ label }) {
  return `
  <div class="settings">
    <i style="height: 8px; background: #bbbbbb"></i>
    <i style="height: 14px; background: #dddddd"></i>
    <i style="height: 6px; background: #999999"></i>
  </div>
  <div class="status"><span>${label}</span></div>
  <div class="ready">
    <div class="chip">${ICONS.note}<span>goal-horn.m4a</span></div>
    <div class="chip">${ICONS.wave}<span>Living Room &#183; 45%</span></div>
  </div>
  <div class="tabbar">
    <div class="tab on">${ICONS.puck}<span>Goal</span></div>
    <div class="tab">${ICONS.songs}<span>Songs</span></div>
    <div class="tab">${ICONS.sonos}<span>Sonos</span></div>
    <div class="tab">${ICONS.lights}<span>Lights</span></div>
  </div>
  <div class="homebar"></div>`;
}

function doc({ css, body, script }) {
  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  <style>${css}</style>
</helmet>
${body}
</x-dc>
${script || ''}
</body>
</html>
`;
}

// ---------------------------------------------------------------- artboards

const PHONE = { w: 390, h: 844, lampW: 346, lampTop: 56, chrome: { statusTop: 640, readyTop: 716 } };
const ALT = { w: 390, h: 760, lampW: 330, lampTop: 22, chrome: { statusTop: 614, readyTop: 690 } };
const STUDY = { w: 620, h: 820, lampW: 452, lampTop: 12, chrome: { statusTop: 740, readyTop: 780 } };

writeFileSync(
  join(OUT, 'Main.dc.html'),
  doc({
    css: styles(PHONE),
    body: `<div class="{{rootCls}}" style="--beam: {{beam}}" onClick="{{fire}}">
  ${room('caged')}
  ${appChrome({ label: '{{label}}' })}
</div>`,
    script: `<script data-dc-script data-props='{
  "beamStrength": {"editor": "range", "default": 75, "min": 0, "max": 100, "step": 5, "unit": "%", "section": "Light"},
  "showReady": {"editor": "boolean", "default": true, "section": "Layout"},
  "$preview": {"width": 390, "height": 844}
}'>
class Component extends DCLogic {
  constructor(props) {
    super(props);
    this.state = { firing: false };
  }
  componentWillUnmount() { clearTimeout(this.timer); }
  fire() {
    if (this.state.firing) return;
    this.setState({ firing: true });
    this.timer = setTimeout(() => this.setState({ firing: false }), 2600);
  }
  renderVals() {
    var firing = this.state.firing;
    var ready = this.props.showReady === false ? ' noready' : '';
    return {
      rootCls: 'stage' + (firing ? ' lit' : '') + ready,
      label: firing ? 'GOAL!' : 'TAP FOR A GOAL!',
      beam: String((this.props.beamStrength == null ? 75 : this.props.beamStrength) / 100),
      fire: () => this.fire(),
    };
  }
}
</script>`,
  })
);

writeFileSync(
  join(OUT, 'Fired.dc.html'),
  doc({
    css: styles(PHONE),
    body: `<div class="stage lit" style="--beam: 0.8">
  ${room('caged')}
  ${appChrome({ label: 'GOAL!' })}
</div>`,
  })
);

writeFileSync(
  join(OUT, 'Lamp.dc.html'),
  doc({
    css:
      styles(STUDY) +
      `
  .stage { background: radial-gradient(120% 84% at 50% 34%, #212127 0%, #131317 38%, #08080a 74%, #050506 100%); }`,
    body: `<div class="{{rootCls}}" style="--beam: {{beam}}">
  ${room('caged', false)}
</div>`,
    script: `<script data-dc-script data-props='{
  "lit": {"editor": "boolean", "default": true, "section": "Light"},
  "beamStrength": {"editor": "range", "default": 75, "min": 0, "max": 100, "step": 5, "unit": "%", "section": "Light"},
  "$preview": {"width": 620, "height": 820}
}'>
class Component extends DCLogic {
  renderVals() {
    return {
      rootCls: 'stage' + (this.props.lit !== false ? ' lit' : ''),
      beam: String((this.props.beamStrength == null ? 75 : this.props.beamStrength) / 100),
    };
  }
}
</script>`,
  })
);

// --- Alternate A: smooth lens, no flutes.
writeFileSync(
  join(OUT, 'AltSmooth.dc.html'),
  doc({
    css: styles(ALT),
    body: `<div class="stage lit noready" style="--beam: 0.8">
  ${room('smooth')}
  <div class="status"><span>GOAL!</span></div>
</div>`,
  })
);

// --- Alternate B: fluted lens with the guard removed.
writeFileSync(
  join(OUT, 'AltBare.dc.html'),
  doc({
    css: styles(ALT),
    body: `<div class="stage lit noready" style="--beam: 0.8">
  ${room('bare')}
  <div class="status"><span>GOAL!</span></div>
</div>`,
  })
);

console.log('wrote Main, Fired, Lamp, AltSmooth, AltBare');
