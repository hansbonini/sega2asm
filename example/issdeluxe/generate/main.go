// Command generate builds the sega2asm segment map for
// International Superstar Soccer Deluxe (Europe) for the Sega Mega Drive.
//
//	go run ./example/issdeluxe/generate -rom <path to ROM> -o example/issdeluxe/issdeluxe.yaml
//
// It traces the 68000 code with the analysis package, carves the Factor 5
// resource archives entry by entry (typed as tiles / tilemaps / palettes)
// and describes the sound banks. The generated YAML is then refined by hand
// (names, descriptions) and fed to sega2asm.
package main

import (
	"bytes"
	"crypto/sha1"
	"flag"
	"fmt"
	"os"
	"sort"
	"strings"

	"sega2asm/analysis"
	"sega2asm/compress"
	"sega2asm/types"
)

const romSHA1 = "CCC60352B43F8C3D536267DD05A8F2C0F3B73DF6"

// ROM map (see README.md for the full description).
const (
	archiveStart = 0x05DB50 // main resource archive (87 groups)
	archiveEnd   = 0x144318
	bootStart    = 0x144318 // boot / logo module (Konami, Factor 5, ... screens)
	bootCodeEnd  = 0x14A150
	bootDataEnd  = 0x1613EC
	samplesStart = 0x1613EC // 8-bit PCM sample bank
	musicStart   = 0x1EB45C // music bank: 3 tables + 26 songs
	soundStart   = 0x1FD954 // 68000 sound driver (jump table API)
	z80Start     = 0x1FDC06 // Z80 PCM driver uploaded to $A00000
	z80End       = 0x1FDCFE
	romEnd       = 0x200000

	soundBufferCopy    = 0x1FDE08 // 32 x (movem.l, 4 x movep.l) copying the mix into Z80 RAM
	soundSeqCommands   = 0x1FEAB6 // sequence event handlers, commands $00-$25
	playerSelectByPads = 0x03DBE4 // screen_player_select: a layout routine per number of pads (0-8)
	strategyDemos      = 0x045FEC // screen_strategy: the mini pitch's demonstration of each strategy (none, 1-8)
)

var rom []byte

func be16(a uint32) uint32 { return uint32(rom[a])<<8 | uint32(rom[a+1]) }
func be32(a uint32) uint32 { return be16(a)<<16 | be16(a+2) }

func main() {
	romPath := flag.String("rom", "", "ROM file")
	out := flag.String("o", "issdeluxe.yaml", "output YAML")
	report := flag.String("report", "", "write the trace report here")
	flag.Parse()
	var err error
	if rom, err = os.ReadFile(*romPath); err != nil {
		fail(err)
	}
	if sum := fmt.Sprintf("%X", sha1.Sum(rom)); sum != romSHA1 {
		fail(fmt.Errorf("unexpected ROM SHA-1 %s (want %s)", sum, romSHA1))
	}

	res := analysis.Trace(rom, traceOptions())
	if *report != "" {
		f, err := os.Create(*report)
		if err != nil {
			fail(err)
		}
		res.WriteReport(f)
		f.Close()
	}

	segs := []types.Segment{{Name: "header", Type: "header", Start: 0, End: 0x200}}
	text := analysis.SegOptions{IsText: isText, TextEnd: 0xFF}

	o := text
	o.Prefix, o.DataPrefix, o.SubDir = "main", "main_data", "main"
	segs = append(segs, res.Segments(0x200, archiveStart, o)...)

	segs = append(segs, archiveSegments(archiveStart, archiveEnd, "res", "archive")...)

	o = text
	o.Prefix, o.DataPrefix, o.SubDir = "boot", "boot_data", "boot"
	for _, s := range res.Segments(bootStart, bootCodeEnd, o) {
		s.StructRegs = map[string]string{"a5": ""} // boot objects use another layout
		segs = append(segs, s)
	}
	segs = append(segs, bootDataSegments()...)

	segs = append(segs, soundDataSegments()...)

	o = text
	o.Prefix, o.DataPrefix, o.SubDir = "sound", "sound_data", "sound"
	for _, s := range res.Segments(soundStart, romEnd, o) {
		// The sound driver points a6 at its own RAM block and uses a5 for
		// the VDP / channel data.
		s.BaseRegs = map[string]types.HexInt{"a6": 0}
		s.StructRegs = map[string]string{"a5": ""}
		for _, a := range soundZ80Offsets {
			if a >= uint32(s.Start) && a < uint32(s.End) {
				s.Literal = append(s.Literal, types.HexInt(a))
			}
		}
		segs = append(segs, splitZ80(s)...)
	}

	sort.SliceStable(segs, func(i, j int) bool { return segs[i].Start < segs[j].Start })
	check(segs)
	if err := os.WriteFile(*out, []byte(writeYAML(segs)), 0644); err != nil {
		fail(err)
	}
	c, d, u := res.Stats()
	fmt.Fprintf(os.Stderr, "segments=%d  code=%d data=%d unknown=%d functions=%d\n", len(segs), c, d, u, len(res.Entries))
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, "generate:", err)
	os.Exit(1)
}

// soundZ80Offsets are sound driver instructions whose absolute short
// operands are Z80 RAM offsets (the FM write queues at $0200 and $0300),
// not ROM addresses.
var soundZ80Offsets = []uint32{0x1FE6D8, 0x1FE6F8}

// traceOptions returns the tracer configuration: data-only regions are
// forced so pointer candidates never land in graphics or sound data.
func traceOptions() analysis.Options {
	return analysis.Options{
		Orphans: true,
		// The sound driver's PCM buffer fill jumps into an unrolled
		// movem/movep block, and its sequence commands are dispatched
		// through a 38-entry table.
		Entries: []uint32{soundBufferCopy},
		Tables: []analysis.Table{
			{Addr: soundSeqCommands, Kind: analysis.TableLong, Count: 38},
			// screen_player_select calls one of these by the number of pads.
			{Addr: playerSelectByPads, Kind: analysis.TableLong, Count: 9},
			// screen_strategy runs one of these each frame for the strategy
			// under the cursor; each step sets the next in $177E.
			{Addr: strategyDemos, Kind: analysis.TableLong, Count: 9},
		},
		Data: []analysis.Range{
			{Start: archiveStart, End: archiveEnd},
			// Tables read through lea that decode as valid instructions.
			{Start: 0x003B92, End: 0x003BAA}, // keeper side step frames
			{Start: 0x003E74, End: 0x003E94}, // keeper roll frames
			{Start: 0x01015A, End: 0x010164}, // keeper: landing distances
			{Start: 0x018A6E, End: 0x018A7A}, // HUD: a 12-character label
			{Start: 0x01A3E8, End: 0x01A408}, // shoot-out: per-stadium values
			{Start: 0x0402FE, End: 0x04032E}, // handicap: home condition boxes
			{Start: 0x0458FA, End: 0x04590A}, // strategy screen boxes
			{Start: 0x04B858, End: 0x04B870}, // team colours: kit part marks
			{Start: 0x04D2B6, End: 0x04D2C6}, // options: stereo / mono boxes
			{Start: 0x04D84E, End: 0x04D85E}, // rules: yes / no boxes
			{Start: 0x055EA0, End: 0x055EAA}, // World Series table: a label
			{Start: bootCodeEnd, End: soundStart},
			{Start: z80Start, End: z80End},
		},
	}
}

// isText reports whether b is part of the game's text encoding: ASCII with
// '@' ($40) used as the space character.
func isText(b byte) bool { return b >= 0x20 && b <= 0x5F }

// ---------------------------------------------------------------------------
// Resource archives
// ---------------------------------------------------------------------------

// stream decodes the length of a Factor 5 "P1"/"P2"/"P3" packed entry and
// returns (compressed length, decompressed data).
func stream(a uint32) (uint32, []byte, bool) {
	if rom[a] != 'P' || (rom[a+1] != '1' && rom[a+1] != '2' && rom[a+1] != '3') {
		return 0, nil, false
	}
	size := uint32(rom[a+2]) | uint32(rom[a+3])<<8
	if rom[a+1] == '3' {
		return 4 + size, rom[a+4 : a+4+size], true
	}
	// Decompress while measuring the consumed input.
	p := a + 4
	var outLen uint32
	for outLen < size {
		b := rom[p]
		p++
		if b&0x80 != 0 {
			if rom[a+1] == '1' {
				outLen += uint32(b>>3&0xF) + 3
				p++
			} else {
				outLen += uint32(b&0x7F) + 4
				p += 2
			}
		} else {
			n := uint32(b&0x7F) + 1
			outLen += n
			p += n
		}
	}
	dec, err := compress.DecompressLZFactor5(rom[a:p])
	if err != nil {
		return 0, nil, false
	}
	return p - a, dec, true
}

// classify guesses the content of a decoded archive entry.
func classify(data []byte) string {
	n := len(data)
	if n >= 32 && n <= 256 && n%32 == 0 {
		pal := true
		for i := 0; i+1 < n; i += 2 {
			if (uint32(data[i])<<8|uint32(data[i+1]))&0xF111 != 0 {
				pal = false
				break
			}
		}
		if pal && n != 32 {
			return "palette"
		}
	}
	if n == 1024 || n == 2048 || n == 3584 || n == 4096 || n == 8192 {
		ok := true
		hi := map[uint32]bool{}
		for i := 0; i+1 < n; i += 2 {
			w := uint32(data[i])<<8 | uint32(data[i+1])
			if w&0x7FF >= 0x600 {
				ok = false
				break
			}
			hi[w>>11] = true
		}
		if ok && len(hi) <= 8 {
			return "tilemap"
		}
	}
	if n%32 == 0 && n > 0 {
		return "tiles"
	}
	return "data"
}

type group struct {
	addr, end uint32
	long      bool
	entries   []uint32
}

// parseGroup reads a group's offset table. Groups whose first word is zero
// use long offsets, all others word offsets (both relative to the group).
func parseGroup(g, end uint32) group {
	gr := group{addr: g, end: end}
	if be16(g) == 0 {
		gr.long = true
		n := be32(g) / 4
		for i := uint32(0); i < n; i++ {
			gr.entries = append(gr.entries, g+be32(g+4*i))
		}
	} else {
		n := be16(g) / 2
		for i := uint32(0); i < n; i++ {
			gr.entries = append(gr.entries, g+be16(g+2*i))
		}
	}
	return gr
}

// groupSegments carves one archive group: its offset table, every entry
// (typed by content) and any padding.
func groupSegments(gr group, name, sub string, palettes map[uint32]string) []types.Segment {
	var segs []types.Segment
	tblSize := uint32(len(gr.entries)) * 2
	format := "word"
	if gr.long {
		tblSize *= 2
		format = "long"
	}
	segs = append(segs, types.Segment{
		Name: name, Type: "table", Format: format, Relative: true,
		Start: types.HexInt(gr.addr), End: types.HexInt(gr.addr + tblSize), SubDir: sub,
	})
	uniq := map[uint32]int{}
	var addrs []uint32
	for i, e := range gr.entries {
		if _, ok := uniq[e]; !ok {
			uniq[e] = i
			addrs = append(addrs, e)
		}
	}
	sort.Slice(addrs, func(i, j int) bool { return addrs[i] < addrs[j] })
	cur := gr.addr + tblSize
	pad := func(a, b uint32) {
		if b > a {
			segs = append(segs, types.Segment{
				Name: fmt.Sprintf("%s_pad_%06X", name, a), Type: "data", Format: "byte",
				Start: types.HexInt(a), End: types.HexInt(b), SubDir: sub,
			})
		}
	}
	for k, e := range addrs {
		next := gr.end
		if k+1 < len(addrs) {
			next = addrs[k+1]
		}
		if e >= gr.end {
			continue // empty slot pointing at the group end
		}
		pad(cur, e)
		idx := uniq[e]
		seg := types.Segment{Start: types.HexInt(e), SubDir: sub}
		length, data, packed := stream(e)
		if packed {
			seg.Compression = "lzfactor5"
		} else {
			length, data = next-e, rom[e:next]
		}
		kind := classify(data)
		if len(data) == 2 && be16(e) == 0xFFFF {
			kind = "empty"
		}
		seg.End = types.HexInt(e + length)
		seg.Name = fmt.Sprintf("%s_%02d_%s", name, idx, kind)
		switch kind {
		case "tiles":
			seg.Type = "gfx"
			if packed {
				seg.Type = "gfxcomp"
			}
			if p, ok := palettes[gr.addr]; ok {
				seg.Palette = p
			}
		case "tilemap":
			seg.Type = "tilemap"
			seg.Width = 64
			if len(data) == 1024 || len(data) == 2048 {
				seg.Width = 32
			}
		case "palette":
			seg.Type = "palette"
		case "empty":
			seg.Type = "data"
			seg.Format = "word"
		default:
			seg.Type = "bin"
		}
		segs = append(segs, seg)
		cur = e + length
	}
	pad(cur, gr.end)
	return segs
}

// archiveSegments carves the main resource archive: a directory of long
// offsets to 87 groups, terminated by $FFFF.
func archiveSegments(start, end uint32, prefix, sub string) []types.Segment {
	n := be32(start) / 4
	var groups []uint32
	for i := uint32(0); i < n; i++ {
		groups = append(groups, start+be32(start+4*i))
	}
	dirEnd := start + n*4
	segs := []types.Segment{
		{Name: prefix + "_directory", Type: "table", Format: "long", Relative: true,
			Start: types.HexInt(start), End: types.HexInt(dirEnd), SubDir: sub,
			Description: "Resource archive directory: offsets of the 87 resource groups"},
		{Name: prefix + "_directory_end", Type: "data", Format: "word",
			Start: types.HexInt(dirEnd), End: types.HexInt(groups[0]), SubDir: sub},
	}
	palettes := map[uint32]string{}
	for i, g := range groups {
		ge := end
		if i+1 < len(groups) {
			ge = groups[i+1]
		}
		gr := parseGroup(g, ge)
		// Colour tile sheets with the group's own palette when it has one.
		for j, e := range gr.entries {
			if l, d, ok := stream(e); ok && l > 0 && classify(d) == "palette" {
				palettes[g] = fmt.Sprintf("%s%02d_%02d_palette", prefix, i, j)
				break
			}
		}
		segs = append(segs, groupSegments(gr, fmt.Sprintf("%s%02d", prefix, i), sub, palettes)...)
	}
	return segs
}

// bootDataSegments describes the boot module's data: two palettes followed
// by five word-offset resource groups.
func bootDataSegments() []types.Segment {
	segs := []types.Segment{
		{Name: "boot_palette_a", Type: "palette", Start: 0x14A150, End: 0x14A1B0, SubDir: "boot"},
		{Name: "boot_palette_b", Type: "palette", Start: 0x14A1B0, End: 0x14A1F0, SubDir: "boot"},
	}
	groups := []uint32{0x14A1F0, 0x156CE6, 0x15B298, 0x16049A, 0x160F38, bootDataEnd}
	for i := 0; i+1 < len(groups); i++ {
		gr := parseGroup(groups[i], groups[i+1])
		segs = append(segs, groupSegments(gr, fmt.Sprintf("boot_res%d", i), "boot", map[uint32]string{})...)
	}
	return segs
}

// soundDataSegments describes the PCM sample bank and the music bank.
func soundDataSegments() []types.Segment {
	segs := []types.Segment{
		{Name: "pcm_bank", Type: "pcm", SampleRate: 9237, Signed: true, Start: samplesStart, End: musicStart, SubDir: "sound",
			Description: "Signed 8-bit PCM samples, addressed by the offset list at $1FFBD8 (9237 Hz = the DAC rate on PAL)"},
	}
	// Music bank: 29 long offsets relative to the bank start.
	n := be32(musicStart+4*3) / 4 // first song offset marks the end of the table
	offs := map[uint32]bool{}
	for i := uint32(0); i < n; i++ {
		offs[musicStart+be32(musicStart+4*i)] = true
	}
	segs = append(segs, types.Segment{
		Name: "music_bank", Type: "table", Format: "long", Relative: true,
		Start: musicStart, End: types.HexInt(musicStart + n*4), SubDir: "sound",
		Description: "Music bank: offsets of the sound script table, table 1 and the effect table (stored after the songs), then of songs 0-25",
	})
	var addrs []uint32
	for a := range offs {
		addrs = append(addrs, a)
	}
	sort.Slice(addrs, func(i, j int) bool { return addrs[i] < addrs[j] })
	cur := uint32(musicStart + n*4)
	for i, a := range addrs {
		if a > cur {
			segs = append(segs, types.Segment{Name: fmt.Sprintf("music_pad_%06X", cur), Type: "bin",
				Start: types.HexInt(cur), End: types.HexInt(a), SubDir: "sound"})
		}
		end := uint32(soundStart)
		if i+1 < len(addrs) {
			end = addrs[i+1]
		}
		name, desc := fmt.Sprintf("song_%06X", a), ""
		switch i - (len(addrs) - 3) {
		case 0:
			name, desc = "sound_scripts", "1024 long offsets (from here) of the sound scripts: [priority, $FF] then 4-byte events [command, argument, word]"
		case 1:
			name = "music_table1"
		case 2:
			// 126 effects of 6 bytes, then the script data.
			fx := a + 6*126
			segs = append(segs, types.Segment{Name: "sfx_table", Type: "bin", Start: types.HexInt(a), End: types.HexInt(fx), SubDir: "sound",
				Description: "sound_play_sfx: 126 x [id, priority, duration.w (frames until release), script.w]"})
			name, desc, a = "sound_script_data", "Sound scripts (see sound_scripts); effect n is script $300+n", fx
		}
		segs = append(segs, types.Segment{Name: name, Type: "bin", Start: types.HexInt(a), End: types.HexInt(end), SubDir: "sound", Description: desc})
		cur = end
	}
	return segs
}

// splitZ80 cuts the embedded Z80 driver out of a sound segment.
func splitZ80(s types.Segment) []types.Segment {
	st, en := uint32(s.Start), uint32(s.End)
	if !(st <= z80Start && en >= z80End) {
		return []types.Segment{s}
	}
	var out []types.Segment
	if st < z80Start {
		a := s
		a.End = z80Start
		a.Hints = clipHints(s.Hints, st, st, z80Start)
		out = append(out, a)
	}
	out = append(out, types.Segment{Name: "z80_driver", Type: "z80", Format: "bytes", Start: z80Start, End: z80End, SubDir: "sound",
		Description: "Z80 PCM driver, copied to Z80 RAM $0000 by the sound driver"})
	if en > z80End {
		b := s
		b.Name = fmt.Sprintf("%s_%06X", strings.SplitN(s.Name, "_", 2)[0], z80End)
		b.Start = z80End
		b.Hints = clipHints(s.Hints, st, z80End, en)
		out = append(out, b)
	}
	return out
}

func clipHints(hs []types.Hint, segStart, a, b uint32) []types.Hint {
	var out []types.Hint
	for _, h := range hs {
		ha := segStart + h.Offset
		he := ha + uint32(h.Length)
		if ha >= a && he <= b {
			h.Offset = ha - a
			out = append(out, h)
		}
	}
	return out
}

// check verifies that segments tile the ROM exactly.
func check(segs []types.Segment) {
	cur := uint32(0)
	for _, s := range segs {
		if uint32(s.Start) != cur {
			fail(fmt.Errorf("segment %s starts at $%06X, expected $%06X", s.Name, uint32(s.Start), cur))
		}
		cur = uint32(s.End)
	}
	if cur != romEnd {
		fail(fmt.Errorf("segments end at $%06X", cur))
	}
}

// ---------------------------------------------------------------------------
// YAML output
// ---------------------------------------------------------------------------

func writeYAML(segs []types.Segment) string {
	var b bytes.Buffer
	b.WriteString(yamlHeader)
	for _, s := range segs {
		fmt.Fprintf(&b, "\n  - name: %s\n    type: %s\n    start: 0x%06X\n    end:   0x%06X\n", s.Name, s.Type, uint32(s.Start), uint32(s.End))
		if s.SubDir != "" {
			fmt.Fprintf(&b, "    subdir: %s\n", s.SubDir)
		}
		if s.Compression != "" && s.Compression != "none" {
			fmt.Fprintf(&b, "    compression: %s\n", s.Compression)
		}
		if s.Format != "" {
			fmt.Fprintf(&b, "    format: %s\n", s.Format)
		}
		if s.Relative {
			b.WriteString("    relative: true\n")
		}
		if s.Signed && s.Type == "pcm" {
			b.WriteString("    signed: true\n")
		}
		if s.Width != 0 {
			fmt.Fprintf(&b, "    width: %d\n", s.Width)
		}
		if s.Palette != "" {
			fmt.Fprintf(&b, "    palette: %s\n", s.Palette)
		}
		for _, k := range []string{"a0", "a1", "a2", "a3", "a4", "a5", "a6"} {
			if v, ok := s.BaseRegs[k]; ok {
				fmt.Fprintf(&b, "    base_regs: {%s: 0x%X}\n", k, uint32(v))
			}
		}
		if len(s.Literal) > 0 {
			var ls []string
			for _, a := range s.Literal {
				ls = append(ls, fmt.Sprintf("0x%06X", uint32(a)))
			}
			fmt.Fprintf(&b, "    literal: [%s]\n", strings.Join(ls, ", "))
		}
		if v, ok := s.StructRegs["a5"]; ok {
			fmt.Fprintf(&b, "    struct_regs: {a5: %q}\n", v)
		}
		if s.SampleRate != 0 {
			fmt.Fprintf(&b, "    sample_rate: %d\n", s.SampleRate)
		}
		if s.Description != "" {
			fmt.Fprintf(&b, "    description: %q\n", s.Description)
		}
		if len(s.Hints) > 0 {
			b.WriteString("    hints:\n")
			for _, h := range s.Hints {
				fmt.Fprintf(&b, "      - {offset: 0x%04X, type: %s, length: %d", h.Offset, h.Type, h.Length)
				if h.Base != 0 {
					fmt.Fprintf(&b, ", base: 0x%06X", uint32(h.Base))
				}
				b.WriteString("}\n")
			}
		}
	}
	return b.String()
}

const yamlHeader = `name: issdeluxe
# International Superstar Soccer Deluxe (Europe) — Sega Mega Drive
# (C) 1996 Konami, developed by Factor 5. Serial GM T-95196-50, 16 Mbit.
#
# Generated by example/issdeluxe/generate, then refined by hand.
# See example/issdeluxe/README.md for the ROM map and how to build.
sha1: "CCC60352B43F8C3D536267DD05A8F2C0F3B73DF6"

options:
  platform: genesis
  region: pal
  basename: issdeluxe
  base_path: ./out
  target_path: "./International Superstar Soccer Deluxe (Europe).md"
  asm_path: asm
  asset_path: assets
  build_path: build
  symbols_path: ./issdeluxe_symbols.txt
  charmap_path: ./issdeluxe.tbl
  header_output: true
  heuristics: false          # segment map comes from a control-flow trace
  base_regs:
    a6: 0xFF0000             # the game keeps its globals block in a6
  struct_regs:
    a5: obj                  # a5 is the current object in the main program

# Object layout (players, ball, menu widgets and palette fades all share the
# list header and callbacks; the other fields are those of pitch objects).
structs:
  obj:
    - {offset: 0x00, name: obj_next, comment: "Next object in its list (-1 = end)"}
    - {offset: 0x04, name: obj_prev, comment: "Previous object (-1 = head)"}
    - {offset: 0x08, name: obj_owner, comment: "Long: ball: player in possession (-1 = loose)"}
    - {offset: 0x0C, name: obj_state, comment: "Byte: ball: possession state ($FF = loose)"}
    - {offset: 0x0D, name: obj_ai_slot, comment: "Byte: player index 0-10; its AI runs when g_ai_slot equals it"}
    - {offset: 0x0E, name: obj_visible, comment: "Byte: 1 = on screen, $FF = culled (set by objects_draw)"}
    - {offset: 0x10, name: obj_x, comment: "Word: pitch X"}
    - {offset: 0x14, name: obj_y, comment: "Word: pitch Y, also the depth-sort key"}
    - {offset: 0x18, name: obj_z, comment: "Word: height above the pitch"}
    - {offset: 0x1C, name: obj_screen_x, comment: "Word: screen X = x + y/2 - hscroll"}
    - {offset: 0x1E, name: obj_screen_y, comment: "Word: screen Y = y/2 - z - vscroll"}
    - {offset: 0x20, name: obj_vel_x, comment: "Long: X velocity (16.16), from velocity_from_heading"}
    - {offset: 0x24, name: obj_vel_y, comment: "Long: Y velocity (16.16), subtracted from obj_y"}
    - {offset: 0x28, name: obj_target_x, comment: "Word: point the object is steering to"}
    - {offset: 0x2A, name: obj_target_y, comment: "Word"}
    - {offset: 0x2E, name: obj_ball_dist, comment: "Word: distance to the ball (|dx| + |dy|, $7FFF = far)"}
    - {offset: 0x30, name: obj_landing_dist, comment: "Word: distance to where the ball will land (g_ball+obj_target_x/y)"}
    - {offset: 0x32, name: obj_attr, comment: "Word: offset into the sprite attribute tables (palette line)"}
    - {offset: 0x34, name: obj_update, comment: "Long: update callback (-1 = none)"}
    - {offset: 0x38, name: obj_think, comment: "Long: think / steering callback run before obj_update"}
    - {offset: 0x3C, name: obj_travel, comment: "Long: remaining distance to the target (16.16)"}
    - {offset: 0x3E, name: obj_kick_request, comment: "Word: set pieces: button(s) that started the kick (AI: 1 once aimed)"}
    - {offset: 0x40, name: obj_kick_power, comment: "Word: kick power 4-15 while the button is held (AI states use it as a timer)"}
    - {offset: 0x42, name: obj_aim, comment: "Word: set pieces: aim direction 0-63, turned with the d-pad"}
    - {offset: 0x44, name: obj_heading, comment: "Word: direction to the target (0-63)"}
    - {offset: 0x48, name: obj_input, comment: "Word: this frame's input: d-pad (bits 0-3), pass $10, lofted $20, dash $40, shoot $100, switch $200 - copied from the control slot for humans, written by the AI otherwise"}
    - {offset: 0x4A, name: obj_team, comment: "Word: 0 = home, 1 = away; ball: team that touched it last"}
    - {offset: 0x51, name: obj_role, comment: "Byte: formation role 0 attack, 1 midfield, 2 defence, 3 goalkeeper (tbl_formations); bit 7: joins attacks"}
    - {offset: 0x52, name: obj_form_x, comment: "Byte: signed X offset from the role's line (x8 pixels)"}
    - {offset: 0x53, name: obj_form_y, comment: "Byte: signed Y offset from the pitch centre (x8 defending, x10 attacking)"}
    - {offset: 0x54, name: obj_mark, comment: "Byte: index of the opponent to man-mark (negative = none)"}
    - {offset: 0x55, name: obj_off_pitch, comment: "Byte: non-zero when the player takes no part (sent off / not playing)"}
    - {offset: 0x56, name: obj_slot, comment: "Byte: squad slot (0-19)"}
    - {offset: 0x57, name: obj_energy, comment: "Byte: energy; loses a point every tbl_stamina_drain[stamina] frames of running and when fouled; below 2 it lowers the speed attribute"}
    - {offset: 0x58, name: obj_energy_timer, comment: "Word: frames until the next energy point is lost"}
    - {offset: 0x5A, name: obj_record, comment: "12 bytes: player record (tbl_player_data): speed, dash, shot power, curl, intelligence, balance, jump, dribble, stamina, number, hair, position"}
    - {offset: 0x62, name: obj_stamina, comment: "Byte: stamina (record byte 8): frames per energy point from tbl_stamina_drain"}
    - {offset: 0x63, name: obj_number, comment: "Byte: shirt number 1-20 (record byte 9): also picks the head graphic, (number-1)*$C0 into the team's head tiles"}
    - {offset: 0x64, name: obj_hair, comment: "Byte: hair graphic (record byte 10): hair*$280 into the team's hair tiles"}
    - {offset: 0x65, name: obj_position, comment: "Byte: position (record byte 11): 0 forward, 1 midfielder, 2 defender, 3 goalkeeper, 4 / 5 rarer attacking / defensive types (tbl_position_bonus)"}
    - {offset: 0x66, name: obj_draw, comment: "Long: draw callback (-1 = none)"}
    - {offset: 0x6A, name: obj_action, comment: "Word: animation action (tbl_player_anims)"}
    - {offset: 0x6C, name: obj_frame, comment: "Long: frame descriptor currently shown"}
    - {offset: 0x70, name: obj_frame_next, comment: "Long: frame waiting for its tile DMA"}
    - {offset: 0x74, name: obj_frame_dma, comment: "Long: DMA queue entry of the pending frame (-1 = none)"}
    - {offset: 0x78, name: obj_vram, comment: "Word: VRAM address of the object's tile slot"}
    - {offset: 0x7A, name: obj_anim_frame, comment: "Word: frame index within the action"}
    - {offset: 0x7E, name: obj_speed, comment: "Long: speed (16.16 pixels per frame)"}
    - {offset: 0x82, name: obj_vel_z, comment: "Long: vertical velocity (16.16), ball"}
    - {offset: 0x86, name: obj_facing, comment: "Word: facing angle 0-63 (0 = up the pitch, 16 = right)"}
    - {offset: 0x88, name: obj_kick_dir, comment: "Word: direction of the kick being taken (0-63)"}
    - {offset: 0x8A, name: obj_distance, comment: "Long: distance left in a lofted pass (16.16)"}
  # Per-team match state (home at $FF181E, away at $FF18A6).
  team:
    - {offset: 0x00, name: tm_kit_tiles, comment: "Long: kit tiles (7 per team, unpacked)"}
    - {offset: 0x04, name: tm_head_tiles, comment: "Long: head tiles recoloured with the team's head mask"}
    - {offset: 0x08, name: tm_hair_tiles, comment: "Long: hair tiles (ROM)"}
    - {offset: 0x10, name: tm_keeper_manual, comment: "Word: 2 = the pad drives the goalkeeper instead of keeper_ai (restart_setup_practice, keeper drill)"}
    - {offset: 0x12, name: tm_ai_level, comment: "Word: AI level 0-4 (CPU team: g_game_level; human team: 2); indexes the AI tables such as player_ai_press_data"}
    - {offset: 0x1E, name: tm_ratings, comment: "5 bytes: tbl_team_ratings"}
    - {offset: 0x24, name: tm_strategy, comment: "Word: strategy being applied (-1 = none): 0 all out attack, 1 push along centre, 2 push along wings, 3 counter attack, 4 all out defence, 5 press up, 6 zone press, 7 offside trap"}
    - {offset: 0x26, name: tm_strategy_run, comment: "Word: run started by strategy 1 or 2"}
    - {offset: 0x2A, name: tm_strategy_on, comment: "Word: 1 = the team's controller may pick strategies (set at match start)"}
    - {offset: 0x2C, name: tm_strategy_label, comment: "Word: label mode of the strategy window (2 = the strategy's own label)"}
    - {offset: 0x2E, name: tm_strategy_slots, comment: "4 words: strategies on dash, pass, lofted and shoot (Mode + that button picks it; -1 = none; screen_strategy assigns them)"}
    - {offset: 0x36, name: tm_lines, comment: "3 words: X of the attack, midfield and defence lines (indexed by obj_role)"}
    - {offset: 0x5C, name: tm_formation, comment: "Word: formation 0-15 (tbl_formations: 4-5-1, 4-4-2, 4-3-3, 4-2-4, 3-5-2, 3-4-3, 3-3-4, 3-2-5, 2-5-3, 2-4-4, 2-3-5, 5-4-1, 5-3-2, 5-2-3, 1-5-4, 1-4-5)"}
    - {offset: 0x5E, name: tm_condition, comment: "Word: handicap condition 0-4 copied to every player's obj_energy, 5 = random per player"}
    - {offset: 0x60, name: tm_players, comment: "Word: players on the pitch - 7 (handicap, default 4 = 11 players); a sending-off takes one off (restart_card), and no card is given while it is 0"}
    - {offset: 0x62, name: tm_keeper_skill, comment: "Word: goalkeeper skill 0-4 (handicap; CPU team: g_game_level), read by the keeper and ball code"}
    - {offset: 0x64, name: tm_nearest, comment: "Long: player nearest to the ball's landing point"}
    - {offset: 0x68, name: tm_second, comment: "Long: second nearest player"}
    - {offset: 0x6C, name: tm_front, comment: "Long: most advanced player (offside checks)"}
    - {offset: 0x70, name: tm_back, comment: "Long: rearmost outfield player (offside line)"}
    - {offset: 0x74, name: tm_cover, comment: "Long: player covering behind the ball"}

# Objects at fixed RAM addresses: fields print as (g_ball+obj_speed-$FF0000)(a6).
instances:
  - {name: g_ball, addr: 0xFF19C0, struct: obj}
  - {name: g_referee, addr: 0xFF1A4E, struct: obj}
  - {name: g_linesman, addr: 0xFF1ADC, struct: obj}
  - {name: g_director, addr: 0xFF1932, struct: obj}
  - {name: g_team_home_info, addr: 0xFF181E, struct: team}
  - {name: g_team_away_info, addr: 0xFF18A6, struct: team}
  - {name: g_team_home_players, addr: 0xFF1B6A, struct: obj, count: 20, stride: 0x8E}
  - {name: g_team_away_players, addr: 0xFF2682, struct: obj, count: 20, stride: 0x8E}

segments:
`
