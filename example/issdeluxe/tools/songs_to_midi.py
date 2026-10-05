#!/usr/bin/env python3
"""Write the ISS Deluxe songs as standard MIDI files.

Reads the songs decoded by the extractor (sound.json, "songs": the order
lists and packed patterns of song_play / song_order_update /
song_pattern_update / song_read_note, see "song_format" there) and writes
one format-1 MIDI file per song: a track per song track, 24 ticks a beat
as the driver counts them, the header's tempo, the notes' gates as their
lengths, velocities from the volumes. A song that loops is written once,
with a "loop" marker where it jumps back to.

    python3 tools/songs_to_midi.py out/godot/assets/iss/sound/sound.json out/godot/assets/iss/sound/midi

A note's MIDI number is the pattern note + 35 (song_pattern_update) +
the entry's transpose + 11 (the FM pitch table's first entry, 15.5 Hz, is
B(-1)) + the offset the track's instrument script adds to the pitch
(its $0B event's argument); a drum-kit script ($14 / $16 map) plays on
channel 10 with the pitch as the key.
"""
import json
import os
import struct
import sys

PPQ = 24
NOTE_BASE = 35 + 11


def vlq(n):
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.append(0x80 | (n & 0x7F))
        n >>= 7
    return bytes(reversed(out))


def midi_track(events):
    """events: [(tick, bytes)] -> a track chunk with running deltas."""
    events.sort(key=lambda e: (e[0], e[1][0] & 0xF0 != 0x90))  # offs before ons at the same tick
    data = bytearray()
    t = 0
    for tick, ev in events:
        data += vlq(tick - t) + ev
        t = tick
    data += vlq(0) + b"\xff\x2f\x00"
    return b"MTrk" + struct.pack(">I", len(data)) + bytes(data)


def song_events(song, variant):
    """[(tick, midi bytes)] per track 0-15, plus the loop tick (or None)."""
    tracks = [[] for _ in range(16)]
    order = variant["order"]
    patterns = variant["patterns"]
    instruments = song["track_instruments"]

    def pitch_of(instr, pitch):
        if "drums" in instr:
            return 9, pitch
        if "fixed_pitch" in instr:
            return None, int(instr["fixed_pitch"]) + 11
        return None, pitch + 11 + int(instr.get("pitch_offset", 0))

    t = 0
    loop = None
    for e in order:
        t += int(e["delay"])
        if e.get("end"):
            break
        if "jump" in e:
            loop = t
            break
        track = int(e["track"])
        instr = instruments[track]
        pos = t
        for note in patterns[int(e["pattern"])]:
            n, vol, dur, delay, cmd = note
            pos += delay
            if n == 0:
                break
            if n & 0x80:
                # An instrument change: the track's script from here on.
                instr = {"script": cmd, "pitch_offset": 0}
                continue
            ch, key = pitch_of(instr, n + NOTE_BASE - 11 + int(e["transpose"]))
            if ch is None:
                ch = track % 16
                if ch == 9:
                    ch = 15
            key = max(0, min(127, key))
            vel = max(1, min(127, (vol + int(e["volume"])) * 2))
            tracks[track].append((pos, bytes([0x90 | ch, key, vel])))
            tracks[track].append((pos + max(1, dur), bytes([0x80 | ch, key, 0])))
    return tracks, loop, t


def write_song(song, variant, path):
    tracks, loop, end = song_events(song, variant)
    chunks = []
    tempo = int(variant["tempo"]) or 120
    conductor = [(0, b"\xff\x51\x03" + struct.pack(">I", 60000000 // tempo)[1:]),
                 (0, b"\xff\x03" + vlq(len("song %d" % song["id"])) + ("song %d" % song["id"]).encode())]
    if loop is not None:
        conductor.append((loop, b"\xff\x06\x04loop"))
    chunks.append(midi_track(conductor))
    for i, ev in enumerate(tracks):
        if not ev:
            continue
        ch = next(e[1][0] & 0xF for e in ev)
        name = "track %d script %d" % (i, song["track_scripts"][i])
        ev = [(0, b"\xff\x03" + vlq(len(name)) + name.encode()), (0, bytes([0xC0 | ch, 0]))] + ev
        chunks.append(midi_track(ev))
    with open(path, "wb") as f:
        f.write(b"MThd" + struct.pack(">IHHH", 6, 1, len(chunks), PPQ) + b"".join(chunks))
    return sum(1 for ev in tracks for e in ev if e[1][0] & 0xF0 == 0x90), end


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    doc = json.load(open(sys.argv[1]))
    out = sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for song in doc["songs"]:
        for v, variant in enumerate(song["variants"]):
            suffix = "" if len(song["variants"]) == 1 else "_%d" % v
            path = os.path.join(out, "song_%02d%s.mid" % (song["id"], suffix))
            notes, end = write_song(song, variant, path)
            print("%s: %d notes, %d ticks, tempo %d" % (os.path.basename(path), notes, end, variant["tempo"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
