# Generic console silhouettes (no brand marks) in a local box, placed with transform.
from make import base, end, pixels

def g(x, y, s, body, rot=0):
    return f'<g transform="translate({x} {y}) rotate({rot}) scale({s})">{body}</g>'

GL = 'fill="url(#glass)" stroke="url(#rim)" stroke-width="4"'
DK = 'fill="#0a0620" fill-opacity=".45"'
LT = 'fill="#fff" fill-opacity=".8"'

def handheld(scr="#9bff7a"):   # 120 x 200, tall brick with the one fat corner
    return (f'<path d="M12 0h96q12 0 12 12v140q0 48-48 48H12Q0 200 0 188V12Q0 0 12 0z" {GL}/>'
            f'<rect x="14" y="16" width="92" height="74" rx="8" {DK}/><rect x="26" y="26" width="68" height="54" rx="3" fill="{scr}" fill-opacity=".85"/>'
            f'<path d="M26 128h10v-10h10v10h10v10H46v10H36v-10H26z" {LT}/>'
            f'<circle cx="94" cy="124" r="9" {LT}/><circle cx="76" cy="136" r="9" {LT}/>'
            + "".join(f'<rect x="{70+i*9}" y="164" width="4" height="20" rx="2" transform="rotate(-25 {72+i*9} 174)" {DK}/>' for i in range(4)))

def boxcon():                   # 220 x 120, flat 8-bit box
    return (f'<rect x="0" y="0" width="220" height="120" rx="10" {GL}/>'
            f'<rect x="0" y="0" width="220" height="44" rx="10" fill="#fff" fill-opacity=".14"/>'
            f'<rect x="40" y="14" width="140" height="16" rx="3" {DK}/>'
            f'<rect x="14" y="70" width="84" height="36" rx="4" {DK}/>'
            f'<rect x="120" y="82" width="22" height="16" rx="2" {LT}/><rect x="150" y="82" width="22" height="16" rx="2" {LT}/><circle cx="196" cy="90" r="6" fill="#ff4f6a"/>')

def disccon():                  # 200 x 170, top-down disc lid
    return (f'<rect x="0" y="0" width="200" height="170" rx="18" {GL}/>'
            f'<circle cx="100" cy="76" r="58" fill="#fff" fill-opacity=".18" stroke="#fff" stroke-opacity=".6" stroke-width="3"/>'
            f'<circle cx="100" cy="76" r="14" {DK}/>'
            f'<circle cx="30" cy="148" r="8" {LT}/><circle cx="170" cy="148" r="8" {LT}/><rect x="70" y="144" width="60" height="8" rx="4" {DK}/>')

def tower():                    # 90 x 220, modern vertical slab with side fins
    return (f'<path d="M0 30Q0 0 30 6L45 10 60 6Q90 0 90 30v160q0 30-30 24l-15-4-15 4Q0 220 0 190z" {GL}/>'
            f'<rect x="35" y="16" width="20" height="190" rx="8" {DK}/><rect x="40" y="24" width="10" height="3" rx="1.5" fill="#6fd6ff"/>')

def pad():                      # 216 x 150 gamepad
    return (f'<path d="M58 0h100q40 0 52 46l18 62q8 40-24 42-22 0-36-30l-8-18H56l-8 18q-14 30-36 30-32-2-24-42l18-62Q18 0 58 0z" transform="translate(6 0)" {GL}/>'
            f'<path d="M40 50h12V38h12v12h12v12H64v12H52V62H40z" {LT}/>'
            + "".join(f'<circle cx="{cx}" cy="{cy}" r="8" fill="{c}"/>' for cx, cy, c in [(176,44,"#ffd84a"),(160,58,"#4dd0ff"),(192,58,"#ff4f7a"),(176,72,"#6dff9a")]))

def hybrid(play=False):                   # 240 x 110 tablet with snap-on grips
    return (f'<rect x="50" y="0" width="140" height="110" rx="6" {GL}/><rect x="60" y="10" width="120" height="90" rx="3" {DK}/>'
            f'<path d="M50 0H26Q0 0 0 26v58q0 26 26 26h24z" fill="#27c9ff" fill-opacity=".75" stroke="url(#rim)" stroke-width="4"/>'
            f'<path d="M190 0h24q26 0 26 26v58q0 26-26 26h-24z" fill="#ff4f6a" fill-opacity=".75" stroke="url(#rim)" stroke-width="4"/>'
            f'<circle cx="25" cy="32" r="9" {LT}/><circle cx="215" cy="70" r="9" {LT}/>'
            + (pixels(["#......", "###....", "#####..", "#######", "#####..", "###....", "#......"], 102, 37, 5.2, "#47fff0", 'filter="url(#glow)"') if play else ''))

glow = lambda a, b: (f'<circle cx="230" cy="830" r="280" fill="{a}" opacity=".55" filter="url(#soft)"/>'
                     f'<circle cx="820" cy="210" r="260" fill="{b}" opacity=".5" filter="url(#soft)"/>')

# A — Lineup: consoles standing on a glass shelf, like the in-app Game Shelf
a = base([(0, "#16224f"), (.6, "#1c1250"), (1, "#07061c")], "", glow("#ff4f8b", "#28d7ff"))
a += '<g transform="translate(0 -100)">' + '<rect x="170" y="690" width="684" height="26" rx="13" fill="url(#glass)" stroke="url(#rim)" stroke-width="3"/><rect x="190" y="716" width="644" height="40" fill="#000" opacity=".25" filter="url(#blur8)"/>'
a += '<g filter="url(#drop)">' + g(205, 470, 1, tower()) + g(310, 520, 1, disccon()) + g(525, 490, 1, handheld()) + g(660, 570, .78, boxcon()) + '</g></g>'
a += end()

# B — Stack: layered glass consoles receding in depth, like Wallet cards
b = base([(0, "#6a2cff"), (.55, "#c23bd4"), (1, "#ff5f6d")], "", glow("#ffb347", "#4d7bff"))
b += '<g opacity=".55">' + g(560, 250, 1.35, disccon(), 10) + '</g>'
b += '<g opacity=".8" filter="url(#drop)">' + g(210, 560, 1.4, pad(), -8) + '</g>'
b += '<g filter="url(#drop)">' + g(340, 250, 2.0, handheld("#b8ff8a"), -6) + '</g>'
b += end()

# C — Orbit: six consoles circling a glass cartridge hub
import math
c = base([(0, "#0e3b4f"), (.6, "#0b1f3a"), (1, "#050a18")], "", glow("#27d3ff", "#9b5cff"))
c += '<circle cx="512" cy="512" r="290" fill="none" stroke="#fff" stroke-opacity=".18" stroke-width="3" stroke-dasharray="6 14"/>'
parts = [(handheld(), 120, 200), (pad(), 216, 150), (disccon(), 200, 170), (tower(), 90, 220), (boxcon(), 220, 120), (hybrid(), 240, 110)]
for i, (body, w, h) in enumerate(parts):
    ang = math.radians(-90 + i * 60); cx, cy = 512 + 290 * math.cos(ang), 512 + 290 * math.sin(ang)
    sc = 0.62
    c += g(cx - w * sc / 2, cy - h * sc / 2, sc, body)
c += ('<g filter="url(#drop)"><path d="M432 400q0-22 22-22h116q22 0 22 22v200l-18 18v32H450v-32l-18-18z" fill="url(#glass)" stroke="url(#rim)" stroke-width="5"/>'
      '<rect x="456" y="420" width="112" height="100" rx="12" fill="#ff4f8b" fill-opacity=".8"/>'
      + "".join(f'<rect x="{458+i*14}" y="620" width="8" height="26" rx="2" fill="#f5c55a"/>' for i in range(8)) + '</g>')
c += pixels(["####", "#...", "#...", "####"], 488, 446, 12, "#fff")
c += end()

# D — Hybrid in hand: modern tablet-console front and centre, retro handheld peeking behind
d = base([(0, "#ff9a3c"), (.5, "#ff3c78"), (1, "#4a1fd0")], "", glow("#ffe36a", "#2a1bff"))
d += '<g opacity=".7">' + g(560, 190, 1.5, handheld(), 14) + '</g>'
d += '<g filter="url(#drop)">' + g(160, 430, 2.9, hybrid(True), -4) + '</g>'
d += end()

for n, svg in [("5-console-lineup", a), ("6-console-stack", b), ("7-console-orbit", c), ("8-hybrid-hero", d)]:
    open(f"{n}.svg", "w").write(svg)
