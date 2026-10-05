#!/usr/bin/env python3
"""A small Mega Drive for running ISS Deluxe's own code: the 68000 under the
Unicorn CPU emulator, a VDP (registers, VRAM / CRAM / VSRAM, 68000 DMA, fill
and copy, the status and HV counter), two 6-button pads, a Z80 whose bus is
always granted (its RAM is plain memory) and a silent YM2612 / PSG. VBlank
and HBlank interrupts are raised as the VDP registers enable them.

It is a tool for the port, not an emulator for playing: the screens the game
draws (front-end menus with their team pictures, the competition tables,
the shoot-out view ...) can be rendered to PNG at any frame, so that the
Godot port reproduces them from the game's own drawing.

    from md_harness import MD
    md = MD(open(rom, 'rb').read())
    md.run(300)                      # frames
    md.press(0, 'start'); md.run(2); md.release(0, 'start')
    md.screenshot('out.png')

Requirements: pip install unicorn pillow
"""
import ctypes
import struct

from PIL import Image
from unicorn import Uc, UC_ARCH_M68K, UC_MODE_BIG_ENDIAN, UC_PROT_ALL, UcError
from unicorn import m68k_const as m68k
from unicorn.m68k_const import UC_CPU_M68K_M68000, UC_M68K_REG_A7, UC_M68K_REG_PC, UC_M68K_REG_SR

BUTTONS = {'up': 0x1, 'down': 0x2, 'left': 0x4, 'right': 0x8, 'b': 0x10, 'c': 0x20, 'a': 0x40,
           'start': 0x80, 'z': 0x100, 'y': 0x200, 'x': 0x400, 'mode': 0x800}


# sound_play_music, sound_play_sfx, sound_update (issdeluxe_symbols.txt).
SOUND_ENTRIES = (0x1FD958, 0x1FD96C, 0x1FD98C, 0x1FD990)

# The registers a saved state keeps (a pickled Unicorn context does not
# restore in another process).
CPU_REGS = [getattr(m68k, 'UC_M68K_REG_D%d' % i) for i in range(8)] + \
    [getattr(m68k, 'UC_M68K_REG_A%d' % i) for i in range(8)] + [UC_M68K_REG_SR]


def md_color(w):
    """CRAM word -> (r, g, b) as the VDP's 3-bit levels."""
    lv = [0, 52, 87, 116, 144, 172, 206, 255]
    return (lv[(w >> 1) & 7], lv[(w >> 5) & 7], lv[(w >> 9) & 7])


class VDP:
    def __init__(self, md):
        self.md = md
        self.reg = [0] * 24
        self.vram = bytearray(0x10000)
        self.cram = [0] * 64
        self.vsram = [0] * 40
        self.pending = None
        self.code = 0
        self.addr = 0
        self.fill_pending = False
        self.vblank = False
        self.hv = 0
        self.line = 0
        self.hblank = 0

    # -- ports
    def read(self, offset, size):
        if size == 1:
            # A byte read: the even address holds the word's high byte (the V
            # counter at $C00008, the status flags' high byte at $C00004).
            w = self.read(offset & ~1, 2)
            return (w >> 8) & 0xFF if offset & 1 == 0 else w & 0xFF
        o = offset & 0x1F
        if o < 4:
            return self.data_read()
        if o < 8:
            self.pending = None
            # The HBlank flag alternates from read to read, so that loops
            # waiting for either edge move on.
            self.hblank ^= 4
            return 0x3400 | (0x8 if self.vblank else 0) | self.hblank | (0x1 if self.md.pal else 0)
        if o < 0x10:
            self.hv = (self.hv * 1103515245 + 12345) & 0xFFFF
            v = self.line if self.line < 0xEB else self.line - 6
            return ((v & 0xFF) << 8) | ((self.hv >> 8) & 0xFF)
        return 0

    def write(self, offset, size, value):
        o = offset & 0x1F
        if o < 4:
            if size == 4:
                # A longword is two words to the data port (the boot module
                # writes its palettes with move.l).
                self.data_write((value >> 16) & 0xFFFF)
                self.data_write(value & 0xFFFF)
                return
            if size == 1:
                value = value | (value << 8)
            self.data_write(value & 0xFFFF)
            return
        if o < 8:
            if size == 4:
                self.control((value >> 16) & 0xFFFF)
                self.control(value & 0xFFFF)
            else:
                self.control(value & 0xFFFF)
            return
        # PSG and the rest: ignored

    def control(self, w):
        if self.pending is None:
            if (w & 0xC000) == 0x8000:
                r = (w >> 8) & 0x1F
                if r < 24:
                    self.reg[r] = w & 0xFF
                return
            self.pending = w
            self.code = (self.code & 0x3C) | ((w >> 14) & 3)
            self.addr = (self.addr & 0xC000) | (w & 0x3FFF)
            return
        first = self.pending
        self.pending = None
        self.addr = (first & 0x3FFF) | ((w & 3) << 14)
        self.code = ((first >> 14) & 3) | ((w >> 2) & 0x3C)
        if self.code & 0x20 and self.reg[1] & 0x10:
            mode = self.reg[23] >> 6
            if mode < 2:
                self.dma_68k()
            elif mode == 2:
                self.fill_pending = True
            else:
                self.dma_copy()

    def length(self):
        n = self.reg[19] | (self.reg[20] << 8)
        return n if n else 0x10000

    def dma_68k(self):
        src = ((self.reg[23] & 0x7F) << 17) | (self.reg[22] << 9) | (self.reg[21] << 1)
        n = self.length()
        data = self.md.read_mem(src, n * 2)
        for i in range(n):
            self.store(struct.unpack_from('>H', data, 2 * i)[0])
        self.code &= 0x1F

    def dma_copy(self):
        src = self.reg[21] | (self.reg[22] << 8)
        for i in range(self.length()):
            self.vram[self.addr & 0xFFFF] = self.vram[(src + i) & 0xFFFF]
            self.addr = (self.addr + self.reg[15]) & 0xFFFF
        self.code &= 0x1F

    def store(self, w):
        t = self.code & 0xF
        if t == 1:
            a = self.addr & 0xFFFE
            self.vram[a] = w >> 8
            self.vram[a + 1] = w & 0xFF
        elif t == 3:
            self.cram[(self.addr >> 1) & 63] = w & 0xEEE
        elif t == 5:
            self.vsram[(self.addr >> 1) % 40] = w & 0x7FF
        self.addr = (self.addr + self.reg[15]) & 0xFFFF

    def data_write(self, w):
        self.pending = None
        if self.fill_pending:
            self.fill_pending = False
            self.store(w)
            hi = w >> 8
            for i in range(self.length() - 1):
                self.vram[self.addr & 0xFFFF] = hi
                self.addr = (self.addr + self.reg[15]) & 0xFFFF
            self.code &= 0x1F
            return
        self.store(w)

    def data_read(self):
        self.pending = None
        t = self.code & 0xF
        a = self.addr
        self.addr = (self.addr + self.reg[15]) & 0xFFFF
        if t == 0:
            return (self.vram[a & 0xFFFE] << 8) | self.vram[(a & 0xFFFE) + 1]
        if t == 8:
            return self.cram[(a >> 1) & 63]
        if t == 4:
            return self.vsram[(a >> 1) % 40]
        return 0

    # -- rendering
    def width(self):
        return 320 if self.reg[12] & 0x81 else 256

    def colour(self, i):
        return md_color(self.cram[i & 63])

    def tile_pixel(self, tile, x, y):
        b = self.vram[(tile * 32 + y * 4 + (x >> 1)) & 0xFFFF]
        return (b >> 4) if (x & 1) == 0 else (b & 15)

    def render(self):
        """The visible picture as an RGB image (planes, window and sprites)."""
        w, h = self.width(), 224 if self.reg[1] & 0x08 else 224
        cells_w = [32, 64, 32, 128][self.reg[16] & 3]
        cells_h = [32, 64, 32, 128][(self.reg[16] >> 4) & 3]
        base_a = (self.reg[2] & 0x38) << 10
        base_b = (self.reg[4] & 7) << 13
        base_w = (self.reg[3] & (0x3C if w == 320 else 0x3E)) << 10
        base_hs = (self.reg[13] & 0x3F) << 10
        sat = (self.reg[5] & (0x7E if w == 320 else 0x7F)) << 9
        hmode = self.reg[11] & 3
        vmode = (self.reg[11] >> 2) & 1
        win_h = self.reg[17]
        win_v = self.reg[18]
        back = self.colour(self.reg[7] & 63)
        # layers: index -> (pixel colour index or 0, priority)
        out = [[back] * w for _ in range(h)]
        prio_layers = []

        def plane_pixel(base, x, y, cw, ch):
            cx, cy = (x >> 3) % cw, (y >> 3) % ch
            e = struct.unpack_from('>H', self.vram, (base + 2 * (cy * cw + cx)) & 0xFFFF)[0]
            px, py = x & 7, y & 7
            if e & 0x800:
                px = 7 - px
            if e & 0x1000:
                py = 7 - py
            v = self.tile_pixel(e & 0x7FF, px, py)
            return (((e >> 13) & 3) * 16 + v if v else 0), bool(e & 0x8000)

        def hscroll(line, plane):
            if hmode == 0:
                o = base_hs
            elif hmode == 2:
                o = base_hs + (line & ~7) * 4
            else:
                o = base_hs + line * 4
            return struct.unpack_from('>H', self.vram, (o + 2 * plane) & 0xFFFF)[0] & 0x3FF

        def vscroll(x, plane):
            col = 0 if vmode == 0 else (x >> 4)
            return self.vsram[(col * 2 + plane) % 40] & 0x3FF

        def in_window(x, y):
            wx = (win_h & 0x1F) * 16
            wy = (win_v & 0x1F) * 8
            hin = x >= wx if win_h & 0x80 else x < wx
            vin = y >= wy if win_v & 0x80 else y < wy
            return hin or vin

        planes = []
        for y in range(h):
            row_b, row_a = [], []
            hsb, hsa = hscroll(y, 1), hscroll(y, 0)
            for x in range(w):
                yb = (y + vscroll(x, 1)) & 0x3FF
                row_b.append(plane_pixel(base_b, (x - hsb) & 0x3FF, yb, cells_w, cells_h))
                if (win_h or win_v) and in_window(x, y):
                    row_a.append(plane_pixel(base_w, x, y, 64 if w == 320 else 32, 32))
                else:
                    ya = (y + vscroll(x, 0)) & 0x3FF
                    row_a.append(plane_pixel(base_a, (x - hsa) & 0x3FF, ya, cells_w, cells_h))
            planes.append((row_b, row_a))
        # sprites (link list from sprite 0)
        spr = [[(0, False)] * w for _ in range(h)]
        link, seen = 0, 0
        while seen < 80:
            o = sat + link * 8
            sy = (struct.unpack_from('>H', self.vram, o)[0] & 0x3FF) - 128
            size = self.vram[o + 2]
            nxt = self.vram[o + 3] & 0x7F
            e = struct.unpack_from('>H', self.vram, o + 4)[0]
            sx = (struct.unpack_from('>H', self.vram, o + 6)[0] & 0x1FF) - 128
            sw, sh = ((size >> 2) & 3) + 1, (size & 3) + 1
            for ty in range(sh * 8):
                yy = sy + ty
                if not 0 <= yy < h:
                    continue
                for tx in range(sw * 8):
                    xx = sx + tx
                    if not 0 <= xx < w or spr[yy][xx][0]:
                        continue
                    px = sw * 8 - 1 - tx if e & 0x800 else tx
                    py = sh * 8 - 1 - ty if e & 0x1000 else ty
                    tile = (e & 0x7FF) + (px >> 3) * sh + (py >> 3)
                    v = self.tile_pixel(tile, px & 7, py & 7)
                    if v:
                        spr[yy][xx] = (((e >> 13) & 3) * 16 + v, bool(e & 0x8000))
            seen += 1
            if nxt == 0:
                break
            link = nxt
        img = Image.new('RGB', (w, h))
        px = img.load()
        shi = bool(self.reg[12] & 0x08)
        for y in range(h):
            row_b, row_a = planes[y]
            for x in range(w):
                b, a, sp = row_b[x], row_a[x], spr[y][x]
                if not shi:
                    c = 0
                    for layer, pri in ((b, False), (a, False), (sp, False), (b, True), (a, True), (sp, True)):
                        if layer[0] and layer[1] == pri:
                            c = layer[0]
                    px[x, y] = self.colour(c) if c else back
                    continue
                # Shadow / highlight: the planes are shadowed unless one of
                # them has priority here; sprite colours 62 and 63 brighten or
                # darken what is under them instead of being drawn.
                c = 0
                for layer, pri in ((b, False), (a, False), (b, True), (a, True)):
                    if layer[0] and layer[1] == pri:
                        c = layer[0]
                shade = 1 if (b[1] or a[1]) else 0
                if sp[0] in (62, 63):
                    if sp[0] == 62:
                        shade = min(2, shade + 1)
                    else:
                        shade = 0
                elif sp[0] and (sp[1] or not ((b[0] and b[1]) or (a[0] and a[1]))):
                    c = sp[0]
                    if sp[1] or (c & 15) == 14:
                        shade = 1
                rgb = self.colour(c) if c else back
                if shade == 0:
                    rgb = tuple(v // 2 for v in rgb)
                elif shade == 2:
                    rgb = tuple(min(255, v // 2 + 128) for v in rgb)
                px[x, y] = rgb
        return img


# Where the status-register stub runs (unmapped on the Mega Drive).
STUB = 0x900000


class MD:
    def __init__(self, rom, pal=True):
        self.pal = pal
        self.vdp = VDP(self)
        self.pads = [0, 0]
        self.six_button = False
        self.th = [0x40, 0x40]
        self.th_count = [0, 0]
        mu = Uc(UC_ARCH_M68K, UC_MODE_BIG_ENDIAN)
        mu.ctl_set_cpu_model(UC_CPU_M68K_M68000)
        mu.mem_map(0, 0x400000)
        mu.mem_write(0, rom[:0x400000])
        mu.mem_map(0xA00000, 0x4000)
        mu.mmio_map(0xA04000, 0x1000, lambda *a: 0, None, lambda *a: None, None)
        mu.mem_map(0xA05000, 0xB000)
        # A page for a stub that reads the status register (move.w
        # sr,(STUB + $100).l): reading unicorn's SR register returns stale
        # condition codes and resets the live ones to them, so a branch on
        # flags set before an interrupt (or a state save) could go wrong.
        mu.mem_map(STUB, 0x1000)
        mu.mem_write(STUB, bytes.fromhex('40f9') + struct.pack('>I', STUB + 0x100))
        mu.mmio_map(0xA10000, 0x10000, self._io_read, None, self._io_write, None)
        mu.mmio_map(0xC00000, 0x10000, lambda uc, o, s, d: self.vdp.read(o, s), None,
                    lambda uc, o, s, v, d: self.vdp.write(o, s, v), None)
        # Work RAM, also at $FFFF0000 (the 68000's 24-bit bus: -(a6) from 0
        # and absolute short addresses land there).
        self._ram = ctypes.create_string_buffer(0x10000)
        mu.mem_map_ptr(0xFF0000, 0x10000, UC_PROT_ALL, self._ram)
        mu.mem_map_ptr(0xFFFF0000, 0x10000, UC_PROT_ALL, self._ram)
        self.mu = mu
        self.frame = 0
        self._dac_acc = 0.0
        self._dac_pos = 0
        self._vint = False
        self._hint = False
        ssp = struct.unpack('>I', rom[0:4])[0]
        self.pc = struct.unpack('>I', rom[4:8])[0]
        mu.reg_write(UC_M68K_REG_A7, ssp & 0xFFFFFFFF)
        mu.reg_write(UC_M68K_REG_SR, 0x2700)

    def read_mem(self, addr, n):
        addr &= 0xFFFFFF
        if addr >= 0xE00000:
            addr = 0xFF0000 | (addr & 0xFFFF)
        return bytes(self.mu.mem_read(addr, n))

    def ram(self, off, n):
        return bytes(self.mu.mem_read(0xFF0000 + off, n))

    def ram_w(self, off):
        return struct.unpack('>H', self.ram(off, 2))[0]

    def poke_w(self, off, v):
        self.mu.mem_write(0xFF0000 + off, struct.pack('>H', v & 0xFFFF))

    # -- I/O: version, pads, Z80 bus
    def _io_read(self, uc, offset, size, data):
        o = offset & 0xFFFF
        if o in (0, 1):
            return 0xE0 if self.pal else 0xA0  # overseas, PAL, no expansion
        if o in (2, 3, 4, 5):
            return self._pad_read((o - 2) >> 1)
        if 0x1100 <= o <= 0x1101:
            return 0  # Z80 bus granted
        return 0

    def _io_write(self, uc, offset, size, value, data):
        o = offset & 0xFFFF
        if o in (2, 3, 4, 5):
            p = (o - 2) >> 1
            th = value & 0x40
            if self.th[p] and not th:
                self.th_count[p] += 1
            self.th[p] = th

    def _pad_read(self, p):
        """6-button protocol: after the third TH low the low nibble reads 0
        (identification) and the next TH high returns Mode X Y Z."""
        b = ~self.pads[p] & 0xFFF
        n = self.th_count[p] if self.six_button else 0
        if self.th[p]:
            if n >= 3:
                return 0x40 | (b & 0x30) | (((b >> 11) & 1) << 3) | (((b >> 10) & 1) << 2) | \
                    (((b >> 9) & 1) << 1) | ((b >> 8) & 1)
            return 0x40 | (b & 0x3F)
        if n == 3:
            return (b & 0xC0) >> 2
        if n >= 4:
            return ((b & 0xC0) >> 2) | 0x0F
        return ((b & 0xC0) >> 2) | (b & 0x03)

    # -- running
    def sr(self):
        """The status register with its live condition codes."""
        self.mu.emu_start(STUB, STUB + 6)
        return struct.unpack('>H', bytes(self.mu.mem_read(STUB + 0x100, 2)))[0]

    def interrupt(self, level, vector):
        sr = self.sr()
        if ((sr >> 8) & 7) >= level:
            return False
        sp = self.mu.reg_read(UC_M68K_REG_A7)
        sp = (sp - 4) & 0xFFFFFFFF
        self.mu.mem_write(sp, struct.pack('>I', self.pc))
        sp = (sp - 2) & 0xFFFFFFFF
        self.mu.mem_write(sp, struct.pack('>H', sr))
        self.mu.reg_write(UC_M68K_REG_A7, sp)
        self.mu.reg_write(UC_M68K_REG_SR, (sr & ~0x0700 & ~0x8000) | 0x2000 | (level << 8))
        self.pc = struct.unpack('>I', self.read_mem(vector, 4))[0]
        return True

    def _exec(self, count):
        """Run about count instructions. Unicorn's 68000 cannot return from
        an exception, so an RTE that stops it is carried out here."""
        while True:
            try:
                self.mu.emu_start(self.pc, 0xFFFFFFFF, 0, count)
                self.pc = self.mu.reg_read(UC_M68K_REG_PC)
                return
            except UcError as e:
                pc = self.mu.reg_read(UC_M68K_REG_PC)
                if self.read_mem(pc, 2) != b'\x4e\x73':
                    raise RuntimeError('68000 stopped at %06X: %s' % (pc, e))
                sp = self.mu.reg_read(UC_M68K_REG_A7)
                sr, ret = struct.unpack('>HI', self.read_mem(sp, 6))
                self.mu.reg_write(UC_M68K_REG_A7, (sp + 6) & 0xFFFFFFFF)
                self.mu.reg_write(UC_M68K_REG_SR, sr)
                self.pc = ret
                count = max(1, count // 2)

    def _z80_tick(self):
        """The Z80 program plays the PCM ring buffer at 9237 Hz: advance its
        read position in Z80 RAM ($0500) as render_sound.py does, so that the
        68000 mixes only what was played."""
        self._dac_acc += (3546894.0 / 384) / (50 if self.pal else 60)
        k = int(self._dac_acc)
        self._dac_acc -= k
        self._dac_pos = (self._dac_pos + k) % 400
        ix = 0x0504 + 2 * self._dac_pos
        self.mu.mem_write(0xA00500, struct.pack('<HH', ix, ix))

    def run(self, frames=1, per_line=64):
        """Run whole frames line by line: the VBlank interrupt at line 224
        (when VDP register 1 enables it), the HBlank interrupt every
        register 10 + 1 lines (register 0), kept pending while masked."""
        lines = 313 if self.pal else 262
        for _ in range(frames):
            self._z80_tick()
            self.th_count = [0, 0]
            hcount = self.vdp.reg[10]
            for line in range(lines):
                v = self.vdp
                v.line = line
                v.vblank = line >= 224
                if line == 224:
                    self._vint = True
                if line < 224:
                    hcount -= 1
                    if hcount < 0:
                        hcount = v.reg[10]
                        self._hint = True
                else:
                    hcount = v.reg[10]
                if self._vint and v.reg[1] & 0x20 and self.interrupt(6, 0x78):
                    self._vint = False
                elif self._hint and v.reg[0] & 0x10 and self.interrupt(4, 0x70):
                    self._hint = False
                self._exec(per_line)
            self._vint = False
            self.frame += 1

    # -- machine state
    def save_state(self):
        """Everything needed to come back to this moment (RAM, Z80 RAM, VDP,
        CPU registers)."""
        return dict(ram=self.ram(0, 0x10000), z80=bytes(self.mu.mem_read(0xA00000, 0x4000)),
                    regs=[self.mu.reg_read(r) for r in CPU_REGS[:-1]] + [self.sr()], pc=self.pc, frame=self.frame,
                    vdp=dict(reg=list(self.vdp.reg), vram=bytes(self.vdp.vram), cram=list(self.vdp.cram),
                             vsram=list(self.vdp.vsram), code=self.vdp.code, addr=self.vdp.addr),
                    dac=(self._dac_acc, self._dac_pos), pads=list(self.pads))

    def load_state(self, st):
        self.mu.mem_write(0xFF0000, st['ram'])
        self.mu.mem_write(0xA00000, st['z80'])
        for r, v in zip(CPU_REGS, st['regs']):
            self.mu.reg_write(r, v)
        self.pc = st['pc']
        self.frame = st['frame']
        v = st['vdp']
        self.vdp.reg = list(v['reg'])
        self.vdp.vram = bytearray(v['vram'])
        self.vdp.cram = list(v['cram'])
        self.vdp.vsram = list(v['vsram'])
        self.vdp.code, self.vdp.addr, self.vdp.pending = v['code'], v['addr'], None
        self._dac_acc, self._dac_pos = st['dac']
        self.pads = list(st['pads'])
        self._vint = self._hint = False

    def mute(self):
        """Stub out the sound driver's calls (play music, play effect, the
        per-frame tick) from now on: the pictures do not need them, and the
        music driver runs into data in this machine after a while in the
        menus. (The title screen needs the driver, so mute after it.)"""
        for a in SOUND_ENTRIES:
            self.mu.mem_write(a, b'\x4e\x75')  # rts

    def boot_to_menu(self, max_taps=40):
        """From power on to the main menu (state_menu, screen 0): wait for
        the title, then press Start until the menu runs."""
        self.run(1300)
        for _ in range(max_taps):
            self.tap(0, 'start', hold=3, after=40)
            if self.ram(0, 4) == bytes.fromhex('0001ff6e'):
                self.mute()
                self.run(60)
                return True
        return False

    def goto_screen(self, n, menu_state, frames=90, setup=None):
        """Show front-end screen n: from the main menu snapshot, confirm the
        highlighted item and, while the fade runs, change g_next_screen
        ($FF175E). setup(md) can change RAM first (teams, mode ...)."""
        self.load_state(menu_state)
        if setup:
            setup(self)
        self.press(0, 'c')
        self.run(3)
        self.release(0)
        self.poke_w(0x175E, n)
        self.run(frames)

    def press(self, pad, *names):
        for n in names:
            self.pads[pad] |= BUTTONS[n]

    def release(self, pad, *names):
        if not names:
            self.pads[pad] = 0
        for n in names:
            self.pads[pad] &= ~BUTTONS[n]

    def tap(self, pad, name, hold=2, after=12):
        self.press(pad, name)
        self.run(hold)
        self.release(pad, name)
        self.run(after)

    def screenshot(self, path=None):
        img = self.vdp.render()
        if path:
            img.save(path)
        return img
