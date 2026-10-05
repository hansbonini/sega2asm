"""The boot screens as the ROM draws them, frame by frame, to compare with
the Godot port's (iss/iss_boot_capture.gd):

    python3 tools/boot_capture.py <rom> <prefix> <start> <end>

runs the game from power-on (NTSC; PAL=1 in the environment for PAL) to
frame end, saving <prefix>_<frame>.png for every frame from start, and
prints the boot module's screen number ($1C), wait and flags whenever
they change. PRESS=frame:frames presses Start on pad 1 at that frame for
that many frames; VRAM_AT=n writes <prefix>.vram, .rram and .regs at frame
n. The pictures are whole frames: the raster effects and the title's
second palette do not show (see README).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from md_harness import MD  # noqa: E402

md = MD(open(sys.argv[1], 'rb').read(), pal=os.environ.get('PAL', '0') == '1')
prefix, start, end = sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
press = [int(x) for x in os.environ['PRESS'].split(':')] if os.environ.get('PRESS') else None


def rw(a):
    return int.from_bytes(md.ram(a, 2), 'big')


last = None
for f in range(end):
    if press and md.frame == press[0]:
        md.pads[0] = 0x80
    if press and md.frame == press[0] + press[1]:
        md.pads[0] = 0
    md.run(1)
    scr = rw(0x1C)
    st = int.from_bytes(md.ram(0x18, 4), 'big')
    key = (scr, st) + tuple(md.ram(a, 1)[0] for a in (0xF32, 0xF2B, 0xF2C, 0xF30, 0xF34, 0xF35))
    if key != last:
        print('frame', md.frame, 'screen', scr, 'wait %d' % (st >> 16),
              'f32 %02X f2b %02X f2c %02X f30 %02X f34 %02X f35 %02X' % key[2:], 'ctr', rw(0x16), flush=True)
        last = key
    if md.frame >= start:
        md.screenshot('%s_%04d.png' % (prefix, md.frame))
    if os.environ.get('VRAM_AT') and md.frame == int(os.environ['VRAM_AT']):
        open(prefix + '.vram', 'wb').write(bytes(md.vdp.vram))
        open(prefix + '.rram', 'wb').write(md.ram(0, 0x10000))
        open(prefix + '.regs', 'w').write(repr({'vsram': list(md.vdp.vsram), 'cram': list(md.vdp.cram),
                                               'reg': list(md.vdp.reg)}))
print('end frame', md.frame)
