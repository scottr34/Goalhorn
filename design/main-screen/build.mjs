// Generates the .dc.html artboards for the Goalhorn main-screen redesign.
//   node design/main-screen/build.mjs
// Geometry for the lamp (cage wrap, hoop perspective, chrome banding) is
// computed here so every artboard stays consistent.

import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const OUT = dirname(fileURLToPath(import.meta.url));

// ---------------------------------------------------------------- utilities

const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const toHex = (rgb) =>
  '#' + rgb.map((v) => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0')).join('');
/** Scale a hex colour toward black by factor f (1 = unchanged). */
const dim = (h, f) => toHex(hex(h).map((v) => v * f));

// ------------------------------------------------------------ lamp geometry
// SVG user space: viewBox 0 0 440 420.
// A rink goal light is SQUAT and wide - the dome is broader than it is tall,
// sitting on a heavy dark base. Tall and narrow reads as a lantern.

const CX = 220;
const R_GLASS = 118;
const R_CAGE = 124;
const Y_APEX = 86;
const Y_SHOULDER = 150; // where the domed cap meets the cylinder
const Y_GLASS_BOT = 258;
const Y_COLLAR = 248;
const EYE = 240; // camera height, drives hoop curvature and the collar ellipse

const GLASS_PATH =
  `M ${CX - R_GLASS},${Y_GLASS_BOT} L ${CX - R_GLASS},${Y_SHOULDER} ` +
  `A ${R_GLASS},${Y_SHOULDER - Y_APEX} 0 0 1 ${CX + R_GLASS},${Y_SHOULDER} ` +
  `L ${CX + R_GLASS},${Y_GLASS_BOT} Z`;

// Vertical cage bars sit at even angles around the cylinder, so on screen they
// bunch toward the silhouette (x = R sin0) and foreshorten (w = w0 cos0).
// That cosine spacing is what makes a cage read as wrapped rather than printed.
const Y_CAGE_APEX = 82;
const RV_CAGE = Y_SHOULDER - Y_CAGE_APEX; // vertical semi-axis of the cage cap
const PHI_RING = Math.asin(19 / R_CAGE); // where the bars meet the top hub
const RING_TILT = 4; // how much the hub's near edge rides up (we look up at it)

/** A point on the cage meridian at azimuth t, polar angle phi from the apex. */
function meridian(t, phi) {
  return [
    CX + R_CAGE * Math.sin(phi) * Math.sin(t),
    Y_CAGE_APEX + RV_CAGE * (1 - Math.cos(phi)) - RING_TILT * Math.cos(t) * Math.cos(phi),
  ];
}

const RING_CY = +(Y_CAGE_APEX + RV_CAGE * (1 - Math.cos(PHI_RING))).toFixed(2);
const RING_RX = +(R_CAGE * Math.sin(PHI_RING)).toFixed(2);

const BAR_ANGLES = [0, 20, -20, 40, -40, 60, -60, 80, -80];
const BARS = BAR_ANGLES.map((deg, i) => {
  const t = (deg * Math.PI) / 180;
  const x = +(CX + R_CAGE * Math.sin(t)).toFixed(2);
  const k = Math.abs(Math.cos(t)); // how square-on this bar faces us
  const w = +(6.2 * (0.3 + 0.7 * k)).toFixed(2);
  // Over the cap the bar is the projected meridian, so it hugs the dome instead
  // of bowing out past the silhouette.
  const steps = 8;
  let d = `M ${x},262 L ${x},${Y_SHOULDER - 2}`;
  for (let j = 1; j <= steps; j++) {
    const phi = (Math.PI / 2) + (PHI_RING - Math.PI / 2) * (j / steps);
    const [px, py] = meridian(t, phi);
    d += ` L ${px.toFixed(2)},${py.toFixed(2)}`;
  }
  return { id: `bar${i}`, x, w, k, d };
});

// Horizontal hoops. A hoop above eye level shows its near half as the TOP of the
// projected ellipse (bulges up); below eye level the near half sags down.
// Cap hoops are narrower because the dome has already started closing in.
const HOOPS = [
  { y: 118, cap: true },
  { y: 188, cap: false },
  { y: 232, cap: false },
].map((h, i) => {
  const halfW = h.cap
    ? R_CAGE * Math.sqrt(Math.max(0, 1 - ((Y_SHOULDER - h.y) / (Y_SHOULDER - Y_APEX)) ** 2))
    : R_CAGE + 6;
  const rise = ((EYE - h.y) / 80) * 10;
  const c = +(h.y - 2 * rise).toFixed(1);
  const cBack = +(h.y + 2 * rise).toFixed(1);
  const x0 = +(CX - halfW).toFixed(1);
  const x1 = +(CX + halfW).toFixed(1);
  return {
    id: `hoop${i}`,
    y: h.y,
    front: `M ${x0},${h.y} Q ${CX},${c} ${x1},${h.y}`,
    back: `M ${x0},${h.y} Q ${CX},${cBack} ${x1},${h.y}`,
  };
});

// ------------------------------------------------------------------- defs

function defs() {
  const barGrads = BARS.map((b) => {
    const k = b.k;
    const stops = [
      [0, '#101014', 1],
      [0.18, '#55555e', 0.62 + 0.38 * k],
      [0.4, '#c6c6cf', 0.55 + 0.45 * k],
      [0.58, '#7c7c86', 0.58 + 0.42 * k],
      [0.8, '#2e2e35', 0.7 + 0.3 * k],
      [1, '#0b0b0e', 1],
    ]
      .map(([o, c, f]) => `<stop offset="${o}" stop-color="${dim(c, f)}"></stop>`)
      .join('');
    return `<linearGradient id="g_${b.id}" gradientUnits="userSpaceOnUse" x1="${(b.x - b.w / 2).toFixed(2)}" y1="0" x2="${(b.x + b.w / 2).toFixed(2)}" y2="0">${stops}</linearGradient>`;
  }).join('');

  const hoopFade =
    `<linearGradient id="gHoopFade" gradientUnits="userSpaceOnUse" x1="${CX - R_CAGE - 6}" y1="0" x2="${CX + R_CAGE + 6}" y2="0">` +
    `<stop offset="0" stop-color="#08080b" stop-opacity="0.85"></stop>` +
    `<stop offset="0.2" stop-color="#08080b" stop-opacity="0.25"></stop>` +
    `<stop offset="0.5" stop-color="#08080b" stop-opacity="0"></stop>` +
    `<stop offset="0.8" stop-color="#08080b" stop-opacity="0.25"></stop>` +
    `<stop offset="1" stop-color="#08080b" stop-opacity="0.85"></stop>` +
    `</linearGradient>`;

  const hoopGrads = HOOPS.map(
    (h) =>
      `<linearGradient id="g_${h.id}" gradientUnits="userSpaceOnUse" x1="0" y1="${h.y - 3.6}" x2="0" y2="${h.y + 3.6}">` +
      `<stop offset="0" stop-color="#141419"></stop>` +
      `<stop offset="0.3" stop-color="#b9b9c2"></stop>` +
      `<stop offset="0.54" stop-color="#6b6b75"></stop>` +
      `<stop offset="0.78" stop-color="#2f2f36"></stop>` +
      `<stop offset="1" stop-color="#0d0d11"></stop>` +
      `</linearGradient>`
  ).join('');

  return `<defs>
  <clipPath id="clipGlass"><path d="${GLASS_PATH}"></path></clipPath>

  <!-- Glass, unlit: deep cherry, nearly black at the rim. -->
  <radialGradient id="gGlass" cx="0.4" cy="0.3" r="0.86">
    <stop offset="0" stop-color="#8f1a17"></stop>
    <stop offset="0.32" stop-color="#5c0e0c"></stop>
    <stop offset="0.64" stop-color="#350706"></stop>
    <stop offset="1" stop-color="#150202"></stop>
  </radialGradient>
  <!-- Glass, lit: blown out around the lamp, which sits LOW in the dome. -->
  <radialGradient id="gHot" cx="0.5" cy="0.62" r="0.98">
    <stop offset="0" stop-color="#fff6f1"></stop>
    <stop offset="0.13" stop-color="#ff9e7c"></stop>
    <stop offset="0.38" stop-color="#ff2c14"></stop>
    <stop offset="0.7" stop-color="#b00604"></stop>
    <stop offset="1" stop-color="#4e0000"></stop>
  </radialGradient>
  <!-- Cylinder form: the left-right falloff that makes a tube read as a tube. -->
  <linearGradient id="gCyl" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#000" stop-opacity="0.78"></stop>
    <stop offset="0.14" stop-color="#000" stop-opacity="0.28"></stop>
    <stop offset="0.36" stop-color="#fff" stop-opacity="0.07"></stop>
    <stop offset="0.62" stop-color="#000" stop-opacity="0.12"></stop>
    <stop offset="0.87" stop-color="#000" stop-opacity="0.62"></stop>
    <stop offset="1" stop-color="#000" stop-opacity="0.84"></stop>
  </linearGradient>
  <linearGradient id="gCapDark" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#000" stop-opacity="0.34"></stop>
    <stop offset="0.2" stop-color="#000" stop-opacity="0"></stop>
    <stop offset="0.82" stop-color="#000" stop-opacity="0"></stop>
    <stop offset="1" stop-color="#000" stop-opacity="0.42"></stop>
  </linearGradient>
  <radialGradient id="gSpec"><stop offset="0" stop-color="#fff" stop-opacity="0.46"></stop><stop offset="0.55" stop-color="#fff" stop-opacity="0.12"></stop><stop offset="1" stop-color="#fff" stop-opacity="0"></stop></radialGradient>
  <radialGradient id="gSpecCap"><stop offset="0" stop-color="#fff" stop-opacity="0.3"></stop><stop offset="1" stop-color="#fff" stop-opacity="0"></stop></radialGradient>
  <radialGradient id="gShadow"><stop offset="0" stop-color="#000" stop-opacity="0.75"></stop><stop offset="0.55" stop-color="#000" stop-opacity="0.3"></stop><stop offset="1" stop-color="#000" stop-opacity="0"></stop></radialGradient>

  <!-- Machined steel collar: catches the lamp, so it stays the brightest metal. -->
  <linearGradient id="gCollar" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#5f5f69"></stop>
    <stop offset="0.16" stop-color="#9a9aa4"></stop>
    <stop offset="0.4" stop-color="#3b3b43"></stop>
    <stop offset="0.58" stop-color="#1d1d23"></stop>
    <stop offset="0.8" stop-color="#565660"></stop>
    <stop offset="1" stop-color="#232329"></stop>
  </linearGradient>
  <!-- Cast housing: dark gunmetal with one bright top edge, not white plastic. -->
  <linearGradient id="gHousing" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#3f3f47"></stop>
    <stop offset="0.08" stop-color="#5e5e69"></stop>
    <stop offset="0.3" stop-color="#212127"></stop>
    <stop offset="0.5" stop-color="#15151a"></stop>
    <stop offset="0.66" stop-color="#101014"></stop>
    <stop offset="0.85" stop-color="#2b2b33"></stop>
    <stop offset="1" stop-color="#101014"></stop>
  </linearGradient>
  <linearGradient id="gFoot" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#43434b"></stop>
    <stop offset="0.28" stop-color="#232329"></stop>
    <stop offset="0.56" stop-color="#0f0f13"></stop>
    <stop offset="0.82" stop-color="#282830"></stop>
    <stop offset="1" stop-color="#08080b"></stop>
  </linearGradient>
  <radialGradient id="gCrown" cx="0.34" cy="0.26">
    <stop offset="0" stop-color="#a6a6b0"></stop>
    <stop offset="0.45" stop-color="#4a4a53"></stop>
    <stop offset="1" stop-color="#131318"></stop>
  </radialGradient>

  <filter id="fb3" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="3"></feGaussianBlur></filter>
  <filter id="fb6" x="-45%" y="-45%" width="190%" height="190%"><feGaussianBlur stdDeviation="6"></feGaussianBlur></filter>
  <filter id="fb14" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="14"></feGaussianBlur></filter>
  <filter id="grainF"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="3" stitchTiles="stitch"></feTurbulence></filter>
  <linearGradient id="gRing" gradientUnits="userSpaceOnUse" x1="0" y1="${RING_CY - 8}" x2="0" y2="${RING_CY + 8}">
    <stop offset="0" stop-color="#6e6e79"></stop>
    <stop offset="0.3" stop-color="#3a3a43"></stop>
    <stop offset="0.7" stop-color="#1c1c22"></stop>
    <stop offset="1" stop-color="#0c0c10"></stop>
  </linearGradient>
  ${barGrads}${hoopGrads}${hoopFade}
</defs>`;
}

// -------------------------------------------------------------- lamp markup

function fresnelRibs() {
  let out = '';
  for (let y = Y_APEX + 4; y < Y_GLASS_BOT - 3; y += 11) {
    out += `<rect x="98" y="${y}" width="244" height="4.2" fill="#fff" opacity="0.11"></rect>`;
    out += `<rect x="98" y="${y + 4.8}" width="244" height="2.2" fill="#000" opacity="0.36"></rect>`;
  }
  return `<g clip-path="url(#clipGlass)">${out}</g>`;
}

function cage() {
  const barPaths = (stroke, extra) =>
    BARS.map(
      (b) =>
        `<path d="${b.d}" fill="none" stroke="${stroke === null ? `url(#g_${b.id})` : stroke}" stroke-width="${b.w}" stroke-linecap="round"${extra || ''}></path>`
    ).join('');
  const hoopPaths = (stroke) =>
    HOOPS.map(
      (h) =>
        `<path d="${h.front}" fill="none" stroke="${stroke === null ? `url(#g_${h.id})` : stroke}" stroke-width="5.6" stroke-linecap="round"></path>`
    ).join('');

  return `<g class="cage">
    <g clip-path="url(#clipGlass)" transform="translate(2,3)" filter="url(#fb6)" opacity="0.16">
      ${barPaths('#000')}${hoopPaths('#000')}
    </g>
    ${hoopPaths(null)}
    ${hoopPaths('url(#gHoopFade)')}
    ${barPaths(null)}
    <ellipse cx="${CX}" cy="${RING_CY}" rx="${(+RING_RX + 3).toFixed(1)}" ry="7" fill="url(#gRing)"></ellipse>
    <path d="M ${CX - 13},${RING_CY - 3} A 14,7 0 0 1 ${CX + 12},${RING_CY - 4}" fill="none" stroke="#c6c6d0" stroke-opacity="0.5" stroke-width="1.6"></path>
    <g class="spill" style="mix-blend-mode:screen">${barPaths('#ff5330')}${hoopPaths('#ff5330')}</g>
  </g>`;
}

function lampSVG({ variant }) {
  const caged = variant !== 'bare';
  const ribs = variant === 'fresnel' ? fresnelRibs() : '';
  const bareCrown = caged
    ? ''
    : `<ellipse cx="${CX}" cy="64" rx="26" ry="15" fill="url(#gCrown)"></ellipse>`;
  const backHoops = caged
    ? HOOPS.map((h) => `<path d="${h.back}" fill="none" stroke="#241a1c" stroke-opacity="0.32" stroke-width="6"></path>`).join('')
    : '';

  return `<svg class="lamp" viewBox="0 0 440 420" xmlns="http://www.w3.org/2000/svg">
${defs()}

  <ellipse cx="${CX}" cy="356" rx="200" ry="17" fill="url(#gShadow)"></ellipse>

  <!-- ============ glass ============ -->
  <g class="glassGroup">
    <path d="${GLASS_PATH}" fill="url(#gGlass)"></path>
    <path class="glassHot" d="${GLASS_PATH}" fill="url(#gHot)"></path>
    <g clip-path="url(#clipGlass)">
      ${backHoops}
      <!-- reflector: a dark dish low in the dome, washed out once it is hot -->
      <g class="reflector">
        <ellipse cx="${CX}" cy="234" rx="46" ry="15" fill="#1d0c0b" opacity="0.62"></ellipse>
        <path d="M ${CX - 46},233 A 46,24 0 0 1 ${CX + 46},233" fill="none" stroke="#e6cec4" stroke-opacity="0.16" stroke-width="2"></path>
        <ellipse class="filament" cx="${CX}" cy="221" rx="6" ry="8" fill="#4a1512"></ellipse>
        <ellipse class="core" cx="${CX}" cy="219" rx="40" ry="32" fill="#ffe9dd" filter="url(#fb14)"></ellipse>
      </g>
      <ellipse class="pool2" cx="${CX}" cy="242" rx="104" ry="40" fill="#ff5a2c" filter="url(#fb14)" style="mix-blend-mode:screen"></ellipse>
      ${ribs}
      <rect x="102" y="86" width="236" height="172" fill="url(#gCyl)"></rect>
      <rect x="102" y="86" width="236" height="172" fill="url(#gCapDark)"></rect>
      <!-- specular: broad soft highlight, crisp core, right-edge environment rim -->
      <ellipse cx="163" cy="166" rx="33" ry="50" transform="rotate(-12 163 166)" fill="url(#gSpec)"></ellipse>
      <ellipse cx="159" cy="146" rx="10" ry="19" transform="rotate(-14 159 146)" fill="#fff" opacity="0.38" filter="url(#fb3)"></ellipse>
      <ellipse cx="197" cy="114" rx="60" ry="20" fill="url(#gSpecCap)"></ellipse>
      <path d="M 322,132 Q 332,196 322,252" fill="none" stroke="#fff" stroke-opacity="0.15" stroke-width="10" filter="url(#fb6)"></path>
      <!-- inner rim darkening + the meniscus where glass seats into the collar -->
      <path d="${GLASS_PATH}" fill="none" stroke="#000" stroke-opacity="0.7" stroke-width="22" filter="url(#fb6)"></path>
      <rect x="96" y="240" width="248" height="20" fill="#000" opacity="0.45"></rect>
      <path class="edgeGlow" d="M 105,256 L 105,150 A 115,61 0 0 1 335,150 L 335,256" fill="none" stroke="#ff7444" stroke-width="4.5" filter="url(#fb3)"></path>
    </g>
    <!-- rim light picked up off the room, left edge -->
    <path d="M 103,252 L 103,150 A 117,63 0 0 1 129.6,108.9" fill="none" stroke="#ffb9a6" stroke-opacity="0.22" stroke-width="2.5" filter="url(#fb3)"></path>
    <path d="${GLASS_PATH}" fill="none" stroke="#0a0a0d" stroke-opacity="0.9" stroke-width="2"></path>
  </g>

  ${bareCrown}
  ${caged ? cage() : ''}

  <!-- ============ base ============ -->
  <g class="housing">
    <ellipse cx="${CX}" cy="${Y_COLLAR + 2}" rx="124" ry="10" fill="#2c2c33"></ellipse>
    <rect x="100" y="${Y_COLLAR}" width="240" height="20" rx="3" fill="url(#gCollar)"></rect>
    <rect x="94" y="266" width="252" height="64" rx="4" fill="url(#gHousing)"></rect>
    <rect x="94" y="266" width="252" height="64" rx="4" fill="none" stroke="#000" stroke-opacity="0.7"></rect>
    <rect x="94" y="266" width="252" height="3" fill="#74747e" opacity="0.5"></rect>
    <rect x="94" y="296" width="252" height="2" fill="#000" opacity="0.55"></rect>
    <rect x="78" y="328" width="284" height="20" rx="3" fill="url(#gFoot)"></rect>
    <rect x="78" y="328" width="284" height="2" fill="#6a6a75" opacity="0.45"></rect>
    <circle cx="116" cy="282" r="5" fill="url(#gCrown)"></circle>
    <circle cx="324" cy="282" r="5" fill="url(#gCrown)"></circle>
    <g class="spill" style="mix-blend-mode:screen">
      <rect x="100" y="${Y_COLLAR}" width="240" height="20" rx="3" fill="#ff5330"></rect>
      <rect x="94" y="266" width="252" height="64" rx="4" fill="#d62c10"></rect>
      <rect x="78" y="328" width="284" height="20" rx="3" fill="#a8240d"></rect>
    </g>
  </g>
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
  const glassTop = sy(Y_APEX);
  const glassBot = sy(Y_GLASS_BOT);
  const bulbY = sy(224);
  const footBot = sy(348);

  const haloW = +(400 * k).toFixed(1);
  const haloH = +(glassBot - glassTop + 150 * k).toFixed(1);
  const beamSize = +(Math.max(w, h) * 2.6).toFixed(0);
  const poolW = +(700 * k).toFixed(1);
  const poolH = +(160 * k).toFixed(1);

  return `
  *, *::before, *::after { box-sizing: border-box; }
  body { margin: 0; background: #050506; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; }
  a { color: #ff5a45; } a:hover { color: #ff8071; }

  .stage {
    position: relative; width: ${w}px; height: ${h}px; overflow: hidden;
    isolation: isolate; user-select: none; -webkit-tap-highlight-color: transparent;
    background:
      radial-gradient(128% 86% at 50% ${(((glassTop + 30) / h) * 100).toFixed(1)}%, #232329 0%, #141418 34%, #0a0a0c 68%, #050506 100%);
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
  .halo { position: absolute; left: ${cx}px; top: ${(glassTop - 70 * k).toFixed(1)}px;
    width: ${haloW}px; height: ${haloH}px; margin-left: ${(-haloW / 2).toFixed(1)}px;
    border-radius: 46% / 50%; filter: blur(${(36 * k).toFixed(1)}px); mix-blend-mode: screen;
    background: radial-gradient(closest-side, rgba(255,58,32,0.95), rgba(255,34,18,0.42) 44%, rgba(255,24,12,0) 78%);
    opacity: 0.13; transition: opacity 380ms ease; }
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
  .core, .pool2, .edgeGlow { opacity: 0; transition: opacity 260ms ease; }
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
  .lit .pool2 { opacity: 0.46; }
  .lit .edgeGlow { opacity: 0.6; }
  .lit .filament { fill: #fff4ec; }
  .lit .spill { opacity: 0.16; animation: spillPulse 1.05s ease-in-out infinite; }
  .lit .housing .spill { opacity: 0.11; animation: spillPulseLow 1.05s ease-in-out infinite; }
  .lit .reflector { animation: swing 1.05s ease-in-out infinite; }
  .nocage .cage { display: none; }

  @keyframes spin { to { transform: rotate(360deg); } }
  @keyframes swing { 0%, 100% { transform: translateX(-9%); } 50% { transform: translateX(9%); } }
  @keyframes haloPulse { 0%, 100% { opacity: 0.8; transform: scale(1); } 50% { opacity: 1; transform: scale(1.05); } }
  @keyframes poolPulse { 0%, 100% { opacity: 0.66; } 50% { opacity: 1; } }
  @keyframes washPulse { 0%, 100% { opacity: 0.62; } 50% { opacity: 1; } }
  @keyframes hotPulse { 0%, 100% { opacity: 0.84; } 50% { opacity: 1; } }
  @keyframes spillPulse { 0%, 100% { opacity: 0.11; } 50% { opacity: 0.22; } }
  @keyframes spillPulseLow { 0%, 100% { opacity: 0.07; } 50% { opacity: 0.15; } }

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

const PHONE = { w: 390, h: 844, lampW: 540, lampTop: 134, chrome: { statusTop: 638, readyTop: 706 } };
const ALT = { w: 390, h: 620, lampW: 500, lampTop: 56, chrome: { statusTop: 516, readyTop: 582 } };
const STUDY = { w: 620, h: 780, lampW: 660, lampTop: 64, chrome: { statusTop: 700, readyTop: 740 } };

// --- Main: the redesigned Goal screen. Tap anywhere to fire the 2.6s show.
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

// --- Fired: the same screen held at the peak of the celebration.
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

// --- Lamp: the fixture on its own, big, for judging the realism.
writeFileSync(
  join(OUT, 'Lamp.dc.html'),
  doc({
    css:
      styles(STUDY) +
      `
  .stage { background: radial-gradient(120% 84% at 50% 32%, #212127 0%, #131317 38%, #08080a 74%, #050506 100%); }`,
    body: `<div class="{{rootCls}}" style="--beam: {{beam}}">
  ${room('caged', false)}
</div>`,
    script: `<script data-dc-script data-props='{
  "lit": {"editor": "boolean", "default": true, "section": "Light"},
  "cage": {"editor": "boolean", "default": true, "section": "Hardware"},
  "beamStrength": {"editor": "range", "default": 75, "min": 0, "max": 100, "step": 5, "unit": "%", "section": "Light"},
  "$preview": {"width": 620, "height": 780}
}'>
class Component extends DCLogic {
  renderVals() {
    var lit = this.props.lit !== false;
    var cage = this.props.cage !== false;
    return {
      rootCls: 'stage' + (lit ? ' lit' : '') + (cage ? '' : ' nocage'),
      beam: String((this.props.beamStrength == null ? 75 : this.props.beamStrength) / 100),
    };
  }
}
</script>`,
  })
);

// --- Alternate A: Fresnel-ribbed beacon glass behind the same cage.
writeFileSync(
  join(OUT, 'AltFresnel.dc.html'),
  doc({
    css: styles(ALT),
    body: `<div class="stage lit noready" style="--beam: 0.8">
  ${room('fresnel')}
  <div class="status"><span>GOAL!</span></div>
</div>`,
  })
);

// --- Alternate B: no cage - polished dome, product-shot clean.
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

console.log('wrote Main, Fired, Lamp, AltFresnel, AltBare');
