package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"gopkg.in/yaml.v3"
)

// The Godot front end (ISSMenu) runs ports of the game's own screen code on
// a small VDP model, so it needs what that code reads: the resource archive
// (every packed entry, unpacked) and the data blocks of the main program,
// addressed as in the ROM and named by the symbols file.

const mainProgramEnd = 0x05DB50 // res_directory: the archive follows the program

// The boot module (boot_main: the logo screens, the intro and the title),
// its data and its own packed resources, after the archive.
const bootStart = 0x144318
const bootEnd = 0x1613EC

// exportResources writes every resource entry: packed ones unpacked as
// res/gGG_eEE.bin (group, entry), raw ones as gGG_eEE.raw (the bytes up to
// the next entry), and res/resources.json with the entry sizes.
func exportResources(dir string) {
	must(os.MkdirAll(dir, 0755))
	type groupOut struct {
		Group   int   `json:"group"`
		Entries []int `json:"entries"`
		Sizes   []int `json:"sizes"`
		Addrs   []int `json:"addrs"`
	}
	var groups []groupOut
	total := 0
	numGroups := int(be32(resDirectory)) / 4
	// Every entry and group start, to size the raw (unpacked) entries.
	var starts []uint32
	for g := 0; g < numGroups; g++ {
		starts = append(starts, group(g))
		for e := 0; e < groupEntries(g); e++ {
			starts = append(starts, entry(g, e))
		}
	}
	starts = append(starts, uint32(len(rom)))
	sort.Slice(starts, func(i, j int) bool { return starts[i] < starts[j] })
	rawSize := func(a uint32) int {
		i := sort.Search(len(starts), func(i int) bool { return starts[i] > a })
		return int(starts[i] - a)
	}
	for g := 0; g < numGroups; g++ {
		out := groupOut{Group: g}
		for e := 0; e < groupEntries(g); e++ {
			a := entry(g, e)
			if int(a)+2 > len(rom) || be16(a) == 0xFFFF {
				continue
			}
			var b []byte
			name := fmt.Sprintf("g%02d_e%02d.bin", g, e)
			if rom[a] == 'P' {
				b = unpack(a)
			} else {
				// Raw entries are read in place by the game (palettes, tables).
				b = rom[a : int(a)+rawSize(a)]
				name = fmt.Sprintf("g%02d_e%02d.raw", g, e)
			}
			must(os.WriteFile(filepath.Join(dir, name), b, 0644))
			out.Entries = append(out.Entries, e)
			out.Sizes = append(out.Sizes, len(b))
			out.Addrs = append(out.Addrs, int(a))
			total += len(b)
		}
		if len(out.Entries) > 0 {
			groups = append(groups, out)
		}
	}
	writeJSON(filepath.Join(dir, "resources.json"), map[string]any{
		"description": "Resource entries (res_directory): gGG_eEE.bin is packed entry EE of group GG, unpacked; " +
			"gGG_eEE.raw an entry stored unpacked (read in place by the game), up to the next entry; " +
			"addrs: each entry's ROM address (where the game's pointers to it point).",
		"groups": groups,
	})
	fmt.Printf("resources: %d groups, %d KB unpacked\n", len(groups), total/1024)
}

type romBlock struct {
	Addr   int `json:"addr"`
	Offset int `json:"offset"`
	Length int `json:"length"`
}

// exportROMData writes the data blocks of the main program ($000200 to the
// archive): the hints of the code segments and the data segments of the
// segment map, and the whole boot module, as one binary (rom_data.bin)
// with an index of blocks (address, offset in the binary, length) and
// every symbol inside them.
func exportROMData(dir, yamlPath, symbolsPath string) {
	must(os.MkdirAll(dir, 0755))
	var cfg struct {
		Segments []struct {
			Name  string `yaml:"name"`
			Type  string `yaml:"type"`
			Start int    `yaml:"start"`
			End   int    `yaml:"end"`
			Hints []struct {
				Offset int    `yaml:"offset"`
				Type   string `yaml:"type"`
				Length int    `yaml:"length"`
			} `yaml:"hints"`
		} `yaml:"segments"`
	}
	b, err := os.ReadFile(yamlPath)
	must(err)
	must(yaml.Unmarshal(b, &cfg))
	var spans [][2]int
	for _, s := range cfg.Segments {
		if s.Start >= bootStart && s.End <= bootEnd {
			spans = append(spans, [2]int{s.Start, s.End})
			continue
		}
		if s.Start < 0x200 || s.Start >= mainProgramEnd {
			continue
		}
		switch s.Type {
		case "m68k":
			for _, h := range s.Hints {
				spans = append(spans, [2]int{s.Start + h.Offset, s.Start + h.Offset + h.Length})
			}
		case "data", "bin", "table":
			spans = append(spans, [2]int{s.Start, s.End})
		}
	}
	sort.Slice(spans, func(i, j int) bool { return spans[i][0] < spans[j][0] })
	// Merge touching spans into blocks.
	var blocks []romBlock
	var data []byte
	for _, sp := range spans {
		if n := len(blocks); n > 0 && blocks[n-1].Addr+blocks[n-1].Length >= sp[0] {
			last := &blocks[n-1]
			if end := sp[1]; end > last.Addr+last.Length {
				data = append(data, rom[last.Addr+last.Length:end]...)
				last.Length = end - last.Addr
			}
			continue
		}
		blocks = append(blocks, romBlock{Addr: sp[0], Offset: len(data), Length: sp[1] - sp[0]})
		data = append(data, rom[sp[0]:sp[1]]...)
	}
	inBlock := func(a int) bool {
		i := sort.Search(len(blocks), func(i int) bool { return blocks[i].Addr+blocks[i].Length > a })
		return i < len(blocks) && blocks[i].Addr <= a
	}
	symbols := map[string]int{}
	f, err := os.Open(symbolsPath)
	must(err)
	defer f.Close()
	re := regexp.MustCompile(`^(\w+)\s*=\s*\$([0-9A-Fa-f]+)`)
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	for sc.Scan() {
		m := re.FindStringSubmatch(sc.Text())
		if m == nil {
			continue
		}
		a, _ := strconv.ParseInt(m[2], 16, 64)
		if inBlock(int(a)) {
			symbols[m[1]] = int(a)
		}
	}
	must(os.WriteFile(filepath.Join(dir, "rom_data.bin"), data, 0644))
	writeJSON(filepath.Join(dir, "rom_data.json"), map[string]any{
		"description": "The data blocks of the main program as one binary: each block is ROM bytes addr .. " +
			"addr + length - 1 at offset in rom_data.bin; symbols name addresses inside them.",
		"blocks":  blocks,
		"symbols": symbols,
	})
	fmt.Printf("rom data: %d blocks, %d KB, %d symbols\n", len(blocks), len(data)/1024, len(symbols))
}

// writeRAMSymbols writes iss/iss_sym.gd: the symbols file's RAM names as
// constants (offsets from $FF0000) for the front end's ports of the game's
// code, which address RAM through ISSRam.
func writeRAMSymbols(out, symbolsPath string) {
	f, err := os.Open(symbolsPath)
	must(err)
	defer f.Close()
	re := regexp.MustCompile(`^(\w+)\s*=\s*\$00FF([0-9A-Fa-f]{4})\s*(?:;\s*(.*))?$`)
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	var b strings.Builder
	b.WriteString("class_name ISSSym\n## Generated by the extractor from issdeluxe_symbols.txt: the game's RAM\n" +
		"## variables as offsets from $FF0000 (the addresses ISSRam takes).\n\n")
	n := 0
	for sc.Scan() {
		m := re.FindStringSubmatch(sc.Text())
		if m == nil {
			continue
		}
		if c := strings.SplitN(strings.ReplaceAll(m[3], `\n`, " "), ". ", 2)[0]; c != "" {
			fmt.Fprintf(&b, "## %s\n", c)
		}
		fmt.Fprintf(&b, "const %s := 0x%s\n", m[1], strings.ToUpper(m[2]))
		n++
	}
	must(os.WriteFile(filepath.Join(out, "iss", "iss_sym.gd"), []byte(b.String()), 0644))
	fmt.Printf("ram symbols: %d (iss/iss_sym.gd)\n", n)
}
