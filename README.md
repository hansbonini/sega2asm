# sega2asm

**Sega Mega Drive / Genesis ROM disassembler & splitter**

Inspired by [ethteck/splat](https://github.com/ethteck/splat) and [nathancassano/snes2asm](https://github.com/nathancassano/snes2asm).
68000 disassembler based on [Clownacy/clown68000](https://github.com/Clownacy/clown68000).
Z80 disassembler based on [Clownacy/clownz80](https://github.com/Clownacy/clownz80).
Assembly output compatible with [Clownacy/clownassembler](https://github.com/Clownacy/clownassembler) (asm68k clone).

---

## Features

| Segment type | Output | Description |
|---|---|---|
| `header`   | `.asm` | ROM header + interrupt vector table |
| `m68k`     | `.asm` | Motorola 68000 disassembly |
| `z80`      | `.asm` | Zilog Z80 disassembly (sound CPU) |
| `gfx`      | `.png` + `.bin` | Raw 4bpp tile graphics → PNG sheet |
| `gfxcomp`  | `.png` + `.bin` | Compressed graphics (auto-decompress) |
| `pcm`      | `.wav` | Raw PCM samples → WAV (7040 Hz default) |
| `psg`      | `.mid` | SN76489 PSG register stream → MIDI |
| `text`     | `.txt` | Text with optional charmap decode |
| `bin`      | `.bin` | Raw binary blob |

…
**Compression formats supported:**

| Code | Type | Description | Games |
|---|---|---|---|
| `none` | — | No compression; data copied verbatim | — |
| `nemesis` | Huffman | Konami tile compressor; Huffman-coded nybble runs per tile | Sonic series, many Konami MD titles |
| `kosinski` | LZ | Kosinski LZ-style scheme with sliding-window back-references | Sonic series and community tools |
| `kosinskiplus` | LZ | Extended Kosinski with larger offset/count fields | Sonic 3 & Knuckles |
| `enigma` | Mixed | Bit-packed compressor for mappings/tilemaps | Sonic 2, Sonic 3 & Knuckles |
| `segard` | RLE | SegaRD block-based RLE graphics compressor | Altered Beast |
| `saxman` | LZSS | Lightly-modified Okumura 1989 LZSS; 2-byte decompressed-size header | Sonic the Hedgehog 2 |
| `saxman_noheader` | LZSS | Same as `saxman` without the size header | Sonic the Hedgehog 2 |
| `comper` | LZ | Community format optimised for 68000 decompression speed at the cost of ratio | Community / Sonic hacks |
| `rocket` | LZ | Konami Rocket Knight compression | Rocket Knight Adventures |
| `faxman` | LZSS | Modified Saxman tuned to compress SMPS music data | Sonic hacks / SMPS tools |
| `rage` | LZ | Bit-stream LZ compressor | Streets of Rage series |
| `chameleon` | LZ | Kid Chameleon compressor | Kid Chameleon |
| `lznamco` | LZ | Namco LZ; 0x400-byte sliding window | Ball Jacks, Klax, Marvel Land, Pac-Attack, PacMan 2, Phelios |
| `lzstrike` | LZ | Same as `lznamco` but with 0x800-byte window | Desert Strike, Jungle Strike, Urban Strike |
| `lztechnosoft` | LZ | Technosoft LZ variant; no size header | Elemental Master |
| `lzkonami1` | LZ | Konami first-generation LZ | Animaniacs, Contra Hard Corps, Lethal Enforcers II, Sparkster |
| `lzkonami2` | LZ | Konami second-generation LZ | Castlevania Bloodlines, Rocket Knight, TMNT Hyperstone Heist, Sunset Riders |
| `lzkonami3` | LZ | Konami third-generation LZ | Castlevania Bloodlines, Lethal Enforcers, TMNT Tournament Fighters |
| `lzancient` | LZ + RLE | Ancient LZ compressor | Beyond Oasis, Streets of Rage 2 |
| `lztose` | LZ | Tose LZ compressor | Dragon Ball Z: Buyuu Retsuden |
| `lznextech` / `lzwolfteam` | LZ | Nextech / WolfTeam shared LZ compressor | Crusader of Centy, El Viento, Granada, Earnest Evans, Final Zone, Ranger-X, Zan Yasha |
| `lzsti` | LZ | STI LZ compressor | Comix Zone |
| `rlesc` | RLE | Software Creations RLE compressor | Maximum Carnage, Venom, The Tick, Cutthroat Island |
| `rnc` / `rnc1` / `rnc2` | LZH | Rob Northen Compression methods 1 & 2 | Various multiplatform ports and publisher tools |
| `lzcompile` | LZ | Compile Co. Ltd. command-byte LZ; 256-byte circular history, 4-byte output chunks | Puyo Puyo, Aleste / MUSHA, GG Aleste, Puyo Puyo 2, Power Strike II |
| `lzitl` | Mixed | I.T.L. (Sega) non-zero-byte copy + XOR block compressor | Bonanza Bros and other I.T.L.-developed Sega games |
| `lzfactor5` | LZ | Factor 5 LZ; v1 = 11-bit window, v2 = 16-bit window (auto-detected from header) | Factor 5 Mega Drive titles |
| `lzbeam` | LZ | Beam Software LZ; Elias-coded counts, absolute back-references, command bits in appended bitstream | Shadowrun, Batman Returns, Judge Dredd |
| `lztreasure` | LZ | Treasure Co. Ltd. multi-mode LZ; 2-byte size header, back-references + RLE single/pairs/alternating + literal runs | Gunstar Heroes, Alien Soldier, Dynamite Headdy, McDonald's Treasure Land Adventure |

**Labels & symbols:**
- Reads `symbols.txt` in multiple formats (name=addr, addr:name, space-separated)
- Used for branch targets, jumps and data labels in disassembly

**Charmap:**
- Standard `.tbl` format (THINGY / WindHex compatible)
- Used for `text` segments and `dc.b` string hints in `m68k` segments

---

## Installation

```bash
git clone https://github.com/hansbonini/sega2asm
cd sega2asm
go build -o sega2asm .
```

Requires Go 1.21+.

---

## Usage

```
sega2asm [options] <config.yaml>

Options:
  -c <file>      Configuration YAML file
  -s <file>      Symbols file (overrides config)
  -t <file>      Charmap TBL file (overrides config)
  -v             Verbose output
  --dry-run      Parse config & symbols, print plan, no file writes
  --version      Show version
```

### Quick start

```bash
sega2asm -c example/sonic1.yaml -s example/symbols.txt -t example/charmap.tbl -v
```

---

## Configuration YAML

```yaml
name: sonic1
sha1: ""                        # Optional SHA1 for ROM verification

options:
  platform: genesis             # genesis | megadrive
  region: ntsc                  # ntsc | pal
  basename: sonic1
  base_path: ./out              # Root output directory
  target_path: ./roms/sonic1.md # Input ROM file
  asm_path: asm                 # Sub-dir for .asm files
  asset_path: assets            # Sub-dir for graphics/audio
  build_path: build
  symbols_path: ./symbols.txt
  charmap_path: ./charmap.tbl
  header_output: true           # Write main .asm include file

segments:
  - name: header
    type: header
    start: 0x000000
    end: 0x000200

  - name: main_code
    type: m68k
    start: 0x000200
    end: 0x040000
    hints:
      - offset: 0x0000          # relative to segment start
        type: code
        label: EntryPoint
      - offset: 0x0E00
        type: data_long
        length: 32
        label: LevelPtrs

  - name: sound_driver
    type: z80
    start: 0x040000
    end: 0x042000

  - name: art_sonic
    type: gfxcomp
    compression: nemesis
    start: 0x050000
    end: 0x052000

  - name: sfx_jump
    type: pcm
    sample_rate: 7040
    start: 0x080000
    end: 0x081000

  - name: music_ghz
    type: psg
    start: 0x090000
    end: 0x091000

  - name: credits_text
    type: text
    encoding: charmap
    start: 0x0B0000
    end: 0x0B0200
```

---

## Symbols file formats

All of the following are accepted:

```
; C-style or semicolon comments are ignored

LabelName = $00A000           ; splat style
LabelName = 0x00A000

$00A000 LabelName             ; address-first
00A000:LabelName              ; colon separated
00A000 LabelName              ; hex space name
```

---

## Charmap TBL format

Standard THINGY / WindHex `.tbl` format:

```
; comment
00=                   ; byte 00 = empty / terminator
01=A
0D=\n
FF=<END>
```

Multi-byte keys are supported:
```
8141=ア
8142=イ
```

---

## Hint types (inline disassembly control)

| Type | Directive emitted |
|---|---|
| `code` | Normal disassembly |
| `data_byte` | `dc.b $XX` per byte |
| `data_word` | `dc.w $XXXX` per word |
| `data_long` | `dc.l $XXXXXXXX` per longword |
| `text` | `dc.b 'string',0` (charmap decoded) |
| `skip` | `even` (alignment padding) |

---

## Project layout (output)

```
out/
├── asm/
│   ├── m68k/
│   │   └── main_code.asm
│   ├── z80/
│   │   └── sound_driver.asm
│   ├── header/
│   │   └── header.asm
│   └── sonic1.asm          ← main include file
└── assets/
    ├── gfxcomp/
    │   └── art_sonic.png
    ├── pcm/
    │   └── sfx_jump.wav
    ├── psg/
    │   └── music_ghz.mid
    └── text/
        └── credits_text.txt
```

---

## References

- [ethteck/splat](https://github.com/ethteck/splat)
- [Clownacy/clownassembler](https://github.com/Clownacy/clownassembler)
- [Clownacy/clown68000](https://github.com/Clownacy/clown68000)
- [Clownacy/clownz80](https://github.com/Clownacy/clownz80)
- [Clownacy/clownnemesis](https://github.com/Clownacy/clownnemesis)
- [Clownacy/clownlzss](https://github.com/Clownacy/clownlzss)
- [hansbonini/smd_alteredbeast](https://github.com/hansbonini/smd_alteredbeast)
