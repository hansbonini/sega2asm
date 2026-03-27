# sega2asm
![GitHub License](https://img.shields.io/github/license/hansbonini/sega2asm) ![GitHub go.mod Go version](https://img.shields.io/github/go-mod/go-version/hansbonini/sega2asm)

**Sega Mega Drive / Genesis ROM disassembler & splitter**

Inspired by [ethteck/splat](https://github.com/ethteck/splat) and [nathancassano/snes2asm](https://github.com/nathancassano/snes2asm), I decided to construct a splitter by segment type for Sega Genesis, for code segments the 68000 disassembler was based on [Clownacy/clown68000](https://github.com/Clownacy/clown68000) and the Z80 disassembler was based on [Clownacy/clownz80](https://github.com/Clownacy/clownz80). The assembly output of code segment is compatible with [Clownacy/clownassembler](https://github.com/Clownacy/clownassembler) which is a improved versions of asm68k assembler. For graphics segments a lot of compressions are available covering most of Sega Genesis games. For audio segments only PCM support are available yet.

---

## Features

| Segment type | Output | Description |
|---|---|---|
| `header`   | `.asm` | ROM header + interrupt vector table |
| `m68k`     | `.asm` | Motorola 68000 disassembly |
| `z80`      | `.asm` | Zilog Z80 disassembly (sound CPU) |
| `gfx`      | `.png` + `.bin` | Raw 4bpp tile graphics → PNG sheet |
| `gfxcomp`  | `.png` + `.bin` | Compressed graphics (auto-decompress) |
| `pcm`      | `.wav` + `.bin` | Raw PCM samples → WAV (7040 Hz default) |
| `text`     | `.txt` | Text with optional charmap decode |
| `bin`      | `.bin` | Raw binary blob |


**Compression formats supported:**

| Code | Type | Description | Compatible Games |
|---|---|---|---|
| `none` | — | No compression; data copied verbatim | — |
| `huffnemesis` | Huffman | Nemesis tile compression; Huffman-coded nybble runs per tile | Alien Storm, ATP Tour Championship Tennis, Altered Beast, Ayrton Senna's Super Monaco GP II, Castle of Illusion, Chou Yakyuu Miracle Nine, Classic Collection, Columns, Disney Collection - Castle of Illusion & Quack Shot, Dr. Robotinik's Mean Bean Machine, ESWAT Cyber Police - City Under Siege, Fatal Labyrinth, Flicky, Forgotten Worlds, Genesis 6-Pak, Ghostbusters, Ghouls n Ghosts, Golden Axe, Golden Axe 2, Golden Axe 3, Jewel Master, Magical Taruruto-Kun, Mega Games 10 , Mega Games 2, Mega Games 3, Mega Games 6, Mega Games 6, Mega Games 6, Mega Games I, Mercs, Metal Fangs, Mighty Morphin Power Rangers - The Movie, MLBPA Sports Talk Baseball, Moonwalker, Musha, Phantasy Star 2, Phantasy Star 2 Text Adventures, Phantasy Star 3, Phantasy Star 4, Psy-O-Blade, Pulseman, Quackshot starring Donald Duck, Rent A Hero, Revenge of Shinobi, Ristar, Sega Mega Anser, Sega Sports 1, Sega Top 5, Shadow Dancer - The Secret of Shinobi, Sonic and Knuckles, Sonic Classics, Sonic Compilation, Sonic Crackers, Sonic Eraser, Sonic The Hedgehog, Sonic the Hedgehog 2, Sonic the Hedgehog 3, Streets of Rage, Streets of Rage 2, Streets of Rage 3, Strider, Super Hang-On, Super Monaco GP, Tecmo Super Bowl II SE, Tecmo Super Bowl III Final Edition, Twin Cobra, Virtua Racing, Wimbledon Championship Tennis, World Cup Italia '90, World of Illusion, Wrestle War |
| `lzkosinski` | LZ | Kosinski LZ-style scheme with sliding-window back-references | 16 Ton (SegaNet), Aworg (SegaNet) , Ayrton Senna's Super Monaco GP II, Battletoads, Bishoujo Senshi Sailor Moon, Disney Collection - Castle of Illusion & Quack Shot, Doki Doki Penguin Land MD (SegaNet), Flux for Mega-CD, Genesis 6-Pak, J. League Pro Striker - Perfect Edition, J. League Pro Striker 2, J. League Pro Striker Final Stage, Mega Games 10, Mega Games 2, Mega Games 3, Mega Games 6 (Vol 1) , Mega Games 6 (Vol 3) , Phantasy Star 4, Phantom 2040, Quackshot starring Donald Duck, Shinobi III - Return of the Ninja Master, Sonic and Knuckles, Sonic Classics , Sonic Crackers, Sonic The Hedgehog, Sonic The Hedgehog 2, Sonic The Hedgehog 3, Streets of Rage, Streets of Rage 3, Teddy Boy Blues (SegaNet), Virtua Racing, World of Illusion |
| `lzhrnc` / `lzhrnc1` / `lzhrnc2` | LZH | Rob Northen Compression methods 1 & 2 | 3 Ninjas Kick Back, Addams Family, Addams Family Values, The Adventures of Mighty Max, Astérix and the Great Rescue, Astérix and the Power of the Gods, The Humans, The Incredible Hulk, The Itchy & Scratchy Game (unreleased), Marsupilami, Mortal Kombat, Mortal Kombat 2, Mortal Kombat 3, Mr. Nutz, Outlander, The Pagemaster, RoboCop 3, Spirou, Spot Goes to Hollywood, Stargate, Street Racer, Tinhead, Tintin in Tibet, World Championship Soccer II, The Chaos Engine |
| `lznamco` | LZ | Namco LZ; 0x400-byte sliding window | Ball Jacks, Buning Force, Chibi Maruko-Chan: Waku Waku Shopping, Fushigi Umi No Nadia, Klax, Kyuukai Douchuuki, Marvel Land , Megapanel, Pac-Attack, PacMan2: The New Adventures, Phelios, Powerball, Rolling Thunder 2 |
| `lzsskoei` | LZSS | KOEI LZSS variant; interleaved flag/literal bytes with 16-bit pairs words; Elias-gamma length coding; variable-width offset via p_len bias table; end marker length=255 | Aerobiz, Aerobiz Supersonic , Gemfire, Genghis Khan II, Liberty or Death, Nobunaga's Ambition, Operation Europe, P.T.O.: Pacific Theater of Operations, Romance of the Three Kingdoms II (also on Amiga), Romance of the Three Kingdoms III, Uncharted Waters, Uncharted Waters: New Horizons |
| `rlesegard` | RLE | SegaRD block-based RLE graphics compression | Alex Kidd in Enchanted Castle, Altered Beast, Columns, Golden Axe, Hokuto no Ken: Shin Seikimatsu Kyuuseishu Densetsu, Last Battle, Osomatsu-kun - Hachamecha Gekijou, World Championship Soccer |
| `lzkonami2` | LZ | Konami second-generation LZ | Animaniacs, Castlevania Bloodlines, Contra: Hard Corps, Rocket Knight Adventures, Sunset Riders, Teenage Mutant Ninja Turtles: The Hyperstone Heist, Tiny Toon Adventures: Acme Allstars, Tiny Toon Adventures: Buster Hidden Treasure |
| `lzbeam` | LZ | Beam Software LZ; Elias-coded counts, absolute back-references, command bits in appended bitstream | Blades of Vengeance, George Foreman's KO Boxing, NBA All-Star Challenge, Radical Rex, Super High Impact, Tom and Jerry - Frantic Antics, True Lies |
| `lznextech` / `lzwolfteam` | LZ | Nextech / WolfTeam shared LZ compression | Crusader of Centy, El Viento, Granada, Earnest Evans, Final Zone, Ranger-X, Zan Yasha Enbuden |
| `lztreasure` | LZ + RLE | Treasure Co. Ltd. multi-mode LZ; 2-byte size header, back-references + RLE single/pairs/alternating + literal runs | Alien Soldier, Dynamite Headdy, Gunstar Heroes, Light Crusader, McDonald's Treasure Land Adventure, Yu Yu Hakusho: Makyo Toitsuken |
| `lzcompile` | LZ | Compile Co. Ltd. command-byte LZ; 256-byte circular history, 4-byte output chunks | Dr. Robotnik's Mean Bean Machine, Mado Monogatari I, MUSHA Aleste, Puyo Puyo, Puyo Puyo 2 |
| `lzkonami3` | LZ | Konami third-generation LZ | Castlevania Bloodlines, Hyper Dunk - The Playoff Edition, Lethal Enforcers, Teenage Mutant Ninja Turtles: Tournament Fighters, Tiny Toon Adventures: Acme Allstars |
| `mixeditl` | Mixed | I.T.L. (Sega) non-zero-byte copy + XOR block compression | Arrow Flash, Bonanza Bros., Chase HQ II, Growl, Ultimate Qix |
| `lzkonami1` | LZ | Konami first-generation LZ | Animaniacs, Contra: Hard Corps, Lethal Enforcers II - Gun Fighters, Sparkster |
| `rlesc` | RLE | Software Creations RLE compression | Cutthroat Island, Spiderman & Venom: Maximum Carnage, Spiderman & Venom: Separation Anxiety, The Tick  |
| `lzssblizzard` | LZSS | Okumura 1989 LZSS; 4096-byte ring buffer (zero-filled), 8-bit control flags LSB-first, 12-bit absolute offset + 4-bit length | Rock N Roll Racing, The Death and Return of Superman, The Lost Vikings |
| `lzstrike` | LZ | Same as `lznamco` but with 0x800-byte window | Desert Strike, Jungle Strike, Urban Strike |
| `mixedenigma` | Mixed | Bit-packed compression for mappings/tilemaps | Sonic 2, Sonic 3 & Knuckles |
| `lzancient` | LZ + RLE | Ancient LZ compression | Beyond Oasis, Streets of Rage 2 |
| `lzhwestone` | LZH | Westone Huffman+LZ tile decompressor (type 0x02); adaptive Huffman tree built from bitstream, symbols 0x000–0x0FF=literal, 0x100–0x11F=back-reference; always outputs 1024 bytes | Monster World IV, Wonder Boy in Monster World |
| `mixedwestone` | Mixed | Westone block-based tile decompressor (type 0x00); 32 blocks × 32 bytes; mode 0=literal, mode 1=sparse color-group bitmap, mode 2=XOR+planar bit-spread; always outputs 1024 bytes | Monster World IV, Wonder Boy in Monster World |
| `lzcomper` | LZ | Community format optimised for 68000 decompression speed at the cost of ratio | Community / Sonic hacks |
| `lzssfaxman` | LZSS | Modified Saxman tuned to compress SMPS music data | Sonic hacks / SMPS tools |
| `lzsssaxman` | LZSS | Lightly-modified Okumura 1989 LZSS; 2-byte decompressed-size header | Sonic the Hedgehog 2 |
| `lzsssaxman_noheader` | LZSS | Same as `lzsssaxman` without the size header | Sonic the Hedgehog 2 |
| `lzkosinskiplus` | LZ | Extended Kosinski with larger offset/count fields | Sonic 3 & Knuckles |
| `lzrocket` | LZ | Konami Rocket Knight compression | Rocket Knight Adventures |
| `lzrage` | LZ | Bit-stream LZ compressor | Streets of Rage 2 |
| `lzchameleon` | LZ | Kid Chameleon compressor | Kid Chameleon |
| `lztechnosoft` | LZ | Technosoft LZ variant; no size header | Elemental Master |
| `lzbandai` | LZ | Bandai LZ compression | Dragon Ball Z: Buyuu Retsuden |
| `lzsti` | LZ | STI LZ compression | Comix Zone |
| `lzfactor5` | LZ | Factor 5 LZ; v1 = 11-bit window, v2 = 16-bit window (auto-detected from header) | International Superstar Soccer Deluxe |
| `lzhlucasarts` | LZH | Adaptive Huffman + LZ sliding window (LZHUF variant); N=4096, F=60, ring buffer pre-filled 0x20; BE16 output size header; position via d_code/d_len tables | Zombies Ate My Neighbors |
| `lz77climax` | LZ77 | Climax LZ77; control byte MSB-first (1=literal, 0=back-ref), 12-bit offset + 4-bit length (3..18), offset=0 ends stream | Landstalker |
| `expgolombclimax` | Exp-Golomb + Spatial | Climax/Camelot 4bpp tile graphics; exp-Golomb position coding + 2-D spatial nibble navigation + nibble-pair packing + 4×4 tile reorder; dimensions header (must be multiples of 4 tiles) | Shining Force |
| `lzclimax` | LZ + RLE | Camelot/Climax bitstream LZ (LoadBasicCompressedData); addx word-chaining control bits, inline literal copies (longword/word), back-references with rotated 12-bit offset + inverse 5-bit length jump table, word-repeat RLE; self-terminating (no header) | Shining Force 2 |
| `rlegamearts` | RLE | Game Arts 4-plane RLE; 16-byte header with 8-byte lookup table + plane offsets; 7 opcode types; bit-interleaved output (plane order 3,2,0,1) | Alisia Dragoon |
| `lzpowerpack20` | LZ77 | PowerPacker 2.0 (no magic variant); backwards LZ77 with sentinel-based bitstream, 4-byte efficiency table, extended literal/match length coding; self-sizing header (u32be total size + trailer with decompressed size) | James Pond 3 |
| `rlebahamut` | RLE + Mixed | Bahamut Senki byteplane-interleaved command-nibble scheme; even/odd byte planes at stride 2; 7 commands (terminate, RLE fill, literal copy, incrementing fill, repeated sub-run, repeated incremental run, uncompressed passthrough); length in low nibble with 8-bit extended length | Bahamut Senki |
| `huffsamsung` | Huffman + Nibble | Samsung Huffman-nibble tile compressor; canonical Huffman table (8 code lengths), 8-bit lookup with 2+7 bit escape codes, value byte = repeat count (high nibble) + pixel (low nibble), 8 nibbles packed per longword, optional XOR delta mode; header encodes tile count + XOR flag | Uzu Keobukseon |

> **Total: 211 unique games covered across 37 compression formats**

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

### Optional LUA Scripts

On folder `optional` there are some LUA scripts that could be run on Emulator to help user and automate collect segments task, here is the list:

| Emulator                         | Script File          |
| -------------------------------- | -------------------- |
| Gens R57Shell Mod                | `gensr57shell.lua`   |

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
  no_suggestions: false         # Set true to suppress split-hint output

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

      - offset: 0x0E00          # absolute pointer table (longwords)
        type: ptr_table
        length: 32
        label: LevelPtrs

      - offset: 0x0F00          # relative pointer table (signed words)
        type: ptr_table_rel
        length: 16
        label: JumpTable
        base: 0x000F00          # base ROM address subtracted from each entry

      - offset: 0x1000          # inline binary blob → extracted file + incbin
        type: bin
        length: 256
        label: SpriteData
        file: sprite_data.bin   # written to same dir as the .asm file

      - offset: 0x1100          # text string decoded with charmap
        type: text
        length: 7
        label: GameTitle

      - offset: 0x1200          # raw byte values
        type: data_byte
        length: 4

      - offset: 0x1204          # raw word values
        type: data_word
        length: 4

      - offset: 0x1208          # raw longword values
        type: data_long
        length: 8

      - offset: 0x1210          # alignment padding
        type: skip
        length: 2

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

Hints override the disassembler output for a byte range within an `m68k` segment.
They are applied even when the disassembler would have decoded those bytes as
a different instruction or skipped them inside a multi-byte opcode.

**Common fields**

| Field | Required | Description |
|---|---|---|
| `offset` | yes | Byte offset relative to the segment `start` |
| `type` | yes | One of the types below |
| `length` | yes | Number of bytes covered |
| `label` | no | Label emitted before the directive |
| `base` | `ptr_table_rel` only | Absolute ROM address used as the subtraction base |
| `file` | `bin` only | Output filename (default: `<label>.bin`) |

**Hint types**

| Type | Directive emitted | Notes |
|---|---|---|
| `code` | Normal M68K disassembly | Explicitly marks a range as code (useful after data blocks) |
| `data_byte` | `dc.b $XX` per byte | |
| `data_word` | `dc.w $XXXX` per 2 bytes | |
| `data_long` | `dc.l $XXXXXXXX` per 4 bytes | |
| `ptr_table` | `dc.l <label>` per 4 bytes | Absolute 32-bit pointer; resolves to symbol name if known |
| `ptr_table_rel` | `dc.w <target>-<base>` per 2 bytes | Signed 16-bit offset relative to `base`; target resolved to symbol name |
| `text` | `dc.b 'string',0` | ASCII or charmap-decoded string; null terminator appended |
| `vdp_regs` | `dc.w $XXXX ; VDP reg #N = $YY (...)` | Each 16-bit word decoded as a VDP register write; annotated with register name and field values |
| `vdp_cmds` | `dc.l $XXXXXXXX ; VDP <type> addr=$XXXX` | Each 32-bit longword decoded as a VDP control port command (address set, DMA setup, or register pair) |
| `bin` | `incbin "file.bin"` | Extracts bytes to `file` (beside the `.asm`) and emits an `incbin` directive |
| `skip` | `even` | Alignment padding; length bytes are suppressed |

**VDP hint example**

```yaml
- offset: 0x0040
  type: vdp_regs        # table of dc.w VDP register writes
  length: 48            # 24 words = 24 register writes
  label: vdp_init_table

- offset: 0x0070
  type: vdp_cmds        # table of dc.l VDP control commands (address set / DMA)
  length: 16
  label: vdp_dma_setup
```

Generated output:
```asm
vdp_init_table:
    dc.w  $8004  ; VDP reg #0 = $04 (Mode1: off)
    dc.w  $8174  ; VDP reg #1 = $74 (Mode2: DisplayOn|VInt|DMAEn|V28)
    dc.w  $8230  ; VDP reg #2 = $30 (PlaneA=$C000)
    dc.w  $8328  ; VDP reg #3 = $28 (Window=$A000)
    dc.w  $8407  ; VDP reg #4 = $07 (PlaneB=$E000)
    dc.w  $857C  ; VDP reg #5 = $7C (Sprites=$F800)
    dc.w  $8700  ; VDP reg #7 = $00 (BgColor=PAL0[0])
    ...
vdp_dma_setup:
    dc.l  $40000080  ; VDP VRAM write addr=$0000
    dc.l  $94009300  ; VDP reg #19 = $00 | VDP reg #20 = $93 (DMALen_hi=$93 words=37632)
```

---

## VDP register reference

A VDP register write is a 16-bit word of the form `$8NVV` where `N` = register number (0–23) and `VV` = value. Two consecutive writes can be packed into a 32-bit longword.

| Reg | Name | Decoded fields |
|---|---|---|
| 0 | Mode Register 1 | Bit 4: `DispOff` · Bit 3: `HVLatch` (freeze H/V counter) · Bit 1: `HInt` (H-blank interrupt enable) · Bit 0: `LCB` (left column blank) |
| 1 | Mode Register 2 | Bit 7: `VRAM128K` · Bit 6: `DisplayOn/Off` · Bit 5: `VInt` (V-blank interrupt enable) · Bit 4: `DMAEn` · Bit 3: `V30`/`V28` (240/224 lines) |
| 2 | Plane A Name Table | `PlaneA=$XXXX` — VRAM address (bits 5-3 × 0x400) |
| 3 | Window Name Table | `Window=$XXXX` — VRAM address (bits 5-1 × 0x400) |
| 4 | Plane B Name Table | `PlaneB=$XXXX` — VRAM address (bits 2-0 × 0x2000) |
| 5 | Sprite Table | `Sprites=$XXXX` — VRAM address (bits 6-0 × 0x200) |
| 6 | Sprite Table (hi) | `Sprites_hi=N` — MSB for 128 KB VRAM mode |
| 7 | Background Color | `BgColor=PALN[N]` — palette line (bits 5-4) and color index (bits 3-0) |
| 8 | SMS H Scroll | `SMSHScroll=$XX` — SMS compatibility; unused in Mode 5 |
| 9 | SMS V Scroll | `SMSVScroll=$XX` — SMS compatibility; unused in Mode 5 |
| 10 | H Interrupt Counter | `HInt every N lines` — H-blank fires every N+1 scanlines |
| 11 | Mode Register 3 | Bit 3: `ExtVScroll` (2-cell column scroll) · Bit 2: `IE2` (external interrupt enable) · Bits 1-0: `HScroll=FullScreen/Invalid/Cell/Line` |
| 12 | Mode Register 4 | Bits 7+0: `H40`/`H32` · Bits 2-1: interlace mode · Bit 3: `+Shadow` (shadow/highlight enable) |
| 13 | H Scroll Data | `HScroll=$XXXX` — VRAM address (bits 5-0 × 0x400) |
| 14 | Name Table (hi) | `NTBase_hi` — Plane A/B address MSBs for 128 KB VRAM mode |
| 15 | Auto-Increment | `AutoInc=N` — bytes added to VDP address after each data port access |
| 16 | Scroll Size | `ScrollSize=WxH cells` — plane dimensions: 32/64/128 cells wide/tall |
| 17 | Window H Position | `WindowH=Left/Right cell=N` — window plane horizontal split |
| 18 | Window V Position | `WindowV=Up/Down cell=N` — window plane vertical split |
| 19 | DMA Length Low | `DMALen_lo=$XX` |
| 20 | DMA Length High | `DMALen_hi=$XX (words=N)` |
| 21 | DMA Source Low | `DMASrc_lo=$XX` |
| 22 | DMA Source Mid | `DMASrc_mid=$XX` |
| 23 | DMA Source High | `DMASrc_hi=$XX (ROM/RAM→VRAM)` / `(fill)` / `DMA VRAM copy` — bits 7-6 select DMA type |

**VDP control commands** (32-bit longwords to `$C00004`) decode the CD bits to determine the operation:

| CD bits | Operation |
|---|---|
| `0x00` | VRAM read |
| `0x01` | VRAM write |
| `0x03` | CRAM write |
| `0x04` | VSRAM read |
| `0x05` | VSRAM write |
| `0x08` | CRAM read |
| `0x20` | DMA fill |
| `0x21` | VRAM DMA write |
| `0x23` | CRAM DMA write |
| `0x25` | VSRAM DMA write |
| `0x30` | VRAM DMA copy |

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
    └── text/
        └── credits_text.txt
```

---

## References

- [ethteck/splat](https://github.com/ethteck/splat)
- [nathancassano/snes2asm](https://github.com/nathancassano/snes2asm)
- [Clownacy/clownassembler](https://github.com/Clownacy/clownassembler)
- [Clownacy/clown68000](https://github.com/Clownacy/clown68000)
- [Clownacy/clownz80](https://github.com/Clownacy/clownz80)
- [Clownacy/clownnemesis](https://github.com/Clownacy/clownnemesis)
- [Clownacy/clownlzss](https://github.com/Clownacy/clownlzss)
- [hansbonini/smd_alteredbeast](https://github.com/hansbonini/smd_alteredbeast)
- [hansbonini/swissknife](https://github.com/hansbonini/swissknife)
