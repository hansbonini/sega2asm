package types

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// ProcessFunc is the function signature shared by all segment processors.
type ProcessFunc func(ctx *Context) (*Result, error)

// registry maps segment type names to their processor functions.
var registry = map[string]ProcessFunc{}

// Register adds a processor for the given segment type name.
func Register(name string, fn ProcessFunc) { registry[strings.ToLower(name)] = fn }

// Lookup returns the processor for the given type name, or nil.
func Lookup(name string) ProcessFunc { return registry[strings.ToLower(name)] }

// Include represents a file to be included in the main assembly output.
type Include struct {
	Path string
	Addr uint32
	Name string
}

// Result holds the output of processing a segment.
type Result struct {
	Includes  []Include
	IsBinary  bool
	Hints     []string
	LabelHits int
}

// Context provides shared dependencies for segment processing.
type Context struct {
	ROM     *ROM
	Seg     Segment
	Syms    *SymbolTable
	Charmap *CharMap

	AsmDir   string
	AssetDir string
	DryRun   bool
	Verbose  bool

	ExtraBins []Include

	// Labels is the global label table (nil when unavailable).
	Labels *Labels
	// Config is the whole project configuration.
	Config *Config
	// BaseDir is the directory the assembler runs from; include and incbin
	// paths are written relative to it.
	BaseDir string
	// Assets holds decoded segment data by segment name (for cross-segment
	// rendering, e.g. tilemap + tiles + palette).
	Assets map[string][]byte
	// Deferred jobs run after every segment has been processed (rendering
	// that depends on other segments' decoded data).
	Deferred *[]func()

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

// ROMData returns the ROM bytes for the current segment, clamped to ROM size.
func (ctx *Context) ROMData() []byte {
	return ctx.ROM.Slice(ctx.Start(), ctx.End())
}

// Start returns the segment start address.
func (ctx *Context) Start() uint32 { return uint32(ctx.Seg.Start) }

// End returns the segment end address, clamped to ROM size.
func (ctx *Context) End() uint32 {
	end := uint32(ctx.Seg.End)
	if int(end) > ctx.ROM.Size {
		end = uint32(ctx.ROM.Size)
	}
	return end
}

// RelPath returns p relative to the assembler base directory, using forward
// slashes, so generated include/incbin paths are portable.
func (ctx *Context) RelPath(p string) string {
	if ctx.BaseDir == "" {
		return filepath.ToSlash(p)
	}
	if r, err := filepath.Rel(ctx.BaseDir, p); err == nil {
		return filepath.ToSlash(r)
	}
	return filepath.ToSlash(p)
}

// Defer schedules fn to run after all segments are processed; when no
// deferred queue exists it runs immediately.
func (ctx *Context) Defer(fn func()) {
	if ctx.Deferred == nil {
		fn()
		return
	}
	*ctx.Deferred = append(*ctx.Deferred, fn)
}
