// ---- console silhouettes (generic shapes, no brand marks), local coordinates ----
const dome = (id, c1, c2) => `<radialGradient id="${id}" cx=".35" cy=".3" r=".8"><stop offset="0" stop-color="#fff" stop-opacity=".95"/><stop offset=".25" stop-color="${c1}"/><stop offset="1" stop-color="${c2}"/></radialGradient>`;
const miniCross = (x, y, a, fill = '#fff', o = .92) => `<path opacity="${o}" fill="${fill}" d="${roundPoly([[x - a / 3, y - a], [x + a / 3, y - a], [x + a / 3, y - a / 3], [x + a, y - a / 3], [x + a, y + a / 3], [x + a / 3, y + a / 3], [x + a / 3, y + a], [x - a / 3, y + a], [x - a / 3, y + a / 3], [x - a, y + a / 3], [x - a, y - a / 3], [x - a / 3, y - a / 3]], a * .12)}"/>`;

const CONSOLES = {
  handheld: {
    d: 'M14 0h92q14 0 14 14v136q0 50-50 50H14Q0 200 0 186V14Q0 0 14 0z', w: 120, h: 200,
    detail: (i) => `<defs><linearGradient id="${i}s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#d6ffa8"/><stop offset="1" stop-color="#86e06a"/></linearGradient>${dome(i + 'b', '#ff5fa0', '#b0125a')}
        <filter id="${i}g" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="5" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>
      <rect x="14" y="16" width="92" height="76" rx="8" fill="#140a30" fill-opacity=".55"/>
      <circle cx="21" cy="40" r="2.2" fill="#ff4f6a"/>
      <rect x="27" y="25" width="68" height="56" rx="3" fill="url(#${i}s)" filter="url(#${i}g)"/>
      <g fill="#2f6b2a" opacity=".75">${pixelShape(['.........', '....#....', '...###...', '..#####..', '.#######.', '#########'], 34, 50, 5.6, '#2f6b2a')}</g>
      <rect x="40" y="34" width="10" height="10" fill="#fdfff0" opacity=".9"/>
      ${miniCross(34, 132, 15)}
      <circle cx="96" cy="124" r="9.5" fill="url(#${i}b)"/><circle cx="76" cy="136" r="9.5" fill="url(#${i}b)"/>
      <rect x="44" y="162" width="14" height="4" rx="2" fill="#140a30" opacity=".4" transform="rotate(-25 51 164)"/><rect x="64" y="162" width="14" height="4" rx="2" fill="#140a30" opacity=".4" transform="rotate(-25 71 164)"/>
      ${[0, 1, 2, 3].map(k => `<rect x="${78 + k * 8}" y="166" width="4" height="20" rx="2" transform="rotate(-28 ${80 + k * 8} 176)" fill="#140a30" opacity=".35"/>`).join('')}`,
  },
  pad: {
    d: 'M66 0h92q42 0 54 46l18 64q8 40-24 40-22 0-36-28l-10-18H62l-10 18q-14 28-36 28-32 0-24-40l18-64Q24 0 66 0z', w: 224, h: 150,
    detail: (i) => `<defs>${dome(i + 'a', '#ffd84a', '#c98a00')}${dome(i + 'b', '#4dd0ff', '#0a6fb0')}${dome(i + 'c', '#ff4f7a', '#b0123e')}${dome(i + 'd', '#6dff9a', '#12a04a')}
        <radialGradient id="${i}k" cx=".5" cy=".4" r=".6"><stop offset="0" stop-color="#3a3160"/><stop offset="1" stop-color="#140a30"/></radialGradient></defs>
      ${miniCross(50, 56, 17)}
      <circle cx="178" cy="40" r="9" fill="url(#${i}a)"/><circle cx="162" cy="56" r="9" fill="url(#${i}b)"/><circle cx="194" cy="56" r="9" fill="url(#${i}c)"/><circle cx="178" cy="72" r="9" fill="url(#${i}d)"/>
      <circle cx="84" cy="92" r="16" fill="url(#${i}k)" opacity=".75"/><circle cx="84" cy="92" r="16" fill="none" stroke="#fff" stroke-opacity=".5" stroke-width="2"/>
      <circle cx="140" cy="92" r="16" fill="url(#${i}k)" opacity=".75"/><circle cx="140" cy="92" r="16" fill="none" stroke="#fff" stroke-opacity=".5" stroke-width="2"/>
      <rect x="100" y="36" width="10" height="5" rx="2.5" fill="#fff" opacity=".55"/><rect x="116" y="36" width="10" height="5" rx="2.5" fill="#fff" opacity=".55"/>`,
  },
  disccon: {
    d: roundPoly([[0, 0], [200, 0], [200, 170], [0, 170]], 20), w: 200, h: 170,
    detail: (i) => `<defs><linearGradient id="${i}r" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ff6ad5"/><stop offset=".25" stop-color="#ffcf6a"/><stop offset=".5" stop-color="#9dff8a"/><stop offset=".75" stop-color="#5ae0ff"/><stop offset="1" stop-color="#8f7bff"/></linearGradient></defs>
      <circle cx="100" cy="76" r="54" fill="url(#${i}r)" opacity=".55"/>
      <circle cx="100" cy="76" r="60" fill="#fff" fill-opacity=".12" stroke="#fff" stroke-opacity=".7" stroke-width="3"/>
      <circle cx="100" cy="76" r="15" fill="#140a30" fill-opacity=".55" stroke="#fff" stroke-opacity=".6" stroke-width="2"/>
      <circle cx="28" cy="148" r="8" fill="#fff" opacity=".85"/><circle cx="172" cy="148" r="8" fill="#fff" opacity=".85"/>
      <rect x="68" y="144" width="64" height="8" rx="4" fill="#140a30" opacity=".4"/><circle cx="160" cy="18" r="4" fill="#3bff9a"/>`,
  },
  tower: {
    d: 'M0 32Q0 0 30 6L45 10 60 6Q90 0 90 32v156q0 32-30 26l-15-4-15 4Q0 220 0 188z', w: 90, h: 220,
    detail: (i) => `<defs><linearGradient id="${i}t" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#140a30" stop-opacity=".6"/><stop offset="1" stop-color="#140a30" stop-opacity=".3"/></linearGradient></defs>
      <rect x="35" y="18" width="20" height="186" rx="9" fill="url(#${i}t)"/><rect x="39" y="28" width="12" height="3" rx="1.5" fill="#6fd6ff" style="filter:drop-shadow(0 0 4px #6fd6ff)"/>`,
  },
  boxcon: {
    d: roundPoly([[0, 0], [220, 0], [220, 120], [0, 120]], 12), w: 220, h: 120,
    detail: (i) => `<rect x="4" y="4" width="212" height="42" rx="9" fill="#fff" opacity=".16"/>
      <rect x="40" y="16" width="140" height="16" rx="4" fill="#140a30" opacity=".5"/>
      <rect x="14" y="68" width="86" height="38" rx="5" fill="#140a30" opacity=".4"/>
      <rect x="120" y="82" width="22" height="15" rx="3" fill="#fff" opacity=".85"/><rect x="150" y="82" width="22" height="15" rx="3" fill="#fff" opacity=".85"/>
      <circle cx="196" cy="90" r="5.5" fill="#ff4f6a" style="filter:drop-shadow(0 0 5px #ff4f6a)"/>`,
  },
  hybrid: {
    d: roundPoly([[0, 0], [240, 0], [240, 110], [0, 110]], 26), w: 240, h: 110,
    detail: (i) => `<defs><linearGradient id="${i}s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1c2a55"/><stop offset="1" stop-color="#0a0f24"/></linearGradient></defs>
      <path d="M50 0H26Q0 0 0 26v58q0 26 26 26h24z" fill="#3ee6c1" opacity=".72"/><path d="M190 0h24q26 0 26 26v58q0 26-26 26h-24z" fill="#ffb03b" opacity=".72"/>
      <rect x="58" y="8" width="124" height="94" rx="6" fill="url(#${i}s)"/>
      <g style="filter:drop-shadow(0 0 5px #47fff0)">${pixelShape(['#....', '###..', '#####', '###..', '#....'], 108, 41, 5.6, '#47fff0')}</g>
      <circle cx="25" cy="34" r="9" fill="#fff" opacity=".9"/>${miniCross(25, 78, 9, '#fff', .8)}<circle cx="215" cy="76" r="9" fill="#fff" opacity=".9"/>${[0, 1, 2, 3].map(k => `<circle cx="${215 + [0, 9, 0, -9][k]}" cy="${34 + [-9, 0, 9, 0][k]}" r="3.6" fill="#fff" opacity=".85"/>`).join('')}`,
  },
  cart: {
    d: 'M0 24Q0 0 24 0h124q24 0 24 24v204l-18 18v34H18v-34L0 228z', w: 172, h: 280,
    detail: (i) => `<defs><linearGradient id="${i}l" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ff4f8b"/><stop offset=".6" stop-color="#ff7a59"/><stop offset="1" stop-color="#ffb13b"/></linearGradient>
        <linearGradient id="${i}g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff1c2"/><stop offset="1" stop-color="#c8912e"/></linearGradient></defs>
      ${[0, 1, 2, 3, 4, 5, 6].map(k => `<rect x="${34 + k * 16}" y="14" width="7" height="30" rx="3.5" fill="#fff" opacity=".3"/>`).join('')}
      <rect x="22" y="58" width="128" height="120" rx="14" fill="url(#${i}l)"/>
      <rect x="22" y="58" width="128" height="120" rx="14" fill="none" stroke="#fff" stroke-opacity=".55" stroke-width="2"/>
      <path d="M22 72q0-14 14-14h100q14 0 14 14v22Q90 70 22 110z" fill="#fff" opacity=".2"/>
      <g style="filter:drop-shadow(0 3px 4px rgba(90,0,40,.45))">${pixelShape(['.####.', '##..##', '##....', '##....', '##..##', '.####.'], 59, 91, 9, '#fff')}</g>
      ${[0, 1, 2, 3, 4, 5, 6, 7].map(k => `<rect x="${27 + k * 15.5}" y="248" width="9" height="28" rx="2" fill="url(#${i}g)"/>`).join('')}`,
  },
};

// Place a glass console: (x,y) = centre on the icon, s = scale, r = rotation.
function consoleAt(name, x, y, s, r = 0, opts = {}, parent = plate) {
  const c = CONSOLES[name];
  const w = div(`left:0;top:0;width:1024px;height:1024px;transform-origin:0 0;
    transform:translate(${x}px,${y}px) rotate(${r}deg) scale(${s}) translate(${-c.w / 2}px,${-c.h / 2}px);${opts.o ? `opacity:${opts.o}` : ''}`, parent);
  glass(c.d, { tint: 'linear-gradient(165deg,rgba(255,255,255,.34),rgba(255,255,255,.08))', blur: 18, sat: 1.7, bright: 1.1, shadow: .38, ...opts, parent: w, k: s });
  svg(c.detail('c' + (uid++)), w);
  return w;
}

Object.assign(VARIANTS, {
  // ---- Stack: layered glass consoles at different depths ----
  s1() { // faithful upgrade of the original: dusk gradient
    div(`inset:0;background:linear-gradient(160deg,#7a2cff 0%,#b43cd8 42%,#ff4f86 75%,#ff8a4f 100%)`);
    blob(760, 250, 220, '#5a7bff', .6, 90); blob(260, 820, 240, '#ffb347', .55, 90); blob(520, 520, 200, '#ff9ad5', .35, 90);
    consoleAt('disccon', 668, 372, 1.45, 10);
    consoleAt('pad', 360, 660, 1.5, -9);
    consoleAt('handheld', 505, 470, 2.05, -6, { shadow: .45 });
    plateFinish(.3, .6);
  },
  s2() { // night: neon screens glowing through stacked glass
    div(`inset:0;background:radial-gradient(110% 90% at 50% 0%,#23306b 0%,#11163a 50%,#05060f 100%)`);
    blob(720, 330, 190, '#ff4fa8', .55, 80); blob(300, 700, 220, '#29d3ff', .5, 90); blob(560, 560, 170, '#8a5cff', .5, 70);
    consoleAt('hybrid', 640, 350, 1.55, 8);
    consoleAt('pad', 350, 670, 1.45, -10);
    consoleAt('handheld', 500, 480, 2.05, -5, { shadow: .6 });
    svg(sparkle(250, 280, 7, .9) + sparkle(820, 760, 6, .8));
    plateFinish(.22, .5);
  },
  s3() { // frost: light plate, colour only from what shows through the glass
    div(`inset:0;background:linear-gradient(170deg,#ffffff 0%,#eef1f7 55%,#dde2ec 100%)`);
    blob(690, 360, 170, '#8f7bff', .75, 50); blob(330, 680, 170, '#ff5f8f', .7, 50); blob(520, 470, 150, '#3ee6c1', .6, 50); blob(640, 700, 120, '#ffc42e', .65, 50);
    const o = { tint: 'linear-gradient(165deg,rgba(255,255,255,.5),rgba(255,255,255,.18))', shadow: .2, glowTop: 1, bright: 1 };
    consoleAt('disccon', 668, 372, 1.45, 10, o);
    consoleAt('pad', 360, 660, 1.5, -9, o);
    consoleAt('handheld', 505, 470, 2.05, -6, { ...o, shadow: .28 });
    plateFinish(.1, .9);
  },

  // ---- Orbit: every console circling one cartridge ----
  o1() { // faithful upgrade: deep teal night, glowing orbit ring
    div(`inset:0;background:linear-gradient(165deg,#0f4a5e 0%,#0b2240 45%,#060a1c 100%)`);
    blob(300, 760, 230, '#1fb6d6', .5, 90); blob(780, 250, 220, '#8a5cff', .55, 90); blob(512, 512, 170, '#ff4f8b', .35, 70);
    svg(`<defs><linearGradient id="orb" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#6ff2ff"/><stop offset=".5" stop-color="#ffffff" stop-opacity=".25"/><stop offset="1" stop-color="#c77dff"/></linearGradient></defs>
      <circle cx="512" cy="512" r="292" fill="none" stroke="url(#orb)" stroke-width="3" opacity=".7" style="filter:drop-shadow(0 0 6px rgba(111,242,255,.8))"/>`);
    orbitRing(512, 512, 292, 292);
    consoleAt('cart', 512, 512, 1.0, 0, { shadow: .5 });
    plateFinish(.2, .5);
  },
  o2() { // planet: tilted orbit with depth; back consoles behind the cartridge
    div(`inset:0;background:radial-gradient(120% 100% at 50% 20%,#2b2466 0%,#130f35 50%,#06040f 100%)`);
    blob(512, 470, 200, 'conic-gradient(#ff4fa8,#ffb13b,#7cffb2,#29d3ff,#8a5cff,#ff4fa8)', .55, 70);
    const cx = 512, cy = 560, rx = 330, ry = 120;
    const ring = (half) => svg(`<defs><linearGradient id="or${half}" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#6ff2ff"/><stop offset="1" stop-color="#ff7ad9"/></linearGradient></defs>
      <path d="M${cx - rx} ${cy}A${rx} ${ry} 0 0 ${half ? 0 : 1} ${cx + rx} ${cy}" fill="none" stroke="url(#or${half})" stroke-width="${half ? 4 : 2.5}" opacity="${half ? .85 : .45}" style="filter:drop-shadow(0 0 6px rgba(255,255,255,.6))"/>`);
    const names = ['handheld', 'pad', 'disccon', 'tower', 'boxcon', 'hybrid'];
    const items = names.map((n, i) => { const a = (i / 6) * 2 * Math.PI; return { n, x: cx + rx * Math.cos(a), y: cy + ry * Math.sin(a), z: Math.sin(a) }; });
    ring(0);
    items.filter(t => t.z < 0).sort((a, b) => a.z - b.z).forEach(t => consoleAt(t.n, t.x, t.y - 40, .42 + .12 * (t.z + 1), 0, { o: .8 }));
    consoleAt('cart', 512, 440, 1.1, 0, { shadow: .55 });
    ring(1);
    items.filter(t => t.z >= 0).sort((a, b) => a.z - b.z).forEach(t => consoleAt(t.n, t.x, t.y - 30, .5 + .14 * t.z));
    svg(sparkle(230, 250, 7, .9) + sparkle(810, 220, 5, .75));
    plateFinish(.22, .5);
  },
  o3() { // light: bright plate, each console tinted by a glow beneath it
    div(`inset:0;background:linear-gradient(170deg,#ffffff 0%,#eef1f7 55%,#dde2ec 100%)`);
    svg(`<circle cx="512" cy="512" r="292" fill="none" stroke="#8a93b0" stroke-opacity=".35" stroke-width="2.5" stroke-dasharray="2 12" stroke-linecap="round"/>`);
    orbitRing(512, 512, 292, 292, true);
    blob(512, 512, 130, '#ff5f8f', .55, 50);
    consoleAt('cart', 512, 512, 1.0, 0, { tint: 'linear-gradient(165deg,rgba(255,255,255,.55),rgba(255,255,255,.2))', shadow: .25, glowTop: 1, bright: 1 });
    plateFinish(.1, .9);
  },
});

// Six consoles evenly around (cx,cy); light=true puts a colour glow under each.
function orbitRing(cx, cy, rx, ry, light = false) {
  const names = ['handheld', 'pad', 'disccon', 'tower', 'boxcon', 'hybrid'];
  const glows = ['#7fe070', '#8f7bff', '#5ae0ff', '#3ee6c1', '#ff7a59', '#ffb03b'];
  names.forEach((n, i) => {
    const a = -Math.PI / 2 + i * Math.PI / 3, x = cx + rx * Math.cos(a), y = cy + ry * Math.sin(a);
    if (light) blob(x, y, 70, glows[i], .75, 30);
    consoleAt(n, x, y, n === 'tower' ? .6 : .64, 0, light ? { tint: 'linear-gradient(165deg,rgba(255,255,255,.55),rgba(255,255,255,.2))', shadow: .22, glowTop: 1, bright: 1 } : {});
  });
}
