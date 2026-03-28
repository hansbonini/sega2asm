// Package segments implements per-type ROM segment processors.
// Each segment type registers itself via init(), following the same
// self-registration pattern used by the compress package.
package segments

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"sega2asm/charmap"
	"sega2asm/config"
	"sega2asm/rom"
	"sega2asm/symbols"
)

// ProcessFunc is the function signature shared by all segment processors.
type ProcessFunc func(ctx *Context) (*Result, error)

// registry maps segment type names to their processor functions.
var registry = map[string]ProcessFunc{}

// Register adds a processor for the given segment type name.
func Register(name string, fn ProcessFunc) {
	registry[strings.ToLower(name)] = fn
}

// Lookup returns the processor for the given type name, or nil.
func Lookup(name string) ProcessFunc {
	return registry[strings.ToLower(name)]
}

// Include represents a file to be included in the main assembly output.
type Include struct {
	Path string // output file path
	Addr uint32 // ROM address (0 for .asm includes, seg.Start for binary includes)
	Name string // segment name, used as label for binary entries
}

// Result holds the output of processing a segment.
type Result struct {
	Includes  []Include // files produced
	IsBinary  bool      // true → incbin; false → include
	Hints     []string  // split suggestions (M68K only)
	LabelHits int       // number of symbols matched
}

// Context provides shared dependencies for segment processing.
type Context struct {
	ROM     *rom.ROM
	Seg     config.Segment
	Syms    *symbols.Table
	Charmap *charmap.Map

	AsmDir   string
	AssetDir string
	DryRun   bool
	Verbose  bool

	// ExtraBins holds pre-processed bin includes for Z80 segments.
	ExtraBins []Include

	// Logging callbacks (set by the splitter).
	Log  func(string, ...any)
	Logv func(string, ...any)
	Warn func(string, ...any)
}

// SegPath resolves the output file path for the current segment.
func (ctx *Context) SegPath(baseDir, ext string) string {
	seg := ctx.Seg
	if seg.OutputPath != "" {
		return seg.OutputPath
	}
	subdir := seg.SubDir
	if subdir == "" {
		subdir = strings.ToLower(seg.Type)
	}
	name := seg.Name
	if name == "" {
		name = fmt.Sprintf("seg_%06X", uint32(seg.Start))
	}
	return filepath.Join(baseDir, subdir, name+ext)
}

// EnsureDir creates the parent directory for a path.
func (ctx *Context) EnsureDir(path string) error {
	return os.MkdirAll(filepath.Dir(path), 0755)
}

// ROMData returns the ROM byte slice for the current segment,
// clamped to the actual ROM size.
func (ctx *Context) ROMData() []byte {
	start := uint32(ctx.Seg.Start)
	end := uint32(ctx.Seg.End)
	if int(end) > ctx.ROM.Size {
		end = uint32(ctx.ROM.Size)
	}
	return ctx.ROM.Slice(start, end)
}

// Start returns the segment start address as uint32.
func (ctx *Context) Start() uint32 { return uint32(ctx.Seg.Start) }

// End returns the segment end address as uint32, clamped to ROM size.
func (ctx *Context) End() uint32 {
	end := uint32(ctx.Seg.End)
	if int(end) > ctx.ROM.Size {
		end = uint32(ctx.ROM.Size)
	}
	return end
}
