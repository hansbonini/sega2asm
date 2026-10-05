#!/usr/bin/env python3
"""Render ISS Deluxe's music and sound effects by running the game's own
68000 sound driver.

The driver (sound_init / sound_play_music / sound_play_sfx / sound_update at
$1FD954) runs under the Unicorn CPU emulator exactly as the VBlank handler
calls it, 50 times a second (PAL). Every frame the script records what the
driver hands to the Z80: the YM2612 part 1 / part 2 and PSG write queues
(z80_ram_write) and the PCM it mixes into the Z80's DAC ring buffer
(pcm_copy_to_z80, played at 9237 Hz). The result is written as a VGM file
and rendered with libvgm's vgm2wav, then saved as Ogg Vorbis.

Songs are rendered up to the end of their first loop; the loop start comes
from the song's order list ($FE entry) and is written to rendered.json so
the game can loop them seamlessly.

Requirements: pip install unicorn soundfile numpy, and vgm2wav from
https://github.com/ValleyBell/libvgm (cmake -DBUILD_VGM2WAV=ON).

    render_sound.py --rom "International Superstar Soccer Deluxe (Europe).md" \\
        --out out/godot/assets/iss/sound/rendered --vgm2wav /path/to/vgm2wav
"""
import argparse
import json
import os
import struct
import subprocess
import tempfile

import numpy as np
import soundfile as sf
from unicorn import Uc, UC_ARCH_M68K, UC_MODE_BIG_ENDIAN, UC_HOOK_CODE, UcError
from unicorn.m68k_const import (UC_CPU_M68K_M68000, UC_M68K_REG_A0, UC_M68K_REG_A1, UC_M68K_REG_A7,
                                UC_M68K_REG_D0, UC_M68K_REG_D1, UC_M68K_REG_D2, UC_M68K_REG_D3,
                                UC_M68K_REG_PC)

SOUND_INIT = 0x1FD954
SOUND_PLAY_MUSIC = 0x1FD958
SOUND_PLAY_SFX = 0x1FD96C
SOUND_UPDATE = 0x1FD98C
Z80_RAM_WRITE = 0x1FDB66      # a0 source, a1 Z80 offset, d0 count - 1
PCM_COPY_TO_Z80 = 0x1FDDCE    # a0 mixed bytes, d0 count
ORDER_JUMP = 0x1FE29E         # song_order_update, $FE entry at a0
ORDER_ENTRY = 0x1FE2B8        # song_order_update, pattern entry at a0
G_SOUND_RAM = 0xFF0008
SOUND_RAM = 0xFF31A8
STOP = 0x3FFFF0
STACK = 0xFFFE00

FRAME_HZ = 50                 # the European release runs at 50 Hz
DAC_HZ = 3546894.0 / 384      # PAL Z80 clock / cycles per DAC byte
YM_CLOCK = 7600489
PSG_CLOCK = 3546893
RING = 400                    # PCM ring buffer entries in Z80 RAM
NUM_SONGS = 26
NUM_SFX = 126
SILENT_SONG = 25
REGS = {"d0": UC_M68K_REG_D0, "d1": UC_M68K_REG_D1, "d2": UC_M68K_REG_D2, "d3": UC_M68K_REG_D3}


class Driver:
    """The 68000 side of the machine the sound driver needs: ROM, work RAM,
    Z80 RAM, the YM2612 / PSG ports (writes logged) and a Z80 that plays the
    DAC ring buffer at the right rate."""

    def __init__(self, rom):
        mu = Uc(UC_ARCH_M68K, UC_MODE_BIG_ENDIAN)
        mu.ctl_set_cpu_model(UC_CPU_M68K_M68000)
        mu.mem_map(0, 0x400000)
        mu.mem_write(0, rom)
        mu.mem_map(0xA00000, 0x4000)                       # Z80 RAM
        mu.mmio_map(0xA04000, 0x1000, self._ym_read, None, self._ym_write, None)
        mu.mem_map(0xA05000, 0xB000)
        mu.mmio_map(0xA10000, 0x10000, lambda *a: 0, None, lambda *a: None, None)  # bus always granted
        mu.mmio_map(0xC00000, 0x1000, self._vdp_read, None, self._vdp_write, None)
        mu.mem_map(0xFF0000, 0x10000)
        for a in (Z80_RAM_WRITE, PCM_COPY_TO_Z80, ORDER_JUMP, ORDER_ENTRY):
            mu.hook_add(UC_HOOK_CODE, self._hook, begin=a, end=a)
        self.mu = mu
        self.reset()

    def reset(self):
        """Clear RAM and the log, for the next song or effect (one Unicorn
        instance is reused: creating many is not reliable)."""
        self.mu.mem_write(0xFF0000, bytes(0x10000))
        self.mu.mem_write(0xA00000, bytes(0x4000))
        self.mu.mem_write(G_SOUND_RAM, struct.pack(">I", SOUND_RAM))
        self.ym_addr = [0, 0]
        self.ym, self.psg, self.dac = [], [], []
        self.pos = 0
        self.acc = 0.0
        self.frame = 0
        self.entry_first = {}
        self.loop = None

    # -- hardware ------------------------------------------------------
    def _ym_read(self, uc, offset, size, data):
        return 0                                            # never busy

    def _ym_write(self, uc, offset, size, value, data):
        port = (offset >> 1) & 1                            # direct writes (init, silence)
        if offset & 1 == 0:
            self.ym_addr[port] = value & 0xFF
        else:
            self.ym.append((port, self.ym_addr[port], value & 0xFF))

    def _vdp_read(self, uc, offset, size, data):
        return 1 if offset in (4, 5) else 0                 # status: PAL

    def _vdp_write(self, uc, offset, size, value, data):
        if offset == 0x11:
            self.psg.append(value & 0xFF)

    def _hook(self, uc, address, size, data):
        rd = uc.reg_read
        a0, a1, d0 = rd(UC_M68K_REG_A0), rd(UC_M68K_REG_A1), rd(UC_M68K_REG_D0)
        if address == Z80_RAM_WRITE:
            n = (d0 & 0xFFFF) + 1
            buf = uc.mem_read(a0, n)
            dst = a1 & 0xFFFF
            if dst in (0x200, 0x300):                       # (register, value) pairs, 0-terminated
                port = 0 if dst == 0x200 else 1
                for i in range(0, n - 1, 2):
                    if buf[i] == 0:
                        break
                    self.ym.append((port, buf[i], buf[i + 1]))
            elif dst == 0x400:                              # PSG bytes, 0-terminated
                for b in buf:
                    if b == 0:
                        break
                    self.psg.append(b)
        elif address == PCM_COPY_TO_Z80:
            # Keep the mixed bytes (the Z80 adds $80) and skip the movep copy.
            self.dac.extend((b + 0x80) & 0xFF for b in uc.mem_read(a0, d0 & 0xFFFF))
            sp = rd(UC_M68K_REG_A7)
            uc.reg_write(UC_M68K_REG_A7, sp + 4)
            uc.reg_write(UC_M68K_REG_PC, struct.unpack(">I", uc.mem_read(sp, 4))[0])
        elif address == ORDER_ENTRY:
            self.entry_first.setdefault(a0, self.frame)
        elif address == ORDER_JUMP and self.loop is None:
            base = struct.unpack(">I", uc.mem_read(SOUND_RAM + 0xC4E, 4))[0]
            target = base + struct.unpack(">H", uc.mem_read(a0 + 4, 2))[0]
            if target in self.entry_first:
                self.loop = (self.entry_first[target], self.frame)

    # -- driver calls ----------------------------------------------------
    def call(self, addr, **regs):
        sp = STACK - 4
        self.mu.mem_write(sp, struct.pack(">I", STOP))
        self.mu.reg_write(UC_M68K_REG_A7, sp)
        for k, v in regs.items():
            self.mu.reg_write(REGS[k], v & 0xFFFFFFFF)
        self.mu.emu_start(addr, STOP, count=5_000_000)

    def init(self):
        self.call(SOUND_INIT)
        # Plus the Z80 program's own set-up: DAC on, FM6 to both speakers.
        self.init_ym = self.ym + [(0, 0x2B, 0x80), (1, 0xB6, 0xC0)]
        self.init_psg = self.psg
        self.ym, self.psg, self.dac = [], [], []

    def step(self):
        """One video frame: the Z80 plays DAC_HZ / FRAME_HZ bytes of the ring,
        then the VBlank handler calls sound_update."""
        self.acc += DAC_HZ / FRAME_HZ
        k = int(self.acc)
        self.acc -= k
        self.pos = (self.pos + k) % RING
        ix = 0x0504 + 2 * self.pos
        self.mu.mem_write(0xA00500, struct.pack("<HH", ix, ix))
        self.ym, self.psg, self.dac = [], [], []
        self.call(SOUND_UPDATE, d0=0)
        self.frame += 1
        return self.ym, self.psg, self.dac

    def ram(self, off, n):
        return bytes(self.mu.mem_read(SOUND_RAM + off, n))

    def busy(self):
        """Any channel script still running, or a PCM voice playing."""
        if any(self.ram(0, 44)):
            return True
        v = self.ram(0x6C0, 0x20)
        return any(struct.unpack(">H", v[o + 0xC:o + 0xE])[0] != 1 or
                   struct.unpack(">H", v[o + 4:o + 6])[0] > 1 for o in (0, 0x10))


def write_vgm(path, init_ym, init_psg, frames):
    per_frame = 44100 // FRAME_HZ
    body = bytearray()

    def wait(n):
        while n > 0:
            k = min(n, 0xFFFF)
            if k == 882:
                body.append(0x63)
            elif k <= 16:
                body.append(0x70 + k - 1)
            else:
                body.extend((0x61, k & 0xFF, k >> 8))
            n -= k

    for p, r, v in init_ym:
        body.extend((0x52 + p, r, v))
    for b in init_psg:
        body.extend((0x50, b))
    for yms, psgs, dac in frames:
        for p, r, v in yms:
            body.extend((0x52 + p, r, v))
        for b in psgs:
            body.extend((0x50, b))
        if not dac:
            wait(per_frame)
            continue
        done = 0
        for k, v in enumerate(dac):
            body.extend((0x52, 0x2A, v))
            t = (k + 1) * per_frame // len(dac)
            wait(t - done)
            done = t
    body.append(0x66)
    hdr = bytearray(0x40)
    hdr[0:4] = b"Vgm "
    struct.pack_into("<I", hdr, 0x08, 0x150)
    struct.pack_into("<I", hdr, 0x0C, PSG_CLOCK)
    struct.pack_into("<I", hdr, 0x18, len(frames) * per_frame)
    struct.pack_into("<I", hdr, 0x24, FRAME_HZ)
    struct.pack_into("<H", hdr, 0x28, 0x0009)
    hdr[0x2A] = 16
    struct.pack_into("<I", hdr, 0x2C, YM_CLOCK)
    struct.pack_into("<I", hdr, 0x34, 0x40 - 0x34)
    data = hdr + body
    struct.pack_into("<I", data, 0x04, len(data) - 4)
    with open(path, "wb") as f:
        f.write(data)


def render(vgm, ogg, vgm2wav, trim):
    """VGM -> WAV (vgm2wav) -> Ogg Vorbis; returns the length in seconds or
    None when silent."""
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "out.wav")
        subprocess.run([vgm2wav, "--fade", "0", vgm, wav], check=True, capture_output=True)
        a, rate = sf.read(wav)
    level = np.abs(a).max(axis=1)
    loud = np.nonzero(level > 1e-3)[0]
    if len(loud) == 0:
        return None
    if trim:
        a = a[:min(len(a), loud[-1] + rate // 20)]
    # Written in blocks: libsndfile's Vorbis encoder crashes on one large write.
    with sf.SoundFile(ogg, "w", rate, a.shape[1], format="OGG", subtype="VORBIS") as f:
        for i in range(0, len(a), 16384):
            f.write(a[i:i + 16384])
    return len(a) / rate


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--rom", required=True)
    ap.add_argument("--out", required=True, help="output folder (e.g. out/godot/assets/iss/sound/rendered)")
    ap.add_argument("--vgm2wav", required=True)
    ap.add_argument("--res", default="res://assets/iss/sound/rendered/", help="Godot path of --out")
    ap.add_argument("--max-seconds", type=int, default=120, help="cap for songs that neither loop nor end")
    args = ap.parse_args()
    rom = open(args.rom, "rb").read()
    os.makedirs(os.path.join(args.out, "vgm"), exist_ok=True)
    cap = args.max_seconds * FRAME_HZ
    songs, effects = [], []
    d = Driver(rom)

    for song in range(NUM_SONGS):
        d.reset()
        d.init()
        d.call(SOUND_PLAY_MUSIC, d0=song, d1=0, d2=0, d3=4)
        frames, ended = [], False
        while len(frames) < cap:
            frames.append(d.step())
            if d.loop:
                frames.pop()                        # that frame already restarts the loop
                break
            if d.ram(0x917, 1) == b"\x02":          # $FF: the song ended
                ended = True
                frames += [d.step() for _ in range(2 * FRAME_HZ)]
                break
        vgm = os.path.join(args.out, "vgm", "song_%02d.vgm" % song)
        write_vgm(vgm, d.init_ym, d.init_psg, frames)
        ogg = os.path.join(args.out, "song_%02d.ogg" % song)
        length = render(vgm, ogg, args.vgm2wav, trim=ended)
        entry = {"id": song, "vgm": "vgm/song_%02d.vgm" % song}
        if length is None:
            entry["silent"] = True
        else:
            entry.update(ogg=args.res + "song_%02d.ogg" % song, seconds=round(length, 3))
            if d.loop:
                entry["loop_offset"] = round(d.loop[0] / FRAME_HZ, 3)
            elif not ended:
                entry["loop_offset"] = 0.0                  # held to the cap: loop all of it
        songs.append(entry)
        print("song %2d: %s" % (song, entry))

    for fx in range(NUM_SFX):
        d.reset()
        d.init()
        # A song always runs in the game (song 25 is the silent one the menus
        # use); starting it also points the driver at the effect table.
        d.call(SOUND_PLAY_MUSIC, d0=SILENT_SONG, d1=0, d2=0, d3=4)
        frames, tail = [], None
        try:
            d.call(SOUND_PLAY_SFX, d0=fx, d1=63)
            while len(frames) < 15 * FRAME_HZ:
                frames.append(d.step())
                if tail is None and len(frames) > 1 and not d.busy():
                    tail = len(frames) + 2 * FRAME_HZ      # release tails of FM notes
                if tail is not None and len(frames) >= tail:
                    break
        except UcError:
            # Not a valid script: the driver would run off into data.
            effects.append({"id": fx, "invalid": True})
            print("sfx %02X: invalid" % fx)
            continue
        vgm = os.path.join(args.out, "vgm", "sfx_%02X.vgm" % fx)
        write_vgm(vgm, d.init_ym, d.init_psg, frames)
        ogg = os.path.join(args.out, "sfx_%02X.ogg" % fx)
        length = render(vgm, ogg, args.vgm2wav, trim=True)
        entry = {"id": fx, "vgm": "vgm/sfx_%02X.vgm" % fx}
        if length is None:
            entry["silent"] = True
        else:
            entry.update(ogg=args.res + "sfx_%02X.ogg" % fx, seconds=round(length, 3))
            if tail is None:
                entry["held"] = True                       # still playing after 15 s (loops)
        effects.append(entry)
        print("sfx %02X: %s" % (fx, entry))

    with open(os.path.join(args.out, "rendered.json"), "w") as f:
        json.dump({"description": "Songs and effects rendered by running the game's 68000 sound driver "
                   "(tools/render_sound.py): YM2612 + PSG + DAC at PAL timing through libvgm. Songs run "
                   "to the end of their first loop; loop_offset (seconds) is where they loop back to.",
                   "songs": songs, "sfx": effects}, f, indent=1)


if __name__ == "__main__":
    main()
