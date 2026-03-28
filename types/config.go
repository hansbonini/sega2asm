package types

import (
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

// Config is the root project configuration.
type Config struct {
	Name     string          `yaml:"name"`
	SHA1     string          `yaml:"sha1"`
	Options  ConfigOptions   `yaml:"options"`
	Segments []Segment       `yaml:"segments"`
}

// ConfigOptions contains global paths and settings for the split operation.
type ConfigOptions struct {
	Platform      string `yaml:"platform"`
	Basename      string `yaml:"basename"`
	BasePath      string `yaml:"base_path"`
	BuildPath     string `yaml:"build_path"`
	TargetPath    string `yaml:"target_path"`
	AsmPath       string `yaml:"asm_path"`
	AssetPath     string `yaml:"asset_path"`
	SrcPath       string `yaml:"src_path"`
	SymbolsPath   string `yaml:"symbols_path"`
	CharmapPath   string `yaml:"charmap_path"`
	Region        string `yaml:"region"`
	Endian        string `yaml:"endian"`
	HeaderOutput  bool   `yaml:"header_output"`
	IncBin        bool   `yaml:"incbin"`
	NoSuggestions bool   `yaml:"no_suggestions"`
}

// Segment defines a single data segment in the ROM.
type Segment struct {
	Name        string `yaml:"name"`
	Type        string `yaml:"type"`
	Start       HexInt `yaml:"start"`
	End         HexInt `yaml:"end"`
	Compression string `yaml:"compression"`
	BPP         int    `yaml:"bpp"`
	SampleRate  int    `yaml:"sample_rate"`
	OutputPath  string `yaml:"output"`
	SubDir      string `yaml:"subdir"`
	Encoding    string `yaml:"encoding"`
	Z80Org      HexInt `yaml:"z80_org"`
	Hints       []Hint `yaml:"hints"`
}

// Hint provides inline disassembly information for a segment.
type Hint struct {
	Offset uint32 `yaml:"offset"`
	Type   string `yaml:"type"`
	Length int    `yaml:"length"`
	Label  string `yaml:"label"`
	Base   HexInt `yaml:"base"`
	File   string `yaml:"file"`
}

// HexInt is a uint32 that can be unmarshalled from either decimal or "0x..." hex strings.
type HexInt uint32

// LoadConfig reads and parses a YAML config file.
func LoadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading config %q: %w", path, err)
	}

	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parsing config %q: %w", path, err)
	}

	dir := filepath.Dir(path)
	resolveRel := func(p string) string {
		if p == "" || filepath.IsAbs(p) {
			return p
		}
		return filepath.Join(dir, p)
	}
	cfg.Options.TargetPath = resolveRel(cfg.Options.TargetPath)
	cfg.Options.SymbolsPath = resolveRel(cfg.Options.SymbolsPath)
	cfg.Options.CharmapPath = resolveRel(cfg.Options.CharmapPath)

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

	for i := range cfg.Segments {
		seg := &cfg.Segments[i]
		if seg.SampleRate == 0 && seg.Type == "pcm" {
			seg.SampleRate = 7040
		}
		if seg.Compression == "" {
			seg.Compression = "none"
		}
	}

	return &cfg, nil
}

func (h *HexInt) UnmarshalYAML(value *yaml.Node) error {
	var s string
	if err := value.Decode(&s); err == nil {
		v, err := ParseHex(s)
		if err != nil {
			return fmt.Errorf("invalid hex/int value: %q", s)
		}
		*h = HexInt(v)
		return nil
	}
	var n int
	if err := value.Decode(&n); err != nil {
		return err
	}
	*h = HexInt(n)
	return nil
}
