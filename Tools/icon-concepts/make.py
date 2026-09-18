import math
# ponytail: plain SVG, rendered to PNG by macOS Quick Look; swap in Icon Composer for the final .icon
PLATE = '<rect x="100" y="100" width="824" height="824" rx="185"'
def base(bg_stops, extra_defs="", glow=""):
    stops = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in bg_stops)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
<defs>
<linearGradient id="bg" x1="0" y1="0" x2="0.4" y2="1">{stops}</linearGradient>
<linearGradient id="rim" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".75"/><stop offset=".5" stop-color="#fff" stop-opacity=".12"/><stop offset="1" stop-color="#fff" stop-opacity=".45"/></linearGradient>
<linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".55"/><stop offset=".45" stop-color="#fff" stop-opacity=".06"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
<linearGradient id="glass" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".34"/><stop offset="1" stop-color="#fff" stop-opacity=".10"/></linearGradient>
<filter id="drop" x="-20%" y="-20%" width="140%" height="150%"><feGaussianBlur in="SourceAlpha" stdDeviation="18"/><feOffset dy="22"/><feComponentTransfer><feFuncA type="linear" slope=".35"/></feComponentTransfer><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>
<filter id="soft" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="60"/></filter>
<filter id="blur8"><feGaussianBlur stdDeviation="8"/></filter>
<filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="14" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
<clipPath id="plate">{PLATE}/></clipPath>
{extra_defs}
</defs>
<g filter="url(#drop)">{PLATE} fill="url(#bg)"/></g>
<g clip-path="url(#plate)">{glow}'''
def end():
    # plate rim + top sheen, shared by every concept
    return f'''</g>
{PLATE} fill="none" stroke="url(#rim)" stroke-width="3"/>
<path d="M285 100h454a185 185 0 0 1 185 185v40C700 250 324 250 100 325v-40A185 185 0 0 1 285 100z" fill="url(#sheen)" opacity=".5"/>
</svg>'''

def pixels(cells, x0, y0, s, fill, extra=""):
    return "".join(f'<rect x="{x0+c*s}" y="{y0+r*s}" width="{s}" height="{s}" fill="{fill}" {extra}/>'
                   for r, row in enumerate(cells) for c, ch in enumerate(row) if ch == "#")

# 1 — Glass cartridge -------------------------------------------------------
sun = ["....####....", "..########..", ".##########.", "############"]
label = f'''<linearGradient id="lbl" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ff4f8b"/><stop offset=".55" stop-color="#ff9a3c"/><stop offset="1" stop-color="#ffd84a"/></linearGradient>
<linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffe7a3"/><stop offset="1" stop-color="#c8912e"/></linearGradient>
<clipPath id="lblclip"><rect x="352" y="330" width="320" height="250" rx="26"/></clipPath>'''
c1 = base([(0, "#2a1b6b"), (.6, "#3b1f8f"), (1, "#0e0a2e")], label,
    '<circle cx="250" cy="820" r="260" fill="#ff4f8b" opacity=".55" filter="url(#soft)"/><circle cx="820" cy="230" r="240" fill="#28d7ff" opacity=".45" filter="url(#soft)"/>')
c1 += '<g transform="rotate(-8 512 540)" filter="url(#drop)">'
c1 += '<path d="M292 250q0-40 40-40h360q40 0 40 40v470l-40 40v70H332v-70l-40-40z" fill="url(#glass)" stroke="url(#rim)" stroke-width="5"/>'
c1 += "".join(f'<rect x="{362+i*34}" y="232" width="14" height="60" rx="7" fill="#fff" opacity=".28"/>' for i in range(9))
c1 += '<rect x="352" y="330" width="320" height="250" rx="26" fill="url(#lbl)"/>'
c1 += '<g clip-path="url(#lblclip)">' + pixels(sun, 440, 438, 12, "#fff6c8") + \
      '<path d="M352 580l80-80 50 40 70-90 120 130z" fill="#6a1d7a" opacity=".85"/>' + \
      "".join(f'<rect x="352" y="{520+i*14}" width="320" height="4" fill="#fff" opacity=".18"/>' for i in range(5)) + '</g>'
c1 += '<rect x="352" y="330" width="320" height="250" rx="26" fill="none" stroke="#fff" stroke-opacity=".5" stroke-width="3"/>'
c1 += "".join(f'<rect x="{350+i*27}" y="742" width="16" height="72" rx="3" fill="url(#gold)"/>' for i in range(12))
c1 += '<path d="M300 250q0-32 32-32h360q32 0 32 32v120C560 300 420 320 300 400z" fill="url(#sheen)" opacity=".8"/>'
c1 += '</g>' + end()

# 2 — Liquid glass D-pad ----------------------------------------------------
cross = "M430 250h164q20 0 20 20v140h140q20 0 20 20v164q0 20-20 20H614v140q0 20-20 20H430q-20 0-20-20V614H270q-20 0-20-20V430q0-20 20-20h140V270q0-20 20-20z"
c2 = base([(0, "#12b0ff"), (.55, "#1463ff"), (1, "#0a1f7a")], "",
    '<circle cx="780" cy="820" r="280" fill="#7b5cff" opacity=".6" filter="url(#soft)"/><circle cx="220" cy="200" r="220" fill="#6ff2ff" opacity=".5" filter="url(#soft)"/>')
c2 += f'<path d="{cross}" fill="#001040" opacity=".35" filter="url(#blur8)" transform="translate(0 26)"/>'
c2 += f'<path d="{cross}" fill="url(#glass)" stroke="url(#rim)" stroke-width="6"/>'
c2 += f'<path d="{cross}" fill="url(#sheen)" opacity=".7" clip-path="inset(0 0 55% 0)"/>'
for d in ["M512 300l-44 56h88z", "M512 724l-44-56h88z", "M300 512l56-44v88z", "M724 512l-56-44v88z"]:
    c2 += f'<path d="{d}" fill="#fff" opacity=".85" stroke="#fff" stroke-width="10" stroke-linejoin="round"/>'
c2 += '<circle cx="512" cy="512" r="58" fill="#001a66" opacity=".25"/><circle cx="512" cy="512" r="58" fill="none" stroke="#fff" stroke-opacity=".5" stroke-width="3"/>'
c2 += end()

# 3 — Iridescent disc -------------------------------------------------------
hues = ["#ff3d7f", "#ff9f1c", "#ffe14d", "#4dff9a", "#27d3ff", "#5b6cff", "#c04dff", "#ff3d7f"]
wedges = ""
for i in range(24):
    a0, a1 = math.radians(i * 15 - 90), math.radians((i + 1) * 15 - 90)
    col = hues[i % 8] if i % 3 != 2 else "#e8ecff"
    wedges += f'<path d="M512 512L{512+420*math.cos(a0):.1f} {512+420*math.sin(a0):.1f}L{512+420*math.cos(a1):.1f} {512+420*math.sin(a1):.1f}z" fill="{col}"/>'
disc_defs = '''<mask id="ring"><circle cx="512" cy="512" r="330" fill="#fff"/><circle cx="512" cy="512" r="96" fill="#000"/></mask>
<radialGradient id="silver"><stop offset=".25" stop-color="#fff" stop-opacity=".9"/><stop offset="1" stop-color="#fff" stop-opacity=".15"/></radialGradient>'''
c3 = base([(0, "#3a3a44"), (.6, "#1c1c22"), (1, "#0b0b10")], disc_defs,
    '<circle cx="512" cy="560" r="330" fill="#7a5cff" opacity=".5" filter="url(#soft)"/>')
c3 += f'<g filter="url(#drop)"><g mask="url(#ring)"><circle cx="512" cy="512" r="330" fill="#dfe3ee"/><g filter="url(#soft)" opacity=".85">{wedges}</g>'
c3 += '<circle cx="512" cy="512" r="330" fill="url(#silver)" opacity=".35"/>'
c3 += "".join(f'<circle cx="512" cy="512" r="{r}" fill="none" stroke="#fff" stroke-opacity=".12" stroke-width="2"/>' for r in range(130, 330, 18))
c3 += '<path d="M182 512a330 330 0 0 1 660 0C700 430 330 430 182 512z" fill="url(#sheen)" opacity=".9"/></g>'
c3 += '<circle cx="512" cy="512" r="330" fill="none" stroke="url(#rim)" stroke-width="5"/>'
c3 += '<circle cx="512" cy="512" r="150" fill="none" stroke="#fff" stroke-opacity=".35" stroke-width="30"/>'
c3 += '<circle cx="512" cy="512" r="96" fill="none" stroke="#fff" stroke-opacity=".7" stroke-width="4"/></g>'
C = [".####.", "##..##", "##....", "##....", "##..##", ".####."]
c3 += pixels(C, 512 - 3*12 + 200, 512 - 3*12 - 190, 12, "#fff", 'opacity=".9"')
c3 += end()

# 4 — Glass CRT -------------------------------------------------------------
play = ["#......", "###....", "#####..", "#######", "#####..", "###....", "#......"]
crt_defs = '''<radialGradient id="scr" cx=".5" cy=".45" r=".7"><stop offset="0" stop-color="#15384a"/><stop offset="1" stop-color="#03070f"/></radialGradient>
<clipPath id="scrclip"><rect x="290" y="330" width="360" height="300" rx="60"/></clipPath>'''
c4 = base([(0, "#ffb347"), (.45, "#ff4f7a"), (1, "#5a23d9")], crt_defs,
    '<circle cx="820" cy="820" r="260" fill="#2a1bff" opacity=".45" filter="url(#soft)"/><circle cx="200" cy="180" r="220" fill="#ffe36a" opacity=".55" filter="url(#soft)"/>')
c4 += '<g filter="url(#drop)"><rect x="236" y="276" width="552" height="420" rx="96" fill="url(#glass)" stroke="url(#rim)" stroke-width="6"/>'
c4 += '<rect x="290" y="330" width="360" height="300" rx="60" fill="url(#scr)"/>'
c4 += '<g clip-path="url(#scrclip)">' + pixels(play, 422, 424, 16, "#47fff0", 'filter="url(#glow)"') + \
      "".join(f'<rect x="290" y="{330+i*8}" width="360" height="3" fill="#000" opacity=".35"/>' for i in range(38)) + \
      '<ellipse cx="420" cy="380" rx="150" ry="50" fill="#fff" opacity=".08"/></g>'
c4 += '<rect x="290" y="330" width="360" height="300" rx="60" fill="none" stroke="#fff" stroke-opacity=".35" stroke-width="3"/>'
c4 += '<circle cx="718" cy="400" r="26" fill="#fff" opacity=".55"/><circle cx="718" cy="480" r="26" fill="#fff" opacity=".35"/>'
c4 += "".join(f'<rect x="700" y="{548+i*18}" width="36" height="6" rx="3" fill="#fff" opacity=".4"/>' for i in range(4))
c4 += '<path d="M320 696l-24 56h72l12-56zM704 696l24 56h-72l-12-56z" fill="#fff" opacity=".35"/>'
c4 += '<path d="M244 372q0-88 88-88h360q88 0 88 88v20C620 330 400 330 244 440z" fill="url(#sheen)" opacity=".85"/></g>'
c4 += end()

if __name__ == "__main__":
  for n, svg in [("1-glass-cartridge", c1), ("2-liquid-dpad", c2), ("3-iridescent-disc", c3), ("4-glass-crt", c4)]:
    open(f"{n}.svg", "w").write(svg)
