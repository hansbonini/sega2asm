# International Superstar Soccer Deluxe (Mega Drive) — disassembly

A complete, **bit-exact, rebuildable** disassembly of *International Superstar
Soccer Deluxe* (Europe) for the Sega Mega Drive, produced with `sega2asm`, plus
an asset export aimed at re-implementing the game in **Godot 4**.

| | |
|---|---|
| ROM | `International Superstar Soccer Deluxe (Europe).md`, 2 MB (16 Mbit) |
| SHA-1 | `CCC60352B43F8C3D536267DD05A8F2C0F3B73DF6` |
| Header | `GM T-95196-50`, (C) Konami 1996, developed by Factor 5 |
| Video | H32 mode (256 × 224), 64×32-cell planes, shadow/highlight enabled |

No ROM data is stored in this repository: the configuration, symbols and tools
regenerate everything from your own copy of the ROM.

## What you get

* **860 segments** that tile the whole ROM with no gaps. Rebuilding them with
  `clownassembler` produces a file identical to the original (`sega2asm verify`).
* **266 KB of 68000 code** found by a recursive control-flow trace
  (1,295 routines, jump tables and code pointers resolved), emitted as 30
  assembly files (26 main, 2 boot, 2 sound) with labels for every branch/call
  target and every referenced data address, so code can be edited and
  reassembled without breaking references.
* Every pointer and offset table written symbolically (`dc.l res07-res_directory`),
  RAM globals written as `(g_next_state-$FF0000)(a6)` and object fields as
  `obj_facing(a5)` (the `obj` layout is declared in the YAML `structs:` block).
* The **Factor 5 resource archive** (87 groups, 478 entries, 900 KB) split
  entry by entry and typed: 354 tile sheets, 71 tilemaps, 82 palettes, all
  decompressed and rendered as indexed PNGs; palettes as `.gpl`/`.json`.
* The 565 KB PCM sample bank, the 26-song music bank and the Z80 PCM driver as
  separate blobs.
* A curated symbols file (`issdeluxe_symbols.txt`) documenting the engine; the
  comments are written above each routine in the generated source.
* `sega2asm godot` turns all of the above into a Godot 4 project (see below).

## Building

Requirements: Go 1.21+, [clownassembler](https://github.com/Clownacy/clownassembler)
(asm68k compatible) in `PATH` or `$CLOWNASSEMBLER`.

```bash
# from the repository root
go build -o sega2asm .

# put your ROM next to the YAML with this exact name
cp /path/to/rom.md "example/issdeluxe/International Superstar Soccer Deluxe (Europe).md"

cd example/issdeluxe
../../sega2asm -c issdeluxe.yaml        # split: writes ./out/asm and ./out/assets
../../sega2asm verify issdeluxe.yaml    # assemble ./out and compare with the ROM
../../sega2asm godot issdeluxe.yaml     # export ./out/godot (Godot 4.3+ project)
```

`verify` runs `clownassembler -i asm/issdeluxe.asm -o build/issdeluxe.bin` from
`./out` (all include/incbin paths are relative to it) and reports the first
differing ranges and their segments if anything does not match.

### Layout of `out/`

```
out/asm/issdeluxe.asm        main file: includes everything in ROM order
out/asm/include/             ports.asm (hardware registers), variables.asm (RAM),
                             macros.asm (see "Assembler notes")
out/asm/header/              vector table and cartridge header
out/asm/main/                main program ($000200–$05DB50): 26 code files + data
out/asm/boot/                boot / logo module ($144318–$14A150)
out/asm/sound/               68000 sound driver ($1FD954–$200000)
out/asm/archive/             resource archive directory and group offset tables
out/assets/archive/          archive entries: .bin (as stored), .decompressed.bin,
                             .png (indexed), palettes .gpl/.json/.png, tilemaps .json
out/assets/boot/, sound/     boot-module resources, PCM (.wav), songs
out/build/issdeluxe.bin      rebuilt ROM
```

## ROM map

| Range | Contents |
|---|---|
| `$000000–$000200` | Vector table and header |
| `$000200–$020408` | Main program: system library (DMA queue, sprites, objects, fades, pads, decompression), match engine, game states |
| `$020408–$03B09E` | Data tables used by the match engine and menus, interleaved with small code modules |
| `$03B09E–$05D72A` | Front-end program: menus, team/option screens, scenarios, results |
| `$05D72A–$05DB50` | Front-end data |
| `$05DB50–$144318` | **Resource archive** (see formats): 87 groups |
| `$144318–$14A150` | Boot module: SEGA, Konami, Factor 5, intro and title screens (`boot_main`, d0 = screen; `boot_sega` … `boot_title`) |
| `$14A150–$1613EC` | Boot module palettes and five resource groups |
| `$1613EC–$1EB45C` | PCM sample bank (signed 8-bit samples, addressed by the offset list at `$1FFBD8`) |
| `$1EB45C–$1FD954` | Music bank: 29 offsets, 26 songs, the sound script table (1024 scripts), table 1 and the effect table |
| `$1FD954–$200000` | 68000 sound driver (16-entry `bra.w` API, software PCM mixer) with the 248-byte Z80 program at `$1FDC06` |

Archive groups of note: `res00` uncompressed sprite tiles (players, stored
column-major per sprite), `res07`–`res14` the eight stadium sets
(`load_stadium_tiles`: group = 7 + stadium), `res26`–`res86` full-screen images
(tiles + 64×32 map + 32-colour palette each).

## Engine architecture

**Boot.** `reset` performs the standard TMSS/VDP/Z80 initialisation, then
`main_init` calls `boot_main` four times (logo screens) and `warm_start`
initialises the system (`system_init`), the sound driver (`sound_init`) and
jumps to the first game state.

**States and frames.** A game state is a routine stored in `g_next_state` and
entered through `main_loop_dispatch`. Each state (`state_menu`, `state_screen`,
`state_match`, `state_shootout`) loads its resources, installs a VBlank handler
in `g_vblank_handler`, starts a palette fade-in and then *busy-waits* until
`g_frame_state` returns to 0. **All game logic runs inside the VBlank
interrupt**: the handler writes scroll registers, flushes the DMA queue, ticks
the sound driver, reads the pads, runs the objects and builds the sprite list.
`g_frame_state`: 1 = fading in, 2 = running, 0 = finished (after the fade-out).
In Godot this maps naturally to one scene per state with the handler body in
`_physics_process` at 60 Hz (50 Hz on PAL: `g_is_pal`).

**Objects.** Everything that moves (players, ball, cursors, menu widgets,
palette fades) is an object in a doubly linked list (`obj_alloc`, `obj_free`,
`objects_update`, `objects_draw`). Layout known so far:

| Offset | Field |
|---|---|
| `+$00` / `+$04` | next / previous object |
| `+$0E` | on-screen flag (1 = visible, $FF = culled) |
| `+$10` | world X |
| `+$14` | world Y (also the depth-sort key) |
| `+$18` | height Z |
| `+$1C` / `+$1E` | computed screen X / Y |
| `+$34` | update callback (−1 = none) |
| `+$38` | think / pre-update callback |
| `+$66` | draw callback (−1 = none) |

**Ball.** `ball_update` integrates height with gravity (`vz -= $1400` per
frame NTSC, `$1CCC` PAL — the square of the 1.2 ratio, since it is an
acceleration), bounces with `vz = -vz/2` (sound effect 88, speed loses
`speed >> tbl_ball_bounce_damp[g_weather]` = 1, 2, 1 for snow, fine, rain),
rolls with friction `speed -= speed >> tbl_ball_friction[g_weather]` (5, 5, 4)
and moves along `obj_heading` (`velocity_from_heading`). Lofted passes and
high kicks have their own update routines (`ball_update_lob`,
`ball_update_high`). `ball_draw` picks the sprite size from the height
(`action = clamp((z − $20) >> 5, 0, 2)`, 3 for a lofted pass) and the spin
frame from `obj_anim_frame` (16.16, + speed/4 per frame rolling, + 1/8 in the
air), and draws a shadow piece `z` pixels below the ball.

**Weather.** `g_weather` is 0 = snow, 1 = fine (the front-end default),
2 = rain. It selects the stadium palette (entries 6–8), keeps (snow) or patches
out (fine, rain) the snow clumps in tiles 238–255, sets the ball friction and
bounce, and animates the plane A overlay: `match_init_hud` loads res16 entry
`g_weather` into plane A (empty for fine weather) and `hud_update` streams
falling-snow frames (res04 entry 7, every 8 frames) or rain frames (entry 8,
every frame) into overlay tiles `$103`–`$106`.

**Motion.** Angles are 0–63 (0 = up the pitch, 16 = right, clockwise);
`direction_to` is a table-driven atan2 and `tbl_direction_x` holds the unit
vectors (8.8 fixed point, shaped for the oblique view). Every speed is stored
as an (NTSC, PAL) pair of 16.16 values with PAL = 1.2 × NTSC
(`tbl_speed_ntsc_pal`), i.e. the game runs its logic once per video frame and
compensates for 50 Hz — a port should run at a fixed 60 Hz tick and use the
NTSC values.

The pitch uses an **oblique projection** (`objects_draw`):
`screen_x = x + y/2 − hscroll`, `screen_y = y/2 − z − vscroll`, with objects
drawn back-to-front by Y. Reproduce this in Godot with a `Node2D` per object and
`z_index`/`y_sort` driven by world Y.

**Video.** VRAM layout (`vdp_init_game`): plane B `$0000`, window `$1000`,
sprites `$1C00`, h-scroll `$1800`, plane A `$2000`, 64×32-cell planes, H32.
All VRAM/CRAM uploads go through a 64-entry DMA queue (`dma_queue_add`,
`dma_queue_add_cram`, flushed by `dma_queue_flush` with a per-frame budget).
Palettes: `g_palette_target` (64 colours) is faded into `g_palette_current`,
which is uploaded every frame. Text is drawn into an off-screen nametable
(`g_text_nametable`) by `text_draw_small` / `text_draw_large`.

In a match the VDP runs in **shadow/highlight mode**: every sprite shadow is
palette line 3 colour 15, which the VDP does not draw but uses to halve the
brightness underneath (colour 14 would highlight). Plane A (the weather
overlay) has the priority bit on every cell, so the pitch itself is never
shadowed. An HBlank chain (`hblank_hud_split`) splits the screen at the HUD;
below the split the backdrop colour (VDP register 7) is line 3 colour 0, the
grass, which shows through every transparent pitch pixel.

**Game modes.** The main menu (`g_menu_item`) leads to: 0 a match submenu
(open game, short league, short tournament), 1 International Cup, 2 World
Series, 3 password entry, 4 scenario, 5 PK, 6 training / challenge,
7 options. `g_game_mode` records the choice (`mode_start_*` set it up;
`mode_resume_*` restore it from a password, selected by the password's
length `g_password_length`):

| Mode | | Mode | |
|---|---|---|---|
| 0 | training (free, defence, free kick, keeper) | 7 | International Cup group (preliminary) round |
| 1 | challenge (dribble, pass, shoot, defence, free kick, timed) | 8 | International Cup finals |
| 2 | PK: penalty shoot-out only | 9 | World Series |
| 3 | open game | `$A` | Championship |
| 4 | short league | `$B` | attract demo (ends after 4 clock minutes) |
| 5 | short tournament | `$C` | scenario (12 situations, screen `$24`) |
| 6 | International Cup elimination round | | |

A penalty shoot-out (PK mode uses one too) runs `state_shootout` once per
kick while `g_shootout_kicks` is below 5: the kick is seen from behind the
taker (screen `$26`, the 16 × 16 ball of `ball_update_large`).
`shootout_setup` places the taker (the next in the order list, x $80,
y $12C, facing away, with the ball) and the keeper (x $80, y $CC, facing the
camera). The keeper (`shootout_keeper`) waits until the ball moves, then the
pad (or `shootout_keeper_ai`) picks a save: pass + direction crouches, pass
alone steps across, lofted + direction jumps with both arms, lofted alone
reaches with one arm (the frames of actions 31, 33, 30 and 32 seen from the
front).

**Options** (`g_settings`, 8 words at $FFFFF0 kept across resets with a
checksum; `system_init` restores the defaults when the checksum is wrong):

| Word | Setting | Values (default in bold) |
|---|---|---|
| $FFFFF0 | game level | 0-4 (**2**); CPU teams play at this `tm_ai_level` and `tm_keeper_skill` |
| `g_opt_time` | game time | 1-3 (**2**): 3, 5 or 7 minutes per half |
| `g_opt_mono` | sound | **0 stereo**, 1 mono |
| `g_opt_fouls_off` | fouls | **0 on**, 1 off |
| `g_opt_cards_off` | yellow cards | **0 on**, 1 off |
| `g_opt_offside_off` | offside | **0 on**, 1 off (the offside check does not read it) |
| `g_opt_vgoal` | overtime | 0 full extra time, **1 V-goal** |
| `g_opt_referee` | referee | 0 Carlos, **1 Heinz**, 2 Hasegawa, 3 random (`g_officials_kit`) |

The handicap screen sets, per team, `tm_condition` (0-4 for every player's
`obj_energy`, 5 = random), `tm_players` (players on the pitch − 7; a
sending-off takes one off and no card is given at 0) and `tm_keeper_skill`.

**Passwords.** `g_password` holds a checksum byte, a key byte and the mode's
fields, written most significant bit first from bit 16
(`password_write_bits`, `password_read_bits`). `password_seal` picks a
random key, XORs the 46 bytes after it with the key and stores the checksum
($F5 + the bytes from the key on); `password_check` verifies it and removes
the key. Each character carries 6 bits, and the number of bits entered
selects the mode: 42 championship (game level: 3 bits, then three 6-bit team
numbers), 48 International Cup, 72 its group round, 96 short league,
102 short tournament, 120 scenario, 180 International Cup finals, 264 World
Series (`password_encode_*` write them, `mode_resume_*` read them back).

**Input.** `joypad_read_all` supports up to 8 controllers through a multitap
(`g_pad_type`, `g_pad_state`). `match_players_update` merges them per team
(`g_pads_home` / `g_pads_away` controllers each, newly pressed and held
buttons in `g_pad_pressed_*` / `g_pad_held_*`) and keeps one control slot per
controller (`g_control_slots`: controlled player, buttons, pad type,
direction remap).

**Sound.** API (call through the `bra.w` table at `$1FD954`): `sound_init`,
`sound_play_music` (d0 = song), `sound_play_sfx` (d0 = effect),
`sound_update` (every frame), `sound_reset`. Work RAM is at `g_sound_ram`
($FF31A8), addressed through a6. See [Sound driver](#sound-driver).

## Sound driver

Everything runs on the 68000; the Z80 program (`z80_driver`, disassembled as
`dc.b` lines with Z80 mnemonics) only moves bytes:

* **FM and PSG.** `fm_queue_write` / `psg_queue_write` append register
  writes to buffers in driver RAM; `sound_frame` copies them to Z80 RAM
  `$0200` (YM2612 part 1), `$0300` (part 2) and `$0400` (PSG) and sets
  `$04FF`, and the Z80 writes them to the chips between two samples.
* **PCM.** Two voices (0: music and crowd, 1: commentary) are mixed in
  software by `pcm_mix`: signed 8-bit samples, summed with saturation. Each
  voice has a loop region (start, length) and an 8-bit rate step; it moves to
  the next source byte whenever its rate accumulator carries, so it plays at
  `DAC rate × step / 256`, and at the end of the region it reloads the loop
  region (length 1 = silence). `pcm_fill_buffer` mixes up to the Z80's play
  position (`$0500`) into a 400-byte ring buffer at Z80 `$0504`, which
  `pcm_copy_to_z80` fills with `movep` (every other byte). The Z80 plays one
  byte every 384 cycles: **9237 Hz on PAL, 9322 Hz on NTSC**.
* **Scripts.** All sound is made of scripts (`sound_scripts`, 1024 of them):
  a priority byte, `$FF`, then 4-byte events `[command, argument, word]`
  run once per frame by `script_run_events` through `tbl_script_commands`
  (wait, loop, goto, instrument call/return, FM patch, volume, pitch, notes
  and the PCM commands below). The first event's argument is the channel:
  0–5 FM1–6, 6–9 PSG (tone 1–3, noise), 10 PCM voice 1.
* **Effects.** `sound_play_sfx` d0 = n uses entry n of `sfx_table`:
  `[n, priority, duration, script]`, script = `$300 + n`. The effect
  replaces the channel's current sound unless that one has a higher
  priority, and is released after `duration` frames (`cmd_sustain` then
  continues, e.g. with the tail of a crowd cheer).
* **Songs.** `song_play` reads the song header (16 track → script words),
  the tempo and an order list of 6-byte entries (delay, pattern, transpose,
  volume, track; `$FF` end, `$FE` jump); patterns hold packed notes
  (`song_read_note`) that start scripts through the note queue. The
  format in full is below; `sound.json` holds every song decoded and
  `tools/songs_to_midi.py` writes them as MIDI files.

**Song format.** The music bank (`music_bank`, `$1EB45C`) starts with the
offsets of the script table, of `music_table1` and of the effect table,
then of songs 0–25. A song: 16 words, the script each track plays its
notes with (0 = none); a word table of variants (offsets from the table;
every song has one); a variant: the word offset of its pattern table (word
offsets from that table), the tempo in beats a minute, then the order
list. Time is counted in ticks of 1/24 beat: each frame adds
tempo × 96 × 256 / 240 × 16 / 60 (50 on PAL) × 16 as 16.16 to the
counters, that is tempo / 150 ticks (NTSC). An order entry is `delay.w,
pattern, transpose, volume, track`: `delay` ticks after the previous entry
the pattern starts on a free one of 16 slots (`song_find_track`) with the
entry's transpose, volume and track; pattern `$FF` ends the song, `$FE`
jumps to the order offset in its word at +4 (the loop). A pattern is a
run of packed notes, `[note, volume, duration, delay(, script)]`: note
bit 7 says the delay is a word, bit 6 that this is an instrument change
(the word after the delay is the track's new script); volume bit 7 says
the duration is a word; the duration is the note's gate in ticks, the
delay the ticks after the previous note (0 = a chord); note 0 ends the
pattern. When a note is due the slot queues it (`note_queue_push`: volume
= the note's + the entry's, 0–63; pitch = note + 35 + transpose; the
track's script), and `note_queue_run` starts the script on its channel
(`script_start`: the pitch at `$1F4` + channel, the gate at `$74` + 4 ×
channel counting down to the release flag, bit 3 of `$128` + channel).
An instrument script plays the queued pitch with `$0B` (pitch + argument),
so its MIDI number is pitch + 11 + that argument: the FM pitch table
(`cmd_0A_data2`, 96 words, block and F-number) starts at 15.5 Hz, B(−1),
and the PSG table (`cmd_0A_data`, periods) is used from pitch 6. A script
beginning with `$14` / `$16` events is a drum kit: each entry picks the
script for one pitch (`script_start_1`).

**FM patches.** `$02` sends the patch that follows: the event itself and
the 23 after it are `[02, 00, register, value]` for registers `$30`–`$8C`
(DT/MUL, TL, RS/AR, AM/D1R, D2R and SL/RR of the four operators), then
two `$22` events write `$B0` (feedback / algorithm) and `$B4` (stereo,
LFO sensitivity). `cmd_fm_patch` releases the operators first, writes the
registers for the channel (+1 / +2 within a part), and the carriers' TL
(from the algorithm in the `$B0` event) last.

**Script commands** (`tbl_script_commands`, `[command, argument,
word]`): `$00` end; `$01` wait word + 1 frames; `$02` FM patch; `$03`
loop (argument times, 0 forever) from event hi(word); `$04` continue in
script word; `$05` call instrument script word on channel argument; `$06`
return; `$07` volume = argument; `$08` volume envelope (argument step,
word target / rate); `$09` register `$B4` stereo / LFO (argument, with the
song's pan); `$0A` note at pitch argument (word = fine detune); `$0B` note
at the queued pitch + argument; `$0C` vibrato (argument, word); `$0D`
portamento over word frames; `$0E` algorithm argument, feedback hi(word);
`$0F` nothing; `$10` key on (hi(word) ≠ 0) or off, argument 1 clears the
channel's flags, `$FF` only the flags; `$11` frequency = the word; `$12`
sustain (wait for the release); `$13` loop until released; `$14` / `$16`
continue in script word when the queued pitch is below / equals the
argument; `$15` the same when the volume is below; `$17` priority =
argument; `$18` flag 2; `$19` PSG all off; `$1A` PSG noise control
argument; `$1B`–`$1E`, `$21`, `$25` PCM (below); `$1F` stereo from the
volume; `$22` write FM register hi(word) = lo(word); `$24` volume +=
argument (signed).

PCM commands: `$25` selects a set (a window of 8 entries of the sorted
sample offset list, `tbl_pcm_sets`), `$21` picks an entry for a voice,
`$1B` sets the start (entry + word), `$1C` the length, `$1D` the rate step
and `$1E` restarts the voice; without `$1E` the new region becomes the loop
that plays when the current one ends. Typical commentary line: set, bank,
start 0, length, step `$FF` (9200 Hz), key, then length 1 (stop after it).
The crowd is sample 0 played as intro `0–$63FF` looping `$2000–$63FF`,
with a rising step for a swelling cheer.

Of the 87 entries of the sample list, 22 are 1-byte placeholders. 28
commentary lines point at a placeholder or play thousands of bytes past the
end of their sample (effects `$0D`, `$10`, `$11`, `$15`–`$1B`, `$1D`, `$2B`,
`$2D`, `$2E`, `$30`, `$31`, `$34`, `$36`–`$39`, `$3B`–`$3D`, `$3F`–`$41`,
`$45`): their audio is not in this ROM, and the match code never queues
them. Crowd effects `$69` and `$6B` also run 4.6 KB past the end of
sample 1; like the lines above they are listed with `missing_sample` and
not rendered.

Commentary (`speech_queue_push` d5 = effect, played by
`speech_queue_update` every `$40` frames, 4 queued at most):

| Effect | Event | Effect | Event |
|---|---|---|---|
| `$01` / `$22` | corner kick (NTSC / PAL) | `$27` | kick-off |
| `$02` / `$23` | goal kick | `$29`, `$2A` | card shown |
| `$03` | throw in | `$2F` | goal (`$44` may precede it) |
| `$04` / `$24` | free kick | `$32` | own goal |
| `$05` / `$25` | penalty kick | `$42` | time up |
| `$06` | offside | `$13`, `$14` | match result |
| `$08` | half time | `$0E` | shot or header |
| `$21` | keeper rushes out | `$09`, `$20` | referee decisions (`match_rules_update`) |

Songs started by the game (`sound_play_music` d0, by caller): 1 and 2 in
the boot module (logo screens), 25 by most front-end screens (with
`sound_play_music_ext`), 3–9 and 11–14 by individual front-end and result
screens, 15–18 in and around the match.

## Match engine

`state_match_frame` runs, every video frame and inside the VBlank interrupt:
pads → `match_players_update` (controllers, AI scheduling, team analysis) →
`objects_update` (every object's think and update callbacks) →
`camera_update` → crowd sounds → `speech_queue_update` (commentary) →
`objects_draw` → `match_rules_update` (the referee) → `hud_update`.

**AI scheduling.** `g_ai_slot` advances `(slot + 1) & 15` every frame. A
player only runs its expensive decisions when the slot equals its
`obj_ai_slot` (its index 0–10 in the team), so each player thinks once every
16 frames; the referee uses slot 12, the linesman 13 and the goal-mouth
sprite priority of the ball slot 14. In the same slot `match_players_update`
refreshes the player's `obj_landing_dist` and the team's `tm_nearest`,
`tm_second`, `tm_front`, `tm_back` and `tm_cover` (struct `team`, instances
`g_team_home_info` / `g_team_away_info`). A port can run the same logic every
frame, but keeping the 16-frame cadence reproduces the original reaction
times.

**Players.** Player 0 is the goalkeeper (`keeper_ai`: 32 px in front of the
goal line, sliding along it with the angle to the ball; `keeper_save` when
the ball comes within $50, `keeper_rush_out` for balls played into the
area). Its movement (`keeper_update`) is a copy of the outfield state machine
with the keeper's own states: `keeper_dive` (a slow ball gets the
full-length dive in the frames of action 22, a fast one the jump of
action 21; gravity $5000 per frame NTSC, $7333 PAL), then `keeper_hold`
(turns at most 45° off the line up the pitch; pass throws, lofted or shoot
kicks from the hands; left alone it kicks after 64-191 frames one time in
four and rolls the ball out otherwise). Outfield players use `player_ai`:

1. loose ball and nearest to where it will land → `player_ai_chase_ball`;
2. opponents in possession and nearest (or second nearest, unless covering)
   → `player_ai_press`;
3. `obj_mark` set → `player_ai_mark` (man-marking);
4. otherwise go to the formation position: X = `tm_lines[obj_role]` +
   `obj_form_x` × 8 (+ $80 for roles flagged to join attacks when the team
   has the ball), Y = pitch centre + `obj_form_y` × 8 (× 10 in possession).
   Roles are 0 attack, 1 midfield, 2 defence, 3 goalkeeper. Defenders
   keep $180 px from their own goal line and forwards from the opponents'
   (unless their line is already beyond that), and nobody runs past the
   opponents' last defender (`tm_back`) minus 32 px.

With the ball the AI (`ai_carrier`) holds it for up to 12 AI turns,
dribbling straight at goal or toward the near wing, then passes (`ai_pass`,
or `ai_long_ball` ahead of the front player); challenged from the front it
passes or sidesteps (`ai_sidestep`); in the opponents' zone it runs at goal
and shoots (`ai_shoot`) when central, else crosses or passes. Each choice is
weighted by the team's five ratings (`tbl_team_ratings`), which are masks:
the choice is made when `g_random & mask` is 0, so with chance
1 / (mask + 1). Rating 0: pass rather than dribble when challenged; 1:
unused; 2: pulse dash while sidestepping; 3: run straight at goal rather
than toward the wing; 4: long ball rather than a short pass.

**Player records** (`tbl_player_data`, 12 bytes, copied to object
+$5A): bytes 0–8 are the edit screen's attributes in its order, 0–9 each:
speed (top speed from `tbl_speed_max`), dash (acceleration,
`tbl_dash_accel`), shot power, curl, intelligence, balance, jump, dribble
and stamina (frames per energy point, `tbl_stamina_drain`; energy below 2
lowers the speed used). Byte 9 is the shirt number, which also picks the
player's head graphic; byte 10 the hair graphic; byte 11 the position
(0 forward, 1 midfielder, 2 defender, 3 goalkeeper, 4 and 5 rarer
attacking and defensive types that only differ through
`tbl_position_bonus`).

Intelligence, balance and dribble decide the three contests through the
signed-byte tables after `misc_data_03AD0A` (`match.json` "contests"),
each indexed by a score × 4 plus a random 0–3 (and read past a table's
end into whatever follows): a sliding tackle on the carrier
(`player_start_sit_after_a_slide_008F16_1`) by half his (position bonus +
energy) × 2 + intelligence + dribble: −1 he rides it (a leap or a hop), 0
he loses the ball, 1 he is knocked over and fouled; a charge from the
crouched run (`player_start_chip_0070AE_1`) by the challenger's
intelligence − the carrier's + 2: −1 the challenger falls backwards, 0
the ball comes loose, 1 the carrier is knocked over and fouled; and a
goalkeeper meeting a lofted ball (`ball_check_00A67A`, one table per
keeper skill) by the kicker's balance + 4 − the keeper's energy: −1 it
gets past him, 0 it bounces back at a quarter speed, 1 he pushes it on at
half speed, 2 he holds it. A foul from a contest carries a card
(`g_foul_card` 0) only when the carrier faced within 9 of the tackler's
way, that is was taken from behind; a keeper fouled with the ball in his
hands always costs a card and, half the time, the victim an energy point
(1). Curl (byte 3) is copied with the record but no code reads it.

**Formations.** 16 (`tbl_formations`, names at `str_formation_names`):
4-5-1, 4-4-2, 4-3-3, 4-2-4, 3-5-2, 3-4-3, 3-3-4, 3-2-5, 2-5-3, 2-4-4, 2-3-5,
5-4-1, 5-3-2, 5-2-3, 1-5-4, 1-4-5. Each is 11 × (form_x, form_y, role) in
squad order; every team has its own tuned copy of its default formation
(`tbl_team_formations`).

`tbl_team_strategies` holds the eight in-match strategies (`tm_strategy`):
0 all-out attack, 1 push along centre, 2 push along wings, 3 counter attack,
4 all-out defence, 5 press up, 6 zone press, 7 offside trap. They either move
the team's three lines relative to the ball (all up, all back, forwards up
with the defence back, ...) or send a player on a run; while one runs its
label (`hud/strategies/`) is shown in the window row 22.
`tbl_kickoff_positions` gives each formation's kick-off layout.

**Rules** (`match_rules_update`).
* Clock: `g_match_clock` counts down minutes, tens, seconds and frames (60 or
  50 per second). At zero the referee waits until no restart is being taken
  and `g_restart_timer` has run out, then calls half time (restart 9) or
  time up ($A).
* Ball out of play: past a touchline → throw-in for the team that did not
  touch it last (`obj_team` of the ball). Past a goal line → goal if it is
  under the bar (z < $3C) and within 92 px of the centre line; a post
  (92–100 px) or the bar (z $3C–$40) makes it rebound; otherwise a corner if
  the defenders touched it last, else a goal kick. Own goals are detected
  from `g_last_touch`.
* Fouls: the fouler (`g_foul_player`) is only punished if the referee sees
  it: `tbl_referee_strictness[officials' kit][random & 3]`, so the four
  referees differ. A foul within $180 px of the fouler's own goal line (only
  the distance to the goal line is checked) is a penalty, otherwise a free
  kick. Whether a card follows depends on the foul, on the player's entry in
  `g_player_status` (bit 7 = already booked) and on how many squad members
  are already flagged there. The settings `g_opt_fouls_off` /
  `g_opt_cards_off` switch fouls and cards off.
* Offside: when a pass is played, the team's most advanced player
  (`tm_front`) is flagged (`g_offside_pending`) if, with 16 px of tolerance,
  they are in the opponents' half and beyond the last defender (`tm_back`),
  and the ball is behind that defender.

Restarts are scripts run by the invisible `g_director` object:

| `g_restart_type` | Script | Banner | Commentary | Position |
|---|---|---|---|---|
| 0 | `restart_throw_in` | THROW IN | 3 | 24 px outside the touchline, X clamped 128 px from the goal lines |
| 1 | `restart_goal_kick` | GOAL KICK | 2 / $23 | 128 px from the goal line, 192 px off centre |
| 2 | `restart_corner` | CORNER KICK | 1 / $22 | 8 px inside the corner |
| 3, 4 | `restart_kickoff` | — | $27 | centre spot (4 = start of the match) |
| 5 | `restart_foul` → `restart_free_kick`, or `restart_offside` | FOUL, FREE KICK / OFFSIDE | 4 / $24, 6 | where the foul or offside was |
| 6 | `restart_foul` → `restart_penalty` | FOUL, PENALTY KICK | 5 / $25 | penalty spot |
| 7 | `restart_penalty_spot` | — | — | 256 px from the goal line |
| 8 | `restart_own_goal` | OWN GOAL | $32 | — |
| 9 | `restart_half_time` | HALF TIME | 8 | — |
| $A | `restart_time_up` | TIME UP | $42 | then `match_result_banner` |
| $B | `restart_goal` | scorer's name | cheer (SFX 100) | — |

The second commentary number is the one used on PAL consoles. When a
restart starts, `tbl_restart_setup[g_restart_type]` moves both teams into
position. Every event updates `g_stats_home` / `g_stats_away` (shots, free
kicks, corners, penalties, yellow and red cards, offsides, goals), and
`g_scorers` keeps the minute, team and squad slot of every goal.

**Commentary.** `speech_queue_push` queues sample numbers (4 entries);
`speech_queue_update` plays one every $40 frames through `sound_play_sfx`.

**Controls.** `joypad_read_port` packs every pad as Up, Down, Left, Right, B,
C, A, Start (bits 0–7), plus Z, Y, X, Mode (bits 8–11) on 6-button pads.
`match_players_update` passes B, C, A and Z through the controller's button
layout (`tbl_button_layouts`, 8 selectable rows) to four logical buttons.
Presses stay pending in the control slot until an action consumes them. The
controlled player copies them, with the d-pad, into `obj_input`, and the AI
drives its players by writing the same word, so one set of action state
machines serves both:

| Logical button | With the ball | Without the ball | Ball in the air |
|---|---|---|---|
| pass `$10` | ground pass in the d-pad direction (`player_pass`) | — | header / volley pass |
| lofted `$20` | lofted pass or cross, power from how long it is held | sliding tackle | header / volley at goal |
| shoot `$100` | shot at the goal (`player_shoot`) | — | jumping header (high ball), diving header (further away), standing header or volley (low ball) |
| dash `$40` | sprint while running; stop the ball when standing | sprint | — |
| switch `$200` (Y) | — | switch player (mode per controller: nearest, or in the d-pad direction) | — |

At free kicks and corners the taker turns the aim with the d-pad and the
button picks pass, power kick or long ball (`set_piece_aim`,
`set_piece_kick`). On 3-button pads the lofted button near the opponents'
goal also counts as a long ball. Kick strength comes from the per-power
tables `tbl_kick_pass`, `tbl_kick_drive`, `tbl_kick_rising` and
`tbl_kick_lofted` (speed and vertical speed, NTSC and PAL).

**Player animations.** `players/animations.json` names all 54
`obj_action` values (`action_names`): stand, run, sprint, the pass and kick
family (14 power kick, 15 side-foot pass, 16–18 left, right and backheel,
chosen by the angle between the kick and the facing), headers (19 standing,
21 jumping, 22 diving), 20 overhead kick, 23 sliding tackle, falls,
celebrations (30–34, 53), the defensive wall (38, 50) and more.

## Data formats

**Factor 5 packed stream** (`decompress_factor5`, sega2asm `lzfactor5`):
`'P'`, version (`'1'` = 11-bit window, `'2'` = 16-bit window, `'3'` = stored),
16-bit little-endian unpacked size, then tokens: `0nnnnnnn` copies n+1 literal
bytes; `1…` copies a back-reference (v1: length = bits 6-3 + 3, distance =
bits 2-0:next byte + 1; v2: length = bits 6-0 + 4, distance = next word + 1).
Streams are byte-aligned and packed back to back.

**Resource archive** at `$05DB50`: a directory of 87 longs (offsets from the
archive start, ending with `$FFFF`), each pointing to a group. A group starts
with an offset table — longs when its first word is 0, words otherwise — whose
entries are offsets from the group start to packed streams or raw data. Groups
are padded with `$FF` to an even length. Code accesses entry *e* of group *g* as
`lea res_directory,a0 / adda.l 4*g(a0),a0 / move.w 2*e(a0),d0 / adda.l d0,a0`.

**Graphics.** Tiles are standard 4bpp Mega Drive tiles. Sprite tiles are
column-major within a sprite (a 2×4-cell sprite stores its 8 tiles column by
column). Nametable words: priority (bit 15), palette line (14-13), v-flip (12),
h-flip (11), tile (10-0). CRAM colours: `----BBB-GGG-RRR-`.

**Text.** Upper-case ASCII, digits and punctuation; `@` is the space
character, `` ` `` the apostrophe, lower case is used in scenario texts, `$FF`
ends a string (`issdeluxe.tbl`).

## Porting to Godot

`sega2asm godot issdeluxe.yaml` writes `out/godot`, a Godot 4.3+ project:

* `data/manifest.json` — every asset with its ROM address, size, compression,
  palette/tile references and the files generated for it.
* `assets/tiles/*.idx.png` — **index textures** (pixel = colour index 0–15)
  and `*.png` coloured previews. Draw index textures with
  `md/md_indexed.gdshader` and a palette texture to keep the original palette
  behaviour (team kits are palette swaps; fades are palette arithmetic —
  `MDPalette.fade_step_to_black` mirrors `fade_out_step`).
* `assets/palettes/*.pal.png` (16 × N, one row per line) and `*.json` (CRAM words).
* `assets/tilemaps/*.json` — nametables; `md/md_tilemap.gd` (`MDTilemap`)
  rebuilds them as two `TileMapLayer`s (low / high priority) with one atlas
  per palette line and flip alternatives, when the tiles and palette of the map
  are known.
* `assets/sound/*.wav`, `assets/text/*.json`.
* `md/md_asset_browser.tscn` — browse all assets with their ROM addresses
  (the main scene until the ISS extractor makes the game the main scene).

Then run the game-specific extractor, which adds `assets/iss/`:

```bash
go run ./example/issdeluxe/extract -rom "<rom>" -out example/issdeluxe/out/godot
```

* `iss/players/frames/f_XXXXXX_{r,l}.png` — all 611 player animation frames
  (right- and left-facing), assembled exactly like the game's sprite code does
  (body tiles from `res00`, head, hair and kit tiles, ground shadow). Pixels are
  CRAM indices `line*16 + colour`: body on line 0 (home kit), heads/skin on
  line 2, the shadow is line 3 colour 15. Draw them with `md_indexed.gdshader`
  (`shadow_highlight = true` turns colour 15 of line 3 into a 50 % darkening,
  like the VDP) and `palette_match.pal.png`, or swap line 0 for any team's
  kit from `kits.json`.
* `iss/players/animations.json` — 54 actions × 8 directions → frame lists,
  with each frame's origin and hardware sprite pieces (`$0210DE` table).
  Direction = `((facing + 4) & $38) >> 3` for a 0–63 facing angle.
* `iss/players/kits.json` — first/second kit palettes and head colour masks for
  all 43 teams.
* `iss/teams.json` — all 43 squads with the team name (read off the name
  plate graphics: 0 England, 1 Germany … 41 All Amer.Star, 42 the practice
  side), flag and name plate images, default formation and layout, AI
  ratings and kit-clash codes; 20 players each with name, the nine named
  attributes, shirt number, hair, position and the raw record; and the
  attribute tables (top speed, acceleration, stamina drain, position bonus).
  `iss/formations.json` has the 16 formations with their kick-off layouts.
* `iss/ball/` — the ball (`tbl_ball_anims`): 5 actions × 8 directions, each
  frame as a ball image (right / left) and a shadow image.
* `iss/npc/` — every non-player character drawn by `npc_draw`: referee and
  linesman (standing, running, flag signals, yellow and red cards, whistle),
  medics, the stretcher and the dog that runs on the pitch (it can steal the
  linesman's flag). 21 named actions × 8 directions, 178 frames, plus the four
  officials' kit variants (`kits.json`).
* `iss/flags/` — the waving corner and halfway flags (4 frames, 6 video
  frames each) and where they stand.
* `iss/stadiums/` — the 8 stadiums in snow / fine / rain weather (`g_weather`
  0–2): full renders (e.g. 2720 × 832 px, transparent pixels filled with the
  backdrop colour), 16 × 16 metatile atlases with their maps (the game's own
  streaming format), tile sheets as index images, palettes and the pitch
  bounds in pitch coordinates (`tbl_pitch_bounds`: left, right, top, bottom;
  the touchlines and goal lines).
* `iss/weather/` — the plane A snow and rain overlays: one 512 × 256 index
  image per animation state (32 for snow at 8 frames each, 16 for rain at one
  frame each), tiled over the stadium from its origin.
* `iss/hud/` — the match HUD: the window plane (`window.png`, 32 × 32
  cells), the 42 team flags and name plates, score / clock digits, the
  strategy labels (and CONFIRM), the banner font and all 17 banner
  messages (CORNER KICK, THROW IN, HALF TIME ...; `ISSHud.show_banner`),
  the replay's logo and icons, the controlled players' markers, the radar
  background and, per stadium, the pitch → radar pixel mapping and the dot
  colours (`hud.json` gives every item's cells, the pause menus' layout
  and the replay HUD's tables).
* `iss/misc/` — the small sprites: rain drops and splashes, snowflakes,
  confetti and sparkles (`particle_draw`), the landing-point marker of lofted
  kicks and the practice goal target (`misc.json` says when each is used).
* `iss/screens/` — the 57 front-end screens (menus, options, league and cup
  tables, mode title cards, game over, password), each a backdrop group
  under the screen's own group as the loader at `$01EB38` stacks them.
  They are rendered without the run-time menu cursors and sprites, and
  screen $39 is only approximate (its backdrop group 25 changes with the
  weather and renders as a flat green block). `screens.json` lists screen
  number → groups.
* `iss/sound/` — the sound: the 65 PCM samples (`samples/pcm_NN.wav`, at
  the rate the scripts mostly play them) and 65 of the 95 effects that use
  PCM (the other 30 have missing samples) rendered by a model of the
  driver's mixer (`sfx/sfx_NN.wav`, 9237 Hz;
  every commentary line, the ball kick `$4D`, the crowd loops `$62`–`$6A`,
  `$78`, `$79` with their loop points in the WAV). `sound.json` lists every
  effect (priority, duration, channel, commentary event, the PCM events
  frame by frame), the PCM sets, the music instruments that use PCM and the
  26 songs.
* `iss/sound/rendered/` (optional, see below) — all 25 songs and the 112
  valid effects rendered by running the game's own sound driver: Ogg Vorbis
  files, the VGM logs they came from and `rendered.json` (loop offsets,
  lengths; effects that hold forever are marked `held`).
* `iss/match.json` — the match engine's constants read from the ROM:
  pitch bounds per stadium, ball gravity (normal and after a high kick),
  rolling friction and bounce damping per weather, the pass, drive, rising
  and lofted kick tables with the distance each power carries, the team
  line table of `$01521E`, referee strictness, press intensity per AI level,
  the goalkeeper's dive data, the knocked-over launch, `match_simulate`'s
  strength and goals tables and the short league's fixture list.
* `iss/screens/font_large*.png`, `font_small*.png` — the front end's own
  8 × 16 and 8 × 8 fonts (`text_draw_large`, `text_draw_small`; the `_hi`
  variants are the highlighted colour).
* `iss/*.gd` — `ISSPitch` (a `TileMapLayer` building any stadium),
  `ISSWeather` (the animated overlay), `ISSFlags` (the six flags), `ISSHud`
  (flags, names, score, clock and a live radar), `ISSPlayerSprite` (animated player with
  kit swapping through the palette shader), `ISSBallSprite` (ball and shadow,
  size from the height), `ISSNPCSprite` (officials with kit variants, medics,
  dog), `ISSProjection` (pitch ↔ map coordinates, heading vectors),
  `ISSSound` (`play_sfx` per hardware channel with the driver's priority
  rule, the commentary queue `say`, `play_music` with the songs' loop
  points) and
  `iss/iss_demo.tscn`, a runnable demo: open the project in Godot 4.3+, open
  the scene and press F6 (arrows scroll, +/− change stadium, W the weather,
  K the officials' kit, B kicks the ball, G and C play commentary).

The generated project has been checked with Godot 4.3: it imports without
errors, and the demo runs headless and renders under Xvfb (OpenGL). To check
your own extraction:

```bash
godot --headless --path example/issdeluxe/out/godot --import
godot --headless --path example/issdeluxe/out/godot -s res://iss/iss_selftest.gd   # prints "iss_selftest: OK"
```

### Playing the game

The extractor makes `iss/iss_game.tscn` the project's main scene: open
`out/godot` in Godot 4.3+ and press F5. It is International Superstar Soccer
Deluxe rebuilt in GDScript on the exported data, in a 256 × 224 viewport
scaled by whole numbers:

* **Front end** (`ISSMenu`): the game's own `state_menu`, its 60 screen
  handlers (`tbl_screen_handlers`) ported routine by routine in the
  `ISSScreens*` scripts (one function per ROM routine, under its name) on a
  model of what they drew with: `ISSVdp` (VRAM, CRAM, the sprite table and
  both planes, drawn by a shader with the VDP's priority and
  shadow/highlight rules), `ISSRam` (the work RAM, which the screens, the
  competitions and the match share as in the original) and `ISSRom` (the
  data blocks and the resource archive). The main menu: *Match* (screen 1:
  open game — 1P vs COM, 1P vs 2P or COM vs COM — short league or short
  tournament), *International Cup*, *World Series*, *Password* (the
  original's passwords, `ISSPassword`), *Scenario*, *PK*, *Training* and
  *Options*
  (game level 1–5, game time 3, 5 or 7 minutes a half, sound; the rules
  screen: fouls, yellow cards, offside, V-goal or full extra time, the four
  referees). Team pages choose the sides with their flags, each side's
  formation (the team's tuned default or any of the 16), the stadium (8),
  the weather (snow, fine, rain) and the strategies on the buttons. Menu
  music is song 3.
* **Competitions** (`ISSCompetition`, the ROM's structures and fixture
  lists): the short league (6 teams, the 15 fixtures of `$05B17E`, 3 points
  a win, W / D / L / P) and short tournament (8 teams, knockout) with 1 to
  6 or 8 human teams; the International Cup (an elimination round of three
  that only the winner leaves, a group round of four whose top two go
  through, and a 16-team knockout final tournament); the World Series (the
  36 national teams play each other once in the order of `$05C7B2`, every
  game with a winner, over two seasons with home and away swapped; a side
  that wins one season meets the other season's winner in the
  Championship, winning both makes it the champion). The computer's games
  are decided by
  `match_simulate` from each team's strength (`tbl_team_strength`,
  `tbl_sim_goals`).
* **Presentations** (`ISSPresentation`, `state_screen`): before a match the
  view goes down the stadium's stand to the big screen with the two
  captains and the referee, and the home side calls heads or tails; the
  winner of the toss takes the kick-off or an end (`$1634`,
  `g_left_goal_team`). An own goal, a goal that puts a human side one up and
  a hat-trick are shown on the big screen; a won International Cup or
  World Series season ends on the trophy. The objects are the match's own
  (`ISSObjects`: players, referee, ball and coin where the game keeps them
  in RAM) and the crowd's flags and confetti.
* **Penalty shoot-out** (`ISSShootout`, `state_shootout`): each kick seen
  from behind the taker as the game draws it: the goal and stand on plane
  B, the HUD on the window plane (the flags, the names of the taker and the
  keeper with their roles and controller icons, five marks a side), the
  taker, the keeper and the 16 × 16 ball as sprites streamed into VRAM,
  snow or rain in front. The taker runs up for a low (pass) or high
  (lofted) kick, a second press during the run-up scoring its quality
  (`tbl_kick_quality`), aimed with the d-pad; the keeper steps across,
  reaches, jumps or dives low by the pad (or `shootout_keeper_ai`); the
  scoreboard flashes GOAL, the crowd roars or groans. Five kicks a side,
  then sudden death; a human side picks its next takers on the order screen
  (`$1A`) between rounds, and the result goes to the mode's own screen
  (`shootout_decided_1`). PK mode, the shoot-out after extra time and the
  competitions' knockout games use it; so does a penalty in a match: the
  view decides the kick and the keeper's save, then the match finishes it
  from the spot (`restart_setup_penalty_spot`, restart 7: the kicker the
  order screen chose walks up and kicks toward the aim, the keeper dives
  as chosen 16 frames later).
* **Boot screens** (`ISSBoot`, `main_init` / `warm_start`): the boot
  module is a small program of its own (`boot_main`: 19 objects run every
  VBlank, a DMA queue, a sprite buffer, palette fades, scroll objects and
  two raster routines) and runs here as the game runs it, on the front
  end's engine with the module's own VDP registers: the SEGA logo rippling
  under its raster routine (`boot_raster_lines`), the Konami line, spark
  and logo, Factor 5, the intro (`boot_intro`: a dozen scenes of unpacked
  pictures, animated sprites, wipes and colour cycles, under songs `$19`
  and 2) and the title (`boot_title`: the text written in, the ball, the
  logo sliding in, PRESS START, the second palette switched in by an HInt
  at line 90). Each screen's main thread is a coroutine on the VBlank, as
  the program spins on its frame counter; a button press skips a screen
  as it does there. Start on the title goes to the main menu; none to
  the attract demo (`mode_start_demo`, `warm_start_1`: a minute of a
  match between two computer teams, then the boot screens again, or the
  title again after Start). The SEGA, Konami, Factor 5 and intro screens
  match the ROM's frames pixel for pixel (`iss/iss_boot_capture.gd`
  against `tools/boot_capture.py`), the ROM pausing a few frames longer
  to unpack each picture; the title matches too, in each half with its
  palette (the harness renders a frame with one).
* **Endings**: the staff roll after the International Cup or the
  championship (screen `$33`, with its scenes of play), the scenarios'
  ending (`$26`), game over and congratulations.
* **Scenarios**: the 12 situations of `tbl_scenarios` with their stories
  (`tbl_scenario_texts`): the score, the time left in the second half, the
  stadium, the referee and the restart the human side starts with; only a
  win clears one (the port remembers which are cleared).
* **Training mode / challenge mode** (screen `$13`, under *Training*).
* **Training** (`restart_setup_practice`): pick a side, then the drills of
  the training menu (screen `$18`, with the ROM's descriptions; Start in a
  drill goes back to it) against the practice team in its second kit:
  *free* (nobody else on the pitch), *defence* (your defenders against
  three attackers, `tbl_drill_defence_attackers`), *free kick* (your
  players 5-10 against the keeper and a wall, from one of the 16 places of
  `tbl_free_kick_spots`) and *keeper* (you control
  the goalkeeper against two attackers, `tbl_drill_keeper_attackers`).
  A drill starts again 128 frames after the ball goes out or a goal, or
  once your side wins the ball (defence, keeper) or loses it (free kick).
* **Challenges** (`restart_setup_practice_target`, mode 1): enter three
  letters (screen `$14`), pick an event and a level (screen `$15`, with the
  best time and best score, starting from the ROM's records) and beat 30
  seconds: *dribble* (take the five flags), *pass* (ten different
  team-mates on the ball), *shoot*, *corner kick* and *free kick* (score,
  through the target panel for the bonus), *defence* (win the ball). After
  dribble, pass and defence a goal before the bonus runs out keeps it.
  *Your record* (screen `$17`) shows the time, time score, bonus and total
  and keeps new records (the port saves them).
* **Controls** (`ISSInput`, the 6-button pad of `joypad_read_port`): player 1
  arrows, Z X C = A B C, A S D = X Y Z, Q = Mode, Enter = Start; player 2
  I J K L, V B N, F G H, R, Backspace; or two joypads (X A B = A B C, LB Y RB
  = X Y Z, Back = Mode). Each controller's button layout
  (`tbl_button_layouts`, 24 of them) turns B, C, A and Z into pass, high
  ball, dash and shoot (by default B pass, C high ball, A dash, Z shoot); Y
  switches player, Mode + a button picks a strategy, Mode + Y takes the
  goalkeeper when he is on SEMI-AUTO or MANUAL. Every controller has the
  Change control settings: TYPE A-D (Y goes to the nearest player, the
  nearest defender, the player in the pad's direction from the ball, or
  from the controlled player), AREA A (only players on the screen) or B,
  and AUTO or MANUAL cursor change (`match_players_update`); a high ball
  goes to the player nearest where it lands and a team-mate taking the
  ball takes control (`kicker_claim`). In the menus C confirms and B
  cancels. Holding the high ball or shoot button builds the kick's power,
  the d-pad aims passes and picks the post for shots; without the ball
  pass or shoot heads a high ball. A human goalkeeper dives the pad's way
  with high ball + a direction, jumps with high ball alone and throws
  himself at the ball with shoot (`keeper_side_dive`, `keeper_dive`,
  `keeper_smother`).
* **Match engine** (`ISSMatchEngine`, `ISSTeam`, `ISSFootballer`, `ISSBall`,
  no drawing, 60 steps a second):
  - the ball's physics are `ball_update`'s, with the constants of
    `match.json` (so a pass travels as far as in the original, the ball
    stops sooner in the rain and bounces lower in the snow);
  - players run at the team's running speed (1.875 px per frame) and dash
    up to their top speed from `tbl_speed_max` with `tbl_dash_accel`, tire
    by `tbl_stamina_drain`, and play the 54 animation actions of the ROM
    (run, sprint, side-foot pass, power kick, headers, sliding tackle,
    falls, celebrations, the keeper's dive and jump);
  - humans and the AI drive the same state machines through the same
    input bits (`obj_input`); the AI thinks once every 16 frames per
    player (`g_ai_slot`) and steers every frame: the formation lines of
    `$01521E` (the ROM's table and limits), chasing the ball's landing
    point, pressing the carrier and sliding in, and with the ball dribble,
    pass, long ball, cross or shoot, weighted by the team's five ratings;
    the goalkeeper on the line from the goal centre to the ball
    32 px out, diving at shots and rushing out, holding the ball 64–191
    frames and kicking one time in four;
  - the rules of `match_rules_update`: throw-ins, goal kicks and corners by
    the last touch, goals under the bar and between the posts (the posts
    and the bar rebound), fouls seen by the referee's strictness table,
    yellow and red cards, penalties within $180 px of the goal line,
    free kicks within $280 px of it facing a wall of 3-6 defenders 192 px
    away with both sides in the places of `restart_setup_free_kick`,
    offside, half time with the ends swapped, time up with the result
    banner, the banners and commentary of each restart and the crowd;
  - open games are knockout matches (`g_knockout`): a draw goes to extra
    time (halves one `g_game_time` step shorter; with V-goal the match ends
    after the extra-time half in which a side leads) and then to the
    penalty shoot-out (below); PK mode on the main menu is a shoot-out on
    its own;
* **Strategies and substitutions**: the team page assigns four of the
  eight strategies (`tbl_team_strategies`) to dash, pass, lofted and shoot;
  in the match the strategy button (D, player 2 B, joypad LB) held with one
  of them picks it (`tm_strategy_slots`, Mode + button on a 6-button pad)
  and pressed alone switches it off. The strategies move the lines exactly
  as the ROM's routines do (all out attack and defence, counter attack,
  press up, offside trap), send a player on a run (push along the centre or
  the wings) or press harder (zone press), and their label shows in the
  HUD. Substitutions are made from the match menu at the next dead ball,
  as in the original (X, or the pause menu's EDIT SCREEN).
* **Pause menu and replay**: Start freezes the game and the pause object
  for the pad's kind opens a box in the window band in the middle of the
  screen, two lines a frame each way (`matchflow_func_018BD8`: RESUME,
  REPLAY, STRATEGY and EDIT SCREEN for a 3-button pad; `_018A7A`: RESUME
  and REPLAY for a 6-button one, whose Mode button picks strategies and X
  asks for the menu). STRATEGY takes the side's four strategy slots in
  turn, then none; the band closes before play resumes. The replay ring
  (`state_match_frame_2`) keeps the last six seconds: 45 snapshots of
  everyone's position, height and facing, the ball, the camera and who is
  controlled every 8 frames, with the animation frames of frames 2 and 6
  between them; a goal freezes it 16 frames in. REPLAY fades to the
  replay (`state_match_8`), which interpolates between snapshots in
  eighths and plays by itself to the end; A plays backwards, C forwards, B
  toggles slow motion (half speed while the direction's button is held),
  and once a button has been pressed the REPLAY logo blinks over the
  controls' icons in the top rows and only Start leaves, back to the pause
  menu (or to play after a goal). The officials are not drawn meanwhile.
* **On screen** (`ISSMatch`): the stadium, weather and flags, sprites from
  the exported frames with the teams' kits (the away side changes kit on a
  clash), the referee and linesman following play, the landing marker of
  lofted balls, `camera_update`'s lead toward the attacking goal, the HUD
  with the live radar, the banners in the band that opens in the middle of
  the screen (a line a frame to 20, `hblank_hud_split`), the name plates
  of each side's kicker (`hud_draw_clock_2`: name, role, number and cards
  in the bottom rows, the team defending the left goal on the left), the
  ring under each pad's player (`hud_update`'s marker sprites, a different
  one per controller), the strategy label as the team's display setting
  shows it (its name, CONFIRM or nothing), commentary, crowd and effects.

`iss_selftest.gd` plays a whole CPU match headless, drives a player
through the pad input, plays a level knockout match to penalties, runs a
league, a tournament, the International Cup and both paths of the World
Series, starts a scenario, sets up and replays each training drill, dives
with a human keeper, checks the free kick wall, plays each challenge to its
end, clears the dribble and checks the challenge timer and scores,
strategies and substitutions, runs the three presentations (the toss with
pad presses, a goal, the trophy) and a goal's hand-over from the match to
the big screen and back, plays a PK-mode shoot-out between two CPU sides to
its decision, takes a match's penalty through the view and back to the
spot, pauses a match on both pad kinds and takes a replay through its
controls, and starts a match in the game scene.

The front end, the presentations, the endings, the shoot-out and the
match's pause menu, replay and banners were checked against the ROM
running in `tools/md_harness.py`:
the same RAM, the same pad presses (and the same HV counter readings, which
the computer's takers and keepers use as random bits), and screenshots
compared pixel for pixel (see
[Capturing the ROM's own screens](#capturing-the-roms-own-screens)); a
ten-kick shoot-out between CPU sides gives the same kicks and the same 3-4.
The game shows a frame's VRAM, CRAM, sprite and scroll changes together one
frame later (its DMA queue runs in the next VBlank); the port shows them
together at the end of the frame. Each kick's set-up takes the ROM about 20
frames of unpacking before the fade-in; the port's is instant.

### Rendering the music and FM effects

The songs and most effects are FM and PSG. `tools/render_sound.py` renders
them by running the game's own 68000 sound driver in the Unicorn CPU
emulator, 50 times a second as the VBlank handler does, and logging what it
hands to the Z80: the YM2612 and PSG write queues and the PCM it mixes for
the DAC. The logs are written as VGM files and rendered with libvgm's
`vgm2wav`, then saved as Ogg Vorbis. Songs are rendered to the end of their
first loop, with the loop start taken from the song's order list.

```bash
pip install unicorn soundfile numpy
git clone https://github.com/ValleyBell/libvgm && cmake -S libvgm -B libvgm/build \
    -DBUILD_LIBAUDIO=OFF -DBUILD_PLAYER=OFF -DBUILD_VGM2WAV=ON && make -C libvgm/build vgm2wav
python3 example/issdeluxe/tools/render_sound.py --rom "<rom>" \
    --out example/issdeluxe/out/godot/assets/iss/sound/rendered \
    --vgm2wav libvgm/build/bin/vgm2wav
```

It takes under a minute. Song 25 is silence (the menus play it to stop the
music); effect 0 and `$6C`–`$77` are not valid scripts (the driver would run
into data) and effect `$1E` is silent. The commentary lines whose samples
are missing render as whatever data follows, so `ISSSound` skips them.
`ISSSound` prefers your own
`res://assets/iss/music/song_NN.ogg`, then the rendered files, then the
extractor's PCM renders (which keep exact loop points for the crowd).

`tools/songs_to_midi.py out/godot/assets/iss/sound/sound.json <dir>`
writes every song as a format-1 MIDI file (a track per song track, 24
ticks a beat, the header's tempo, gates as note lengths, a `loop` marker
where the song jumps back).

### Capturing the ROM's own screens

`tools/md_harness.py` is a small Mega Drive for running the game's own code
to look at what it draws: the 68000 under Unicorn, a VDP (VRAM / CRAM /
VSRAM, 68000 DMA, fill and copy, the HV counter and status, planes, window,
sprites and shadow/highlight), pads, the Z80's RAM as plain memory with the
DAC ring the PCM mixer waits on, and a silent YM2612. Frames are run line by
line (313 lines, PAL) so that HBlank interrupts and the V counter behave:
the title screen waits on a flag only the HBlank handler sets. The front-end
screens, with their run-time team photos, flags and labels, can be rendered
to PNG as a reference for the Godot screens.

```python
from md_harness import MD
md = MD(open(rom, 'rb').read())
md.boot_to_menu()                 # title, Start, main menu
menu = md.save_state()
md.goto_screen(0x03, menu)        # any front-end screen (team select here)
md.tap(0, 'right'); md.run(10)
md.screenshot('team_select.png')
```

`goto_screen` leaves the main menu as the game does (C on an item) and
replaces the next screen number during the fade; screens that read a
competition's state need it set up in RAM first.

Byte reads of the VDP ports return the word's half the address names (the
V counter at `$C00008`; the title's HInt compares it with 90), and a
longword to the data port is two words (the boot module writes its
palettes with `move.l`). Frames are rendered whole, with the VRAM, CRAM
and VSRAM as the frame left them: a raster routine's per-line scroll or a
mid-frame palette change does not show. Addresses outside the mapped
regions are what the 68000's 24-bit bus makes of them: RAM through
`$E00000-$FFFFFF` and the cartridge below `$400000` are mapped as mirrors
on first touch (the pitch drawing adds a negative word offset as a
longword), so a match runs in the harness too.

`tools/boot_capture.py <rom> <prefix> <start> <end>` saves the boot
screens' frames from power-on, and `iss/iss_boot_capture.gd` (run with
`-s` on `out/godot`) the port's, to put side by side.

Interrupts are raised by the harness, which stacks the status register
itself. Unicorn's SR register does not hold the live condition codes, and
reading it resets them, so the harness reads SR through a two-instruction
stub (`move.w sr,(addr).l`) run by the emulated CPU: otherwise a VBlank
landing between a compare and its branch could take the wrong way (the
unpacker then stopped early, and the shoot-out's team names came out as
flag tiles).

**Stadium format.** Each stadium group (`res07`–`res14`) holds a metatile map
(`width, height` in 16 × 16 metatiles, then one word per metatile), a metatile
table (four nametable words per metatile, tile numbers relative to the
stadium's first VRAM tile), 256 + 663 tiles, an 18-tile patch replacing the
snow clumps of tiles 238–255 in fine and rain weather, and one palette line
per weather (entries 6–8 for `g_weather` 0 snow, 1 fine, 2 rain).
`camera_update` streams rows and columns of cells into plane B as the camera
moves (`pitch_draw_row` / `pitch_draw_column`).

Suggested mapping of the original systems:

| Mega Drive | Godot |
|---|---|
| Game state + VBlank handler | Scene + `_physics_process` (60/50 Hz) |
| Object list and callbacks | Nodes; `update`/`think`/`draw` → `_physics_process` / `_draw` |
| Planes A/B, window | `MDTilemap` / `TileMapLayer`s, `Camera2D` for scrolling |
| Sprite attribute buffer | `Sprite2D` / `AnimatedSprite2D` with the indexed shader |
| Shadow/highlight mode | `md_indexed.gdshader` with `shadow_highlight` (line 3 colours 14/15 → 50 % white/black) |
| Plane A weather overlay | `ISSWeather`: repeating `Sprite2D` region above the players |
| CRAM + fades | Palette textures + `md_indexed.gdshader` uniforms |
| Oblique pitch projection | `screen = Vector2(x + y/2, y/2 - z)` |
| Sound driver | `ISSSound`: rendered songs and effects on one `AudioStreamPlayer` per hardware channel |

## Assembler notes

* Output targets `clownassembler` / asm68k syntax.
* The original assembler kept `ADD/SUB/AND/OR/CMP #imm,Dn` in their `<ea>,Dn`
  encodings; asm68k-style assemblers silently turn them into `ADDI/…`, so they
  are emitted through the `add_ea`, `sub_ea`, `and_ea`, `or_ea`, `cmp_ea`
  macros in `include/macros.asm` (e.g. `and_ea.w #$000F,d0`).
* Encodings no assembler can reproduce (garbage in extension words) are kept as
  `dc.w` with the instruction in a comment.

## Regenerating and improving the segment map

`issdeluxe.yaml` is generated by `generate/main.go` from a control-flow trace
and the archive structure:

```bash
go run ./example/issdeluxe/generate -rom "<rom>" -o example/issdeluxe/issdeluxe.yaml -report trace.txt
```

`trace.txt` lists code/data regions, resolved tables, cross references and
unresolved indirect jumps. To document the game further, add names and
comments to `issdeluxe_symbols.txt` (`name = $ADDRESS ; comment`) — RAM
addresses become equates, ROM addresses labels — and re-run the split. Labels
must sit on instruction, hint or segment boundaries; `sega2asm` warns otherwise.

Every routine and data block has a name. About 580 names (routines, tables
and RAM variables) are written by hand; the other 1864 come from
`tools/name_routines.py`, which works from the listing: a routine
only ever reached from one named routine (installed as its next state, called
or jumped to) is `<owner>_<n>`, or `<owner>_<action>` when it starts one of the
54 player actions; dispatch table entries are named after their slot; the
remaining shared routines are `<area>_<category>_<address>` (for example
`player_start_run_006046`, `menu_draw_01F4B2`) with their users in the comment;
data blocks are named after the routine or table that uses them. When you name
something by hand, remove the generated section at the end of the symbols
file, re-run the split and the tool, and append its output again:

```bash
python3 example/issdeluxe/tools/name_routines.py example/issdeluxe/out/asm \
    example/issdeluxe/issdeluxe_symbols.txt >> generated.txt
```

## Status and next steps

Done: full code/data separation, bit-exact rebuild, all compressed data decoded,
archive typed, core engine documented (boot, states, frame loop, objects, DMA,
sprites, fades, pads, text, sound API, resource loading), player animation
system decoded and exported (frames, animation tables, kits for 43 teams),
ball, non-player characters (officials, medics, stretcher, dog) and pitch
flags exported,
stadium format decoded and all 8 stadiums exported with a Godot builder,
weather (palettes, tile patch, animated plane A overlay) and the match's
shadow/highlight and backdrop rules reproduced in Godot. Match engine
architecture named: AI scheduler, player and goalkeeper AI, team state and
strategies, referee rules (clock, out of play, goals, fouls, offside, cards),
restart scripts, statistics and commentary. Sound driver decoded (Z80
program, software PCM mixer, script and song formats); all PCM samples and
PCM effects exported, and every song and effect rendered by running the
driver itself (`tools/render_sound.py`), all playable from Godot.

Game modes, the main menu, the password restore paths, the penalty
shoot-out state, the strategies, the small sprites and the 60 front-end
screen handlers are named, and every routine and data block now has a name
(hand-written or derived from its owner, see above).

The options, the handicap settings, the password container, the
goalkeeper's dive and distribution and the shoot-out keeper are decoded too.

The game itself runs in Godot (see [Playing the game](#playing-the-game)):
open games for one or two players or CPU against CPU, the short league and
tournament, the International Cup, the World Series, the scenarios, PK and
training, with the front end, the rules, the AI and the presentation
rebuilt on the exported data.

Open work:
1. The field layout of each mode's password and the object behind each
   remaining menu screen.
