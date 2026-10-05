package types

import (
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

// Config is the root project configuration.
type Config struct {
	Name     string                   `yaml:"name"`
	SHA1     string                   `yaml:"sha1"`
	Options  ConfigOptions            `yaml:"options"`
	Analysis AnalysisConfig           `yaml:"analysis"`
	Structs  map[string][]StructField `yaml:"structs"`
	// Instances are structures (or arrays of structures) at fixed addresses,
	// typically in RAM. Operands inside them are printed as
	// base+index*stride+field, e.g. (g_ball+obj_speed-$FF0000)(a6).
	Instances []StructInstance `yaml:"instances"`
	Segments  []Segment        `yaml:"segments"`
}

// StructInstance declares Count structures of type Struct at Addr, Stride
// bytes apart. Name must also be defined (symbols file) at Addr.
type StructInstance struct {
	Name   string `yaml:"name"`
	Addr   HexInt `yaml:"addr"`
	Struct string `yaml:"struct"`
	Count  int    `yaml:"count"`
	Stride HexInt `yaml:"stride"`
}

// StructField names one field of a structure addressed through a register
// (see ConfigOptions.StructRegs). Offsets become equates in structs.asm and
// d16(An) operands are printed as name(An).
type StructField struct {
	Offset  HexInt `yaml:"offset"`
	Name    string `yaml:"name"`
	Comment string `yaml:"comment"`
}

// AnalysisConfig steers the control-flow tracer used by "sega2asm analyze".
type AnalysisConfig struct {
	Entries  []HexInt        `yaml:"entries"`  // extra code entry points
	NoReturn []HexInt        `yaml:"noreturn"` // subroutines that never return
	CodeEnd  HexInt          `yaml:"code_end"` // no code at or above this address
	Orphans  *bool           `yaml:"orphans"`  // recover unreferenced functions (default true)
	Data     []AnalysisRange `yaml:"data"`     // forced data ranges
	Tables   []AnalysisTable `yaml:"tables"`   // manual jump / pointer tables
}

// AnalysisRange is a half-open [start, end) address range.
type AnalysisRange struct {
	Start HexInt `yaml:"start"`
	End   HexInt `yaml:"end"`
}

// AnalysisTable describes a jump or pointer table the tracer cannot infer.
type AnalysisTable struct {
	Addr  HexInt `yaml:"addr"`
	Type  string `yaml:"type"` // long | word_rel | branch
	Count int    `yaml:"count"`
	Base  HexInt `yaml:"base"` // word_rel base address
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
	// Heuristics enables the linear-sweep jump-table / dead-data heuristics
	// for m68k segments (default true). Disable it for traced segment maps.
	Heuristics *bool `yaml:"heuristics"`
	// BaseRegs declares address registers that hold a constant base address
	// in all m68k segments, e.g. {a6: 0xFF0000}. Segment values override.
	BaseRegs map[string]HexInt `yaml:"base_regs"`
	// FillGaps inserts bin segments for ROM ranges not covered by any
	// segment so the rebuilt ROM is always complete (default true).
	FillGaps *bool `yaml:"fill_gaps"`
	// StructRegs maps an address register to a structure in Structs, e.g.
	// {a5: obj}: d16(a5) operands are printed with the field names.
	StructRegs map[string]string `yaml:"struct_regs"`
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

	// m68k
	Heuristics *bool             `yaml:"heuristics"`
	BaseRegs   map[string]HexInt `yaml:"base_regs"`
	StructRegs map[string]string `yaml:"struct_regs"` // "" cancels a global entry
	// Literal lists instruction addresses whose operands stay numeric.
	Literal []HexInt `yaml:"literal"`

	// table: format long|word, relative to Base (default: segment start);
	// z80: format bytes emits dc.b lines with the disassembly as comments.
	// Signed also marks pcm samples as signed 8-bit.
	Format   string `yaml:"format"`
	Relative bool   `yaml:"relative"`
	Signed   bool   `yaml:"signed"`
	Base     HexInt `yaml:"base"`

	// gfx / tilemap / palette rendering
	Palette     string `yaml:"palette"`      // name of a palette segment used to colour PNGs
	PaletteLine int    `yaml:"palette_line"` // default palette line for gfx sheets
	Tiles       string `yaml:"tiles"`        // tilemap: name of the tile segment
	TileBase    int    `yaml:"tile_base"`    // tilemap: VRAM tile index of the first tile
	Width       int    `yaml:"width"`        // tilemap width in cells / gfx sheet tiles per row
	Description string `yaml:"description"`  // free-form note copied into outputs
}

// HeuristicsEnabled reports whether linear-sweep heuristics apply to seg.
func (c *Config) HeuristicsEnabled(seg Segment) bool {
	if seg.Heuristics != nil {
		return *seg.Heuristics
	}
	if c.Options.Heuristics != nil {
		return *c.Options.Heuristics
	}
	return true
}

// SegmentBaseRegs merges the global and per-segment base registers.
func (c *Config) SegmentBaseRegs(seg Segment) map[uint16]uint32 {
	out := map[uint16]uint32{}
	add := func(m map[string]HexInt) {
		for k, v := range m {
			if len(k) == 2 && (k[0] == 'a' || k[0] == 'A') && k[1] >= '0' && k[1] <= '7' {
				out[uint16(k[1]-'0')] = uint32(v)
			}
		}
	}
	add(c.Options.BaseRegs)
	add(seg.BaseRegs)
	for k, v := range out {
		if v == 0 { // "a6: 0" in a segment cancels a global base register
			delete(out, k)
		}
	}
	return out
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

// SegmentStructRegs resolves the structure field names for each address
// register used by seg (global struct_regs overridden per segment).
func (c *Config) SegmentStructRegs(seg Segment) map[uint16]map[int32]string {
	names := map[string]string{}
	for k, v := range c.Options.StructRegs {
		names[k] = v
	}
	for k, v := range seg.StructRegs {
		names[k] = v
	}
	out := map[uint16]map[int32]string{}
	for k, v := range names {
		if v == "" || len(k) != 2 || (k[0] != 'a' && k[0] != 'A') || k[1] < '0' || k[1] > '7' {
			continue
		}
		fields := map[int32]string{}
		for _, f := range c.Structs[v] {
			fields[int32(int16(uint16(f.Offset)))] = f.Name
		}
		if len(fields) > 0 {
			out[uint16(k[1]-'0')] = fields
		}
	}
	return out
}

// InstanceTable resolves the configured struct instances for the decoder.
func (c *Config) InstanceTable() []InstanceInfo {
	var out []InstanceInfo
	for _, in := range c.Instances {
		fields := map[int32]string{}
		for _, f := range c.Structs[in.Struct] {
			fields[int32(int16(uint16(f.Offset)))] = f.Name
		}
		n := in.Count
		if n <= 0 {
			n = 1
		}
		stride := uint32(in.Stride)
		if stride == 0 {
			max := int32(0)
			for off := range fields {
				if off >= max {
					max = off + 4
				}
			}
			stride = uint32(max)
		}
		out = append(out, InstanceInfo{Name: in.Name, Base: uint32(in.Addr), Count: n, Stride: stride, Fields: fields})
	}
	return out
}

// InstanceInfo is a resolved StructInstance.
type InstanceInfo struct {
	Name   string
	Base   uint32
	Count  int
	Stride uint32
	Fields map[int32]string
}

// Resolve returns "name+field" (or "name+$idx*stride+field") for addr when it
// is the start of a named field of one of the instances.
func ResolveInstance(ins []InstanceInfo, addr uint32) (string, bool) {
	for _, in := range ins {
		if addr < in.Base || addr >= in.Base+uint32(in.Count)*in.Stride {
			continue
		}
		rel := addr - in.Base
		idx, off := rel/in.Stride, int32(rel%in.Stride)
		f, ok := in.Fields[off]
		if !ok {
			return "", false
		}
		elem := in.Name
		if idx > 0 {
			elem = fmt.Sprintf("%s+$%X", in.Name, idx*in.Stride)
		}
		if off == 0 {
			return elem, true // start of an element: no field suffix
		}
		return elem + "+" + f, true
	}
	return "", false
}
