"""Turn the DATA lines of P-C-S.BAS into Z80 tables: the head, the mouth
shapes it is animated with, and the speech that drives them.

The BASIC draws the head with the firmware's graphics coordinates: ORIGIN
320,0, x scaled by 3, y by 2.9, and the whole half is then mirrored by
negating x (va=-1).  MODE 2 is 640x200 physical, so a logical y maps to
the scanline (399-y)/2 - the 399 is measured, not a typo.

Only the half is stored: dx from the centre fits in a byte (0..144) and
the other half of the face is the same bytes with the bits reversed.  The
scanline fits in a byte too, so every segment has 8-bit deltas and the
line routine never needs a 16-bit counter.
"""
import os, re, collections

A, B = 2.9, 3.0                 # line 80 of the BASIC: a=2.9 : b=3

# The BASIC centred the head at x=320.  Here it sits left, at 159/160, to
# leave the right of the screen for a text window - and 159 because the
# mirror has to stay on a byte boundary: x -> 319-x is column c -> 39-c.
HEADX   = 159
MIRRORC = 39

# ---------------------------------------------------------------- the head

# the 1985 BASIC, wherever it is kept relative to here
BASIC = next(p for p in ('../original/P-C-S.bas.txt', 'P-C-S.bas.txt')
             if os.path.exists(p))

toks = []
for line in open(BASIC, encoding='latin-1'):
    m = re.match(r'^(\d+)\s+DATA\s*(.*)$', line)
    if m and 190 <= int(m.group(1)) <= 650:
        toks += [t.strip() for t in m.group(2).split(',')]

polys, i = [], 0
while i < len(toks):
    x, y = toks[i], toks[i + 1]; i += 2
    if x == 'origin':
        x, y = toks[i], toks[i + 1]; i += 2
        polys.append([(float(x), float(y))])
    elif float(x) == -1:
        break
    else:
        polys[-1].append((float(x), float(y)))

# Two parts of the face move: the mouth and the left eye.  Each is a few
# polylines of the digitised head, and taking them out of the static
# drawing is not enough - the lines of the rest of the mesh that END on one
# of their vertices have to move with them, or the face tears open.  So
# every segment of every other polyline that touches a moving vertex is
# animated too, pivoting about an anchor a fixed distance back along
# itself; the remainder of that line stays static and is drawn once.
#
# 15 is the outer lip contour, 16 the inner one (the opening), 26, 27 and
# 28 the creases to the corner.  11, 12 and 13, which sit half a face
# higher and look just as much like a mouth in a wireframe, are the
# nostrils.  17 is the eye opening; 18, the fold above it, stays put and
# is merely dragged along at the corner it shares.
MOUTH   = [15, 16, 26, 27, 28]  # outer lip, inner lip, three creases
CHIN    = [38, 39]              # the crease under the lip and the chin
EYE     = [17]                  # the eye opening
MID     = 41.5                  # the line the lips part along: the two
                                # corners, (17,40) and (10,42), sit on it
LIPX    = 17.0                  # and that is how far out they reach - the
                                # lips are hinged there and do not move
EYEMID  = 88.0                  # likewise the eye's corners
RISEMAX = 3.5                   # the upper lip stops below the nostril line
                                # at y=61 and the fold at (6,60): measured
                                # off the mesh, not guessed
DROPMAX = 5.0                   # and the jaw before the chin creases run
CHINTOP = 32.0                  # into the ones below them.  The jaw field
CHINBOT = 25.0                  # fades out between these, so nothing that
CHINX   = 24.0                  # is ordered down the face can cross
TOL     = 1.5                   # two vertices this close were digitised as
                                # the same point - (16,40) and (17,40) are
                                # the mouth corner written down twice

def near(a, b):
    return abs(a[0] - b[0]) <= TOL and abs(a[1] - b[1]) <= TOL

def anchor(fixed, mover, radius):
    """The point on fixed->mover that is `radius` back from the moving end:
    the far part of the line never moves, so only this stub is redrawn."""
    dx, dy = fixed[0] - mover[0], fixed[1] - mover[1]
    d = (dx * dx + dy * dy) ** 0.5
    if d <= radius:
        return fixed
    return (mover[0] + dx * radius / d, mover[1] + dy * radius / d)

GROUPS = [(MOUTH + CHIN, 12.0), (EYE, 8.0)]
gverts = [[v for n in idx for v in polys[n]] for idx, _ in GROUPS]
lipverts  = [v for n in MOUTH for v in polys[n]]
chinverts = [v for n in CHIN for v in polys[n]]

def group_of(v):
    for g, vs in enumerate(gverts):
        if any(near(v, m) for m in vs):
            return g
    return None

def is_lip(v):
    return any(near(v, m) for m in lipverts)

static, anim = [], [[], []]
for n, p in enumerate(polys):
    g = next((g for g, (idx, _) in enumerate(GROUPS) if n in idx), None)
    if g is not None:
        anim[g].append(p)               # all of it moves, keep it a chain
        continue
    chain = []
    for a, b in zip(p, p[1:]):
        ga, gb = group_of(a), group_of(b)
        if ga is None and gb is None:
            chain = chain or [a]
            chain.append(b)
            continue
        if chain:
            static.append(chain); chain = []
        assert ga is None or gb is None or ga == gb, (n, a, b)
        if ga is not None and gb is not None:
            anim[ga].append([a, b])
        elif ga is not None:
            k = anchor(b, a, GROUPS[ga][1])
            if k != b:
                static.append([b, k])
            anim[ga].append([a, k])
        else:
            k = anchor(a, b, GROUPS[gb][1])
            if k != a:
                static.append([a, k])
            anim[gb].append([k, b])
    if chain:
        static.append(chain)

def moved(p, g, fn):
    return [fn(x, y) if group_of((x, y)) == g else (x, y) for x, y in p]

def screen(x, y):
    """BASIC (x,y) -> (dx from the centre, scanline)."""
    return int(round(x * B)), (399 - int(round(y * A))) // 2

def raster(a, b):
    """Exactly the pixels line.asm's Bresenham puts down, so the generator
    can predict what the screen will look like."""
    (x0, y0), (x1, y1) = a, b
    if x0 > x1:
        (x0, y0), (x1, y1) = (x1, y1), (x0, y0)
    dx, dy = x1 - x0, abs(y1 - y0)
    sy = 1 if y1 > y0 else -1
    out, x, y = [], x0, y0
    if dx >= dy:
        err = dx >> 1
        for _ in range(dx + 1):
            out.append((x, y)); x += 1; err -= dy
            if err < 0: err += dx; y += sy
    else:
        err = dy >> 1
        for _ in range(dy + 1):
            out.append((x, y)); y += sy; err -= dx
            if err < 0: err += dy; x += 1
    return out

def coverage(chains):
    """How many times each screen pixel of the left half gets plotted."""
    c = collections.Counter()
    for p in chains:
        pts = [screen(x, y) for x, y in p]
        for a, b in zip(pts, pts[1:]):
            c.update(raster((HEADX - a[0], a[1]), (HEADX - b[0], b[1])))
    return c

def emit(f, name, plist, comment='', fix=False):
    f.write(f'{name}:{comment}\n')
    for p in plist:
        pts = [screen(x, y) for x, y in p]
        f.write(f'    defb {len(pts)}\n')
        for j in range(0, len(pts), 6):
            f.write('    defb ' + ','.join(f'{d},{y}' for d, y in pts[j:j+6]) + '\n')
    f.write('    defb 0\n\n')

def cost(plist):
    px = 0
    for p in plist:
        pts = [screen(x, y) for x, y in p]
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            px += max(abs(x1 - x0), abs(y1 - y0)) + 1
    return px

# -------------------------------------------------------------- the mouth
#
# One digitised mouth, one closed position.  The visemes are that mouth
# deformed: the lips move away from the mouth line by a weight that falls
# off towards the corner, where they stay pinned, and the whole thing is
# scaled sideways.  Between the lips goes the aperture - two arcs from the
# centre to the corner, which collapse onto the mouth line when shut, and
# then only one of them is emitted: in XOR, drawing a line twice rubs it out.

def mouth_shape(a, wide):
    """Opening the mouth and closing it are not the same movement.  Closing
    squashes the lips towards the line they meet on - the outer contour
    hardly moves, the inner edges come together.  Opening rotates the jaw:
    the lower lip and the chin below it travel down, the upper lip rises a
    little, and both are capped at the distance measured off the mesh, so
    the lip cannot climb into the nostrils and the chin creases cannot
    cross each other.  The jaw field fades with height and with distance
    from the centre, which is what keeps everything in order."""
    rise = min(a * 0.40, RISEMAX) if a > 0 else 0.0
    drop = min(a * 0.60, DROPMAX) if a > 0 else 0.0
    k    = 1.0 + a / 12.0 if a < 0 else 1.0

    def fn(x, y):
        if is_lip((x, y)):
            if a < 0:
                return (x * wide, MID + (y - MID) * k)
            w = max(0.0, 1.0 - x / LIPX)        # pinned at the corner
            return (x * wide, y + (rise * w if y >= MID else -drop * w))
        wy = min(1.0, max(0.0, (y - CHINBOT) / (CHINTOP - CHINBOT)))
        wx = min(1.0, max(0.0, 1.0 - x / CHINX))
        return (x, y - drop * wy * wx)

    return [moved(p, 0, fn) for p in anim[0]]

def eye_shape(k):
    """The eye opening scaled about its own corners; k=1 is wide awake."""
    return [moved(p, 1, lambda x, y: (x, EYEMID + (y - EYEMID) * k))
            for p in anim[1]]

#          name    how open
EYES = [('open',   1.00),
        ('half',   0.45),
        ('shut',   0.06)]


#          name      aperture wide     aperture: + opens the jaw, - closes
VISEMES = [('rest',       0.0,  1.00),   # the mouth as it was digitised
           ('shut',     -10.0,  0.95),   # MM PP BB - pressed together
           ('small',     -4.0,  1.00),   # AX IH and most consonants
           ('mid',        2.0,  1.05),   # EH EY AE
           ('wide',       8.0,  1.10),   # AA AY AW
           ('ee',        -3.0,  1.30),   # IY YY - stretched
           ('oo',         0.0,  0.65),   # UW WW SH - rounded
           ('oh',         5.0,  0.80),   # OW AO OR
           ('fv',        -7.0,  1.00),   # FF VV
           ('th',        -1.0,  1.00)]   # TH LL DH EL

REST, SHUT, SMALL, MID_V, WIDE, EE, OO, OH, FV, TH = range(10)

# allophone -> viseme, the whole AL2 set
VMAP = [REST]*5 + [
    OH,    WIDE,  MID_V, SMALL, SHUT,  SMALL, SMALL, SMALL, SMALL, OO,     #  5..14
    SMALL, SHUT,  SMALL, TH,    EE,    MID_V, SMALL, OO,    OH,    WIDE,   # 15..24
    EE,    MID_V, SMALL, SHUT,  TH,    OO,    OO,    WIDE,  SMALL, SMALL,  # 25..34
    FV,    SMALL, OO,    OO,    OO,    FV,    SMALL, SMALL, SMALL, SMALL,  # 35..44
    TH,    OO,    OO,    OO,    EE,    OO,    OO,    OO,    OH,    TH,     # 45..54
    SMALL, SMALL, SMALL, OH,    WIDE,  EE,    SMALL, TH,    SHUT]          # 55..63
assert len(VMAP) == 64, len(VMAP)

# durations from the AL2 data sheet, milliseconds; the pauses first
DUR = {0: 10, 1: 30, 2: 50, 3: 100, 4: 200}
for line in open('allophones.txt'):
    m = re.match(r'SP_(\w+)\s+equ\s+0x([0-9A-Fa-f]+).*?(\d[\dO]*)MS', line)
    if m:
        DUR[int(m.group(2), 16)] = int(m.group(3).replace('O', '0'))
assert len(DUR) == 64, len(DUR)

NAMES = {}
for line in open('allophones.txt'):
    m = re.match(r'SP_(\w+)\s+equ\s+0x([0-9A-Fa-f]+)', line)
    if m:
        NAMES[m.group(1)] = int(m.group(2), 16)
NAMES.update(PA1=0, PA2=1, PA3=2, PA4=3, PA5=4)

# ------------------------------------------------------------ the utterance
#
# "Hello, I am a vectorized computer head.  I live in the C P C."
#
# This is only spoken when NRL.BIN was not loaded and there are no rules to
# convert anything with.  It has to say what intro1 and intro2 in head.asm
# say: it used to still say "living in the CPC", the phrase the sentence was
# deliberately changed away from, so a machine that had not loaded the engine
# announced the old wording and there was no way to tell that was why.
WORDS = [
    ('Hello',      'HH1 EH LL OW'),
    ('I',          'AY'),
    ('am',         'AE MM'),
    ('a',          'AX'),
    ('vectorized', 'VV EH KK3 TT2 ER1 AY ZZ DD1'),
    ('computer',   'KK1 AX MM PP YY1 UW2 TT2 ER1'),
    ('head',       'HH1 EH DD1'),
    ('.',          'PA5 PA5 PA5'),
    ('I',          'AY'),
    ('live',       'LL IH VV'),
    ('in',         'IH NN1'),
    ('the',        'DH1 AX'),
    ('C',          'SS IY'),
    ('P',          'PP IY'),
    ('C',          'SS IY'),
]

# ------------------------------------------------------------------- output

shapes  = [[mouth_shape(o, w) for _, o, w in VISEMES],
           [eye_shape(k) for _, k in EYES]]

def box(states):
    """The screen rectangle a group's shapes ever touch, which is what has
    to be mirrored to the other half of the face after a redraw."""
    pts = [screen(x, y) for st in states for p in st for x, y in p]
    lo, hi = min(d for d, _ in pts), max(d for d, _ in pts)
    return (HEADX - hi) // 8, (HEADX - lo) // 8, min(y for _, y in pts), max(y for _, y in pts)

with open('headdata.inc', 'w') as f:
    f.write(';; generated by mkhead.py from P-C-S.BAS - do not edit\n')
    f.write(f';; head: {len(static)} chains, {sum(len(p)-1 for p in static)} segments, '
            f'{cost(static)} pixels per half\n')
    f.write(';; each entry: vertex count, then (dx from centre, scanline) pairs; 0 ends it\n\n')
    emit(f, 'head', static)

    for grp, (label, names, states) in enumerate((
            ('mouth', [v[0] for v in VISEMES], shapes[0]),
            ('eye',   [e[0] for e in EYES],    shapes[1]))):
        f.write(f';; the {label}, one table per shape, in the same format\n')
        f.write(f'{label}tab:\n')
        for nm in names:
            f.write(f'    defw {label}_{nm}\n')
        f.write('\n')
        for nm, st in zip(names, states):
            emit(f, f'{label}_{nm}', st)
        c0, c1, r0, r1 = box(states)
        f.write(f';; the box it lives in, for the mirror blit\n')
        f.write(f'{label.upper()}COL  equ {c0}\n')
        f.write(f'{label.upper()}COLW equ {c1 - c0 + 1}\n')
        f.write(f'{label.upper()}ROW  equ {r0}\n')
        f.write(f'{label.upper()}ROWS equ {r1 - r0 + 1}\n\n')

    f.write(';; allophone -> viseme\n')
    f.write('vismap:\n')
    for j in range(0, 64, 8):
        f.write('    defb ' + ','.join(str(v) for v in VMAP[j:j+8]) + '\n')
    f.write('\n;; allophone duration in 1/300 s, for when no synthesiser answers\n')
    f.write('durtab:\n')
    for j in range(0, 64, 8):
        f.write('    defb ' + ','.join(str(max(1, round(DUR[k] * 0.3))) for k in range(j, j+8)) + '\n')

    hp = [screen(x, y) for p in static for x, y in p]
    hlo, hhi = min(d for d, _ in hp), max(d for d, _ in hp)
    f.write(';; where the head sits, and how the mirror maps a column\n')
    f.write(f'HEADX     equ {HEADX}\n')
    f.write(f'MIRRORC   equ {MIRRORC}\n')
    f.write(f'HEADCOL   equ {(HEADX - hhi) // 8}\n')
    f.write(f'HEADCOLW  equ {(HEADX - hlo) // 8 - (HEADX - hhi) // 8 + 1}\n\n')
    f.write(';; allophone names, three characters each, for the listing\n')
    f.write('phnames:\n')
    names = {0:'PA1',1:'PA2',2:'PA3',3:'PA4',4:'PA5'}
    for line in open('allophones.txt'):
        m = re.match(r'SP_(\w+)\s+equ\s+0x([0-9A-Fa-f]+)', line)
        if m: names[int(m.group(2), 16)] = m.group(1)[:3]
    for j in range(0, 64, 4):
        f.write('    defb ' + ','.join('"%-3s"' % names[k] for k in range(j, j+4)) + '\n')
    f.write('\n')
    f.write('\n;; bit-reversed bytes, for mirroring the drawn half across the screen\n')
    f.write('    align 256\n')
    f.write('revtab:\n')
    for j in range(0, 256, 16):
        row = ','.join(str(int(f'{v:08b}'[::-1], 2)) for v in range(j, j + 16))
        f.write(f'    defb {row}\n')
    f.write('\n;; the utterance: allophones, #FF ends it\n')
    f.write('utter:\n')
    for word, phones in WORDS:
        codes = [NAMES[p] for p in phones.split()]
        f.write(f'    defb {",".join(str(c) for c in codes)},2   ; {word}\n')
    f.write('    defb #FF\n')

mx = max(max(abs(screen(*b)[0] - screen(*a)[0]), abs(screen(*b)[1] - screen(*a)[1]))
         for p in static + [q for st in shapes for sh in st for q in sh]
         for a, b in zip(p, p[1:]))
assert mx < 256, mx

# the vertex count the README quotes against Parke's ~400, printed here so
# the claim stays tied to the DATA rather than to a number someone typed
_verts = {(x, y) for p in polys for x, y in p}
print(f'head   {len(static)} chains, {cost(static)} pixels per half')
print(f'       {len(polys)} digitized polylines, {len(_verts)} distinct vertices '
      f'({len(_verts) * 2} mirrored)')
for label, states in (('mouth', shapes[0]), ('eye', shapes[1])):
    c0, c1, r0, r1 = box(states)
    px = max(cost(st) for st in states)
    print(f'{label:6s} {len(states)} shapes, {len(states[0])} chains, {px} pixels at most, '
          f'box cols {c0}..{c1} rows {r0}..{r1} ({(c1-c0+1)*(r1-r0+1)} bytes)')
# The mouth has to stay in the space the face leaves it.  Checked the only
# way that means anything: rasterise the lips and rasterise the lines
# around them, and see whether any pixel is claimed by both.  A shape that
# opens into the nostrils shows up here as a collision, not as something
# to notice in a screenshot three days later.
NOSE = [polys[n] for n in (11, 12, 13)] + [polys[14][:3]]
BELOW = [polys[n] for n in (44, 45)]

def pixels(chains):
    out = set()
    for p in chains:
        pts = [screen(x, y) for x, y in p]
        for a, b in zip(pts, pts[1:]):
            out.update(raster((HEADX - a[0], a[1]), (HEADX - b[0], b[1])))
    return out

nosepx, belowpx = pixels(NOSE), pixels(BELOW)
for (name, a, w), st in zip(VISEMES, shapes[0]):
    lipchains = [q for p, q in zip(anim[0], st) if is_lip(p[0]) and is_lip(p[-1])]
    lp = pixels(lipchains)
    hit_n, hit_b = lp & nosepx, lp & belowpx
    assert not hit_n, (name, 'runs into the nose at', sorted(hit_n)[:3])
    assert not hit_b, (name, 'runs into the chin at', sorted(hit_b)[:3])
    gap_n = min(y for _, y in nosepx) and min(
        py - ny for nx, ny in nosepx for px, py in lp if px == nx) if lp else 0
    print(f'  {name:6s} aperture {a:+5.1f} width {w:.2f}  '
          f'clearance to the nose {gap_n:2d} scanlines')

for label, states, (c0, c1, r0, r1) in (('mouth', shapes[0], box(shapes[0])),
                                        ('eye',   shapes[1], box(shapes[1]))):
    for st in states:
        for px, _ in coverage(st).items():
            assert c0 * 8 <= px[0] <= c1 * 8 + 7 and r0 <= px[1] <= r1, (label, px)
print(f'longest segment delta {mx}')
