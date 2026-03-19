# sega2asm

**Sega Mega Drive / Genesis ROM disassembler & splitter**

- Inspired by: [ethteck/splat](https://github.com/ethteck/splat) and [nathancassano/snes2asm](https://github.com/nathancassano/snes2asm).
- 68000 disassembler based on [Clownacy/clown68000](https://github.com/Clownacy/clown68000).
- Z80 disassembler based on [Clownacy/clownz80](https://github.com/Clownacy/clownz80).
- Assembly output compatible with [Clownacy/clownassembler](https://github.com/Clownacy/clownassembler) (asm68k clone).

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
| `text`     | `.txt` | Text with optional charmap decode |
| `bin`      | `.bin` | Raw binary blob |


**Compression formats supported:**

| Code | Type | Description | Compatible Games |
|---|---|---|---|
| `none` | — | No compression; data copied verbatim | — |
| `nemesis` | Huffman | Nemesis tile compression; Huffman-coded nybble runs per tile | Alien Storm, ATP Tour Championship Tennis, Ayrton Senna's Super Monaco GP II, Castle of Illusion, Chou Yakyuu Miracle Nine, Classic Collection, Columns, Disney Collection - Castle of Illusion & Quack Shot, Dr. Robotinik's Mean Bean Machine, ESWAT Cyber Police - City Under Siege, Fatal Labyrinth, Flicky, Forgotten Worlds, Genesis 6-Pak, Ghostbusters, Ghouls n Ghosts, Golden Axe, Golden Axe 2, Golden Axe 3, Jewel Master, Magical Taruruto-Kun, Mega Games 10 , Mega Games 2, Mega Games 3, Mega Games 6, Mega Games 6, Mega Games 6, Mega Games I, Mercs, Metal Fangs, Mighty Morphin Power Rangers - The Movie, MLBPA Sports Talk Baseball, Moonwalker, Musha, Phantasy Star 2, Phantasy Star 2 Text Adventures, Phantasy Star 3, Phantasy Star 4, Psy-O-Blade, Pulseman, Quackshot starring Donald Duck, Rent A Hero, Revenge of Shinobi, Ristar, Sega Mega Anser, Sega Sports 1, Sega Top 5, Shadow Dancer - The Secret of Shinobi, Sonic and Knuckles, Sonic Classics, Sonic Compilation, Sonic Crackers, Sonic Eraser, Sonic The Hedgehog, Sonic the Hedgehog 2, Sonic the Hedgehog 3, Streets of Rage, Streets of Rage 2, Streets of Rage 3, Strider, Super Hang-On, Super Monaco GP, Tecmo Super Bowl II SE, Tecmo Super Bowl III Final Edition, Twin Cobra, Virtua Racing, Wimbledon Championship Tennis, World Cup Italia '90, World of Illusion, Wrestle War |
| `kosinski` | LZ | Kosinski LZ-style scheme with sliding-window back-references | 16 Ton (SegaNet), Aworg (SegaNet) , Ayrton Senna's Super Monaco GP II, Battletoads, Bishoujo Senshi Sailor Moon, Disney Collection - Castle of Illusion & Quack Shot, Doki Doki Penguin Land MD (SegaNet), Flux for Mega-CD, Genesis 6-Pak, J. League Pro Striker - Perfect Edition, J. League Pro Striker 2, J. League Pro Striker Final Stage, Mega Games 10, Mega Games 2, Mega Games 3, Mega Games 6 (Vol 1) , Mega Games 6 (Vol 3) , Phantasy Star 4, Phantom 2040, Quackshot starring Donald Duck, Shinobi III - Return of the Ninja Master, Sonic and Knuckles, Sonic Classics , Sonic Crackers, Sonic The Hedgehog, Sonic The Hedgehog 2, Sonic The Hedgehog 3, Streets of Rage, Streets of Rage 3, Teddy Boy Blues (SegaNet), Virtua Racing, World of Illusion |
| `kosinskiplus` | LZ | Extended Kosinski with larger offset/count fields | Sonic 3 & Knuckles |
| `enigma` | Mixed | Bit-packed compression for mappings/tilemaps | Sonic 2, Sonic 3 & Knuckles |
| `segard` | RLE | SegaRD block-based RLE graphics compression | Alex Kidd in Enchanted Castle, Altered Beast, Columns, Golden Axe, Hokuto no Ken: Shin Seikimatsu Kyuuseishu Densetsu, Last Battle, Osomatsu-kun - Hachamecha Gekijou, World Championship Soccer |
| `saxman` | LZSS | Lightly-modified Okumura 1989 LZSS; 2-byte decompressed-size header | Sonic the Hedgehog 2 |
| `saxman_noheader` | LZSS | Same as `saxman` without the size header | Sonic the Hedgehog 2 |
| `comper` | LZ | Community format optimised for 68000 decompression speed at the cost of ratio | Community / Sonic hacks |
| `rocket` | LZ | Konami Rocket Knight compression | Rocket Knight Adventures |
| `faxman` | LZSS | Modified Saxman tuned to compress SMPS music data | Sonic hacks / SMPS tools |
| `rage` | LZ | Bit-stream LZ compressor | Streets of Rage series |
| `chameleon` | LZ | Kid Chameleon compressor | Kid Chameleon |
| `lznamco` | LZ | Namco LZ; 0x400-byte sliding window | Ball Jacks, Buning Force, Chibi Maruko-Chan: Waku Waku Shopping, Fushigi Umi No Nadia, Klax, Kyuukai Douchuuki, Marvel Land , Megapanel, Pac-Attack, PacMan2: The New Adventures, Phelios, Powerball, Rolling Thunder 2 |
| `lzstrike` | LZ | Same as `lznamco` but with 0x800-byte window | Desert Strike, Jungle Strike, Urban Strike |
| `lztechnosoft` | LZ | Technosoft LZ variant; no size header | Elemental Master |
| `lzkonami1` | LZ | Konami first-generation LZ | Animaniacs, Contra: Hard Corps, Lethal Enforcers II - Gun Fighters, Sparkster |
| `lzkonami2` | LZ | Konami second-generation LZ | Animaniacs, Castlevania Bloodlines, Contra: Hard Corps, Rocket Knight Adventures, Sunset Riders, Teenage Mutant Ninja Turtles: The Hyperstone Heist, Tiny Toon Adventures: Acme Allstars, Tiny Toon Adventures: Buster Hidden Treasure |
| `lzkonami3` | LZ | Konami third-generation LZ | Castlevania Bloodlines, Hyper Dunk - The Playoff Edition, Lethal Enforcers, Teenage Mutant Ninja Turtles: Tournament Fighters, Tiny Toon Adventures: Acme Allstars |
| `lzancient` | LZ + RLE | Ancient LZ compression | Beyond Oasis, Streets of Rage 2 |
| `lztose` | LZ | Tose LZ compression | Dragon Ball Z: Buyuu Retsuden |
| `lznextech` / `lzwolfteam` | LZ | Nextech / WolfTeam shared LZ compression | Crusader of Centy, El Viento, Granada, Earnest Evans, Final Zone, Ranger-X, Zan Yasha Enbuden |
| `lzsti` | LZ | STI LZ compression | Comix Zone |
| `rlesc` | RLE | Software Creations RLE compression | Cutthroat Island, Spiderman & Venom: Maximum Carnage, Spiderman & Venom: Separation Anxiety, The Tick  |
| `rnc` / `rnc1` / `rnc2` | LZH | Rob Northen Compression methods 1 & 2 | Various multiplatform ports and publisher tools |
| `lzcompile` | LZ | Compile Co. Ltd. command-byte LZ; 256-byte circular history, 4-byte output chunks | Dr. Robotnik's Mean Bean Machine, Mado Monogatari I, MUSHA Aleste, Puyo Puyo, Puyo Puyo 2 |
| `itl` | Mixed | I.T.L. (Sega) non-zero-byte copy + XOR block compression | Arrow Flash, Bonanza Bros., Chase HQ II, Growl, Ultimate Qix |
| `lzfactor5` | LZ | Factor 5 LZ; v1 = 11-bit window, v2 = 16-bit window (auto-detected from header) | International Superstar Soccer Deluxe, Mega Turrican |
| `lzbeam` | LZ | Beam Software LZ; Elias-coded counts, absolute back-references, command bits in appended bitstream | Blades of Vengeance, George Foreman's KO Boxing, NBA All-Star Challenge, Radical Rex, Super High Impact, Tom and Jerry - Frantic Antics, True Lies |
| `lztreasure` | LZ + RLE | Treasure Co. Ltd. multi-mode LZ; 2-byte size header, back-references + RLE single/pairs/alternating + literal runs | Alien Soldier, Dynamite Headdy, Gunstar Heroes, Light Crusader, McDonald's Treasure Land Adventure, Yu Yu Hakusho: Makyo Toitsuken |
| `lzblizzard` | LZSS | Okumura 1989 LZSS; 4096-byte ring buffer (zero-filled), 8-bit control flags LSB-first, 12-bit absolute offset + 4-bit length | Rock N Roll Racing, The Death and Return of Superman |
| `lzhlucasarts` | LZH | Adaptive Huffman + LZ sliding window (LZHUF variant); N=4096, F=60, ring buffer pre-filled 0x20; BE16 output size header; position via d_code/d_len tables | Zombies Ate My Neighbors |
| `lzclimax` | LZ77 | Climax LZ77; control byte MSB-first (1=literal, 0=back-ref), 12-bit offset + 4-bit length (3..18), offset=0 ends stream | Landstalker, Shining in the Darkness, Shining Force, Shining Force II |
| `lzwestone` | LZH | Westone Huffman+LZ tile decompressor (type 0x02); adaptive Huffman tree built from bitstream, symbols 0x000–0x0FF=literal, 0x100–0x11F=back-reference; always outputs 1024 bytes | Mega Bomberman, Monster World IV, Wonder Boy in Monster World |
| `lzwestone_block` | Mixed | Westone block-based tile decompressor (type 0x00); 32 blocks × 32 bytes; mode 0=literal, mode 1=sparse color-group bitmap, mode 2=XOR+planar bit-spread; always outputs 1024 bytes | Mega Bomberman, Monster World IV, Wonder Boy in Monster World |
| `lzkoei` | LZSS | KOEI LZSS variant; interleaved flag/literal bytes with 16-bit pairs words; Elias-gamma length coding; variable-width offset via p_len bias table; end marker length=255 | Various KOEI games |
| `rlegamearts` | RLE | Game Arts 4-plane RLE; 16-byte header with 8-byte lookup table + plane offsets; 7 opcode types; bit-interleaved output (plane order 3,2,0,1) | Alisia Dragoon |

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
