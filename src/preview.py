"""Render the ten mouth shapes the way the CPC draws them, so the
animation can be looked at without going through the emulator.

    python3 preview.py [out.png]

Writes a contact sheet of the visemes, each one cropped to the mouth.
"""
import importlib.util, sys, io, contextlib
from PIL import Image, ImageDraw

spec = importlib.util.spec_from_file_location('mk', 'mkhead.py')
mk = importlib.util.module_from_spec(spec)
with contextlib.redirect_stdout(io.StringIO()):     # the generator reports
    spec.loader.exec_module(mk)                     # as it writes its tables

def frame(chains):
    """One whole face: the digitised half, and the same half mirrored."""
    img = Image.new('L', (640, 200), 0)
    d = ImageDraw.Draw(img)
    for p in chains:
        pts = [mk.screen(x, y) for x, y in p]
        for side in (0, 1):
            xs = [(319 - dx) if side == 0 else (320 + dx) for dx, _ in pts]
            d.line(list(zip(xs, [y for _, y in pts])), fill=255)
    return img

CROP = (236, 88, 404, 158)                          # the mouth and the chin
GAP  = 6
# a CPC pixel is twice as tall as it is wide, so y is scaled twice as much
W, H = (CROP[2] - CROP[0]) * 2, (CROP[3] - CROP[1]) * 4
sheet = Image.new('L', (5 * (W + GAP) + GAP, 2 * (H + 20) + GAP), 30)
draw  = ImageDraw.Draw(sheet)
for i, (name, ap, wide) in enumerate(mk.VISEMES):
    chains = mk.static + mk.mouth_shape(ap, wide) + mk.eye_shape(1.0)
    tile = frame(chains).crop(CROP).resize((W, H), Image.NEAREST)
    x = GAP + (i % 5) * (W + GAP)
    y = GAP + (i // 5) * (H + 20)
    sheet.paste(tile, (x, y))
    draw.text((x + 2, y + H + 4), f'{name}   aperture {ap:+.0f}   width {wide:.2f}', fill=200)
out = sys.argv[1] if len(sys.argv) > 1 else 'visemes.png'
sheet.save(out)
print(out, sheet.size)
