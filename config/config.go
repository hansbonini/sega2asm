// Package config handles the YAML configuration file for sega2asm.
// The format is inspired by ethteck/splat.
package config

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

// Config is the root configuration structure.
type Config struct {
	Name    string  `yaml:"name"`
	SHA1    string  `yaml:"sha1"`
	Options Options `yaml:"options"`
	// Segments can be defined inline or as structured entries
	Segments []Segment `yaml:"segments"`
}

// Options contains global options for the split operation.
type Options struct {
	Platform     string `yaml:"platform"`      // genesis, megadrive
	Basename     string `yaml:"basename"`
	BasePath     string `yaml:"base_path"`
	BuildPath    string `yaml:"build_path"`
	TargetPath   string `yaml:"target_path"`   // Path to the input ROM
	AsmPath      string `yaml:"asm_path"`
	AssetPath    string `yaml:"asset_path"`
	SrcPath      string `yaml:"src_path"`
	SymbolsPath  string `yaml:"symbols_path"`  // symbols.txt
	CharmapPath  string `yaml:"charmap_path"`  // charmap.tbl
	Region       string `yaml:"region"`        // ntsc, pal
	Endian       string `yaml:"endian"`        // big (default for Genesis)
	HeaderOutput bool   `yaml:"header_output"` // emit include directives
	IncBin       bool   `yaml:"incbin"`        // use incbin for binary segments
}

// Segment defines a single data segment in the ROM.
type Segment struct {
	Name        string `yaml:"name"`
	Type        string `yaml:"type"`        // m68k, z80, gfx, gfxcomp, pcm, psg, header, bin, text
	Start       HexInt `yaml:"start"`
	End         HexInt `yaml:"end"`
	Compression string `yaml:"compression"` // none, nemesis, kosinski, enigma
	SampleRate  int    `yaml:"sample_rate"` // for PCM segments (default 7040 for Mega Drive)
	OutputPath  string `yaml:"output"`      // custom output path override
	SubDir      string `yaml:"subdir"`      // subdirectory override
	Encoding    string `yaml:"encoding"`    // for text segments: ascii, charmap
	// Z80 address space origin (z80-type segments only).
	// Set to 0 or omit for drivers that always load at $0000 in Z80 RAM.
	// Set to the load address for overlay drivers that start at a non-zero Z80 address.
	Z80Org HexInt `yaml:"z80_org"`
	// Disassembly hints
	Hints []Hint `yaml:"hints"`
}

// Hint provides inline disassembly information for a segment.
type Hint struct {
	Offset uint32 `yaml:"offset"` // ROM offset
	Type   string `yaml:"type"`   // data_byte, data_word, data_long, code, text, skip
	Length int    `yaml:"length"` // number of bytes to treat this way
	Label  string `yaml:"label"`  // optional label name
}

// HexInt is a uint32 that can be unmarshalled from either decimal or "0x..." hex strings.
type HexInt uint32

func (h *HexInt) UnmarshalYAML(value *yaml.Node) error {
	var s string
	if err := value.Decode(&s); err == nil {
		// It's a string like "0x1A2B" or "$1A2B"
		var v uint64
		if len(s) > 0 && s[0] == '$' {
			s = "0x" + s[1:]
		}
		if _, err := fmt.Sscanf(s, "0x%X", &v); err == nil {
			*h = HexInt(v)
			return nil
		}
		if _, err := fmt.Sscanf(s, "%d", &v); err == nil {
			*h = HexInt(v)
			return nil
		}
		return fmt.Errorf("invalid hex/int value: %q", s)
	}
	// Try as integer directly
	var n int
	if err := value.Decode(&n); err != nil {
		return err
	}
	*h = HexInt(n)
	return nil
}

// Load reads and parses a YAML config file.
func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading config %q: %w", path, err)
	}

	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parsing config %q: %w", path, err)
	}

	// Apply defaults
	if cfg.Options.Platform == "" {
		cfg.Options.Platform = "genesis"
	}
	if cfg.Options.Region == "" {
		cfg.Options.Region = "ntsc"
	}
	if cfg.Options.AsmPath == "" {
		cfg.Options.AsmPath = "asm"
	}
	if cfg.Options.AssetPath == "" {
		cfg.Options.AssetPath = "assets"
	}
	if cfg.Options.BuildPath == "" {
		cfg.Options.BuildPath = "build"
	}
	if cfg.Options.BasePath == "" {
		cfg.Options.BasePath = "."
	}
	if cfg.Options.Basename == "" {
		cfg.Options.Basename = cfg.Name
	}
	if cfg.Options.SymbolsPath == "" {
		cfg.Options.SymbolsPath = "symbols.txt"
	}

	// Validate segment types and set defaults
	for i := range cfg.Segments {
		seg := &cfg.Segments[i]
		if seg.SampleRate == 0 && seg.Type == "pcm" {
			seg.SampleRate = 7040 // Default Mega Drive PCM rate
		}
		if seg.Compression == "" {
			seg.Compression = "none"
		}
	}

	return &cfg, nil
}
