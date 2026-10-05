// Package godot exports the assets described by a sega2asm configuration as
// a Godot 4 project: indexed tile textures plus palette textures (so palette
// swaps and fades can be reproduced with a shader), pre-coloured tile atlases
// and JSON descriptions for tilemaps, WAV files for PCM data, decoded text,
// and a manifest tying everything back to its ROM address.
package godot

import (
	"embed"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"sega2asm/types"
	"sega2asm/types/audio"
)

//go:embed templates
var templates embed.FS

// Options controls the export.
type Options struct {
	OutDir   string // Godot project directory
	ExtraDir string // optional directory copied verbatim into the project
	Title    string // project name
}

// Asset is one manifest entry.
type Asset struct {
	Name        string            `json:"name"`
	Kind        string            `json:"kind"`
	ROMStart    uint32            `json:"rom_start"`
	ROMEnd      uint32            `json:"rom_end"`
	Compression string            `json:"compression,omitempty"`
	Size        int               `json:"size"`
	Palette     string            `json:"palette,omitempty"`
	Tiles       string            `json:"tiles,omitempty"`
	Description string            `json:"description,omitempty"`
	Files       map[string]string `json:"files"`
}

type exporter struct {
	cfg     *types.Config
	rom     []byte
	cmap    *types.CharMap
	o       Options
	decoded map[string][]byte
	assets  []Asset
	warn    func(string, ...any)
}

// Export writes the Godot project.
func Export(cfg *types.Config, o Options, warn func(string, ...any)) error {
	r, err := types.LoadROM(cfg.Options.TargetPath)
	if err != nil {
		return err
	}
	cmap, err := types.LoadCharmap(cfg.Options.CharmapPath)
	if err != nil {
		return err
	}
	if o.Title == "" {
		o.Title = cfg.Name
	}
	e := &exporter{cfg: cfg, rom: r.Data, cmap: cmap, o: o, decoded: map[string][]byte{}, warn: warn}

	// Decode every asset segment first so cross references resolve.
	for _, s := range cfg.Segments {
		switch strings.ToLower(s.Type) {
		case "gfx", "gfxcomp", "palette", "tilemap":
			if d, err := e.decode(s); err == nil {
				e.decoded[s.Name] = d
			} else {
				warn("%s: %v", s.Name, err)
			}
		}
	}
	for _, s := range cfg.Segments {
		var err error
		switch strings.ToLower(s.Type) {
		case "gfx", "gfxcomp":
			err = e.tiles(s)
		case "palette":
			err = e.palette(s)
		case "tilemap":
			err = e.tilemap(s)
		case "pcm":
			err = e.pcm(s)
		case "text":
			err = e.text(s)
		}
		if err != nil {
			warn("%s: %v", s.Name, err)
		}
	}
	if err := e.writeTemplates(); err != nil {
		return err
	}
	if o.ExtraDir != "" {
		if err := copyDir(o.ExtraDir, o.OutDir); err != nil {
			return err
		}
	}
	sort.Slice(e.assets, func(i, j int) bool { return e.assets[i].ROMStart < e.assets[j].ROMStart })
	manifest := map[string]any{
		"project":   cfg.Name,
		"rom_sha1":  cfg.SHA1,
		"generator": "sega2asm godot",
		"conventions": map[string]string{
			"index_texture":   "8-bit greyscale PNG, pixel value = colour index 0-15 (0 = transparent)",
			"palette_texture": "16 x N RGBA PNG, one row per 16-colour palette line",
			"tilemap_word":    "priority(15) palette(14-13) vflip(12) hflip(11) tile(10-0)",
			"color":           "CRAM ----BBB-GGG-RRR-, 3-bit channels expanded linearly to 8 bits",
		},
		"assets": e.assets,
	}
	return writeJSON(filepath.Join(o.OutDir, "data", "manifest.json"), manifest)
}

func (e *exporter) decode(s types.Segment) ([]byte, error) {
	start, end := uint32(s.Start), uint32(s.End)
	if int(end) > len(e.rom) {
		end = uint32(len(e.rom))
	}
	raw := e.rom[start:end]
	if s.Compression != "" && s.Compression != "none" {
		return types.Decompress(s.Compression, raw)
	}
	return raw, nil
}

func (e *exporter) rel(p string) string {
	r, _ := filepath.Rel(e.o.OutDir, p)
	return "res://" + filepath.ToSlash(r)
}

func (e *exporter) add(s types.Segment, kind string, files map[string]string, extra func(*Asset)) {
	a := Asset{
		Name: s.Name, Kind: kind, ROMStart: uint32(s.Start), ROMEnd: uint32(s.End),
		Compression: s.Compression, Size: len(e.decoded[s.Name]), Description: s.Description, Files: files,
	}
	if a.Compression == "none" {
		a.Compression = ""
	}
	if extra != nil {
		extra(&a)
	}
	e.assets = append(e.assets, a)
}

func (e *exporter) dir(parts ...string) string {
	p := filepath.Join(append([]string{e.o.OutDir, "assets"}, parts...)...)
	_ = os.MkdirAll(p, 0755)
	return p
}

// paletteColors returns the colours of the palette segment called name.
func (e *exporter) paletteColors(name string) []color.RGBA {
	if d, ok := e.decoded[name]; ok {
		return types.DecodePalette(d)
	}
	return nil
}

// tiles exports a tile sheet as an index texture and a coloured preview.
func (e *exporter) tiles(s types.Segment) error {
	data := e.decoded[s.Name]
	if s.BPP != 0 && s.BPP != 4 {
		return nil
	}
	perRow := s.Width
	if perRow <= 0 {
		perRow = 16
	}
	d := e.dir("tiles", s.SubDir)
	idx, err := indexSheet(data, perRow)
	if err != nil {
		return err
	}
	idxPath := filepath.Join(d, s.Name+".idx.png")
	if err := types.WritePNG(idxPath, idx); err != nil {
		return err
	}
	pal := types.GrayPalette(16)
	if cols := e.paletteColors(s.Palette); cols != nil {
		pal = types.PaletteLine(cols, s.PaletteLine)
	}
	prev, _ := types.TileSheet(data, perRow, pal, true)
	prevPath := filepath.Join(d, s.Name+".png")
	if err := types.WritePNG(prevPath, prev); err != nil {
		return err
	}
	e.add(s, "tiles", map[string]string{"index": e.rel(idxPath), "preview": e.rel(prevPath)}, func(a *Asset) {
		a.Palette = s.Palette
	})
	return nil
}

// indexSheet renders tiles into an 8-bit greyscale image of colour indices.
func indexSheet(tiles []byte, perRow int) (*image.Gray, error) {
	n := len(tiles) / 32
	if n == 0 {
		return nil, fmt.Errorf("no complete tiles")
	}
	rows := (n + perRow - 1) / perRow
	img := image.NewGray(image.Rect(0, 0, perRow*8, rows*8))
	for t := 0; t < n; t++ {
		ox, oy := (t%perRow)*8, (t/perRow)*8
		for y := 0; y < 8; y++ {
			for x := 0; x < 8; x++ {
				b := tiles[t*32+y*4+x/2]
				v := b >> 4
				if x&1 == 1 {
					v = b & 15
				}
				img.SetGray(ox+x, oy+y, color.Gray{Y: v})
			}
		}
	}
	return img, nil
}

func (e *exporter) palette(s types.Segment) error {
	data := e.decoded[s.Name]
	cols := types.DecodePalette(data)
	if len(cols) == 0 {
		return nil
	}
	d := e.dir("palettes", s.SubDir)
	lines := (len(cols) + 15) / 16
	img := image.NewRGBA(image.Rect(0, 0, 16, lines))
	hex := make([]string, len(cols))
	cram := make([]uint16, len(cols))
	for i, c := range cols {
		img.SetRGBA(i%16, i/16, c)
		hex[i] = types.HexColor(c)
		cram[i] = uint16(data[i*2])<<8 | uint16(data[i*2+1])
	}
	texPath := filepath.Join(d, s.Name+".pal.png")
	if err := types.WritePNG(texPath, img); err != nil {
		return err
	}
	jsonPath := filepath.Join(d, s.Name+".json")
	if err := writeJSON(jsonPath, map[string]any{"name": s.Name, "colors": hex, "cram": cram, "lines": lines}); err != nil {
		return err
	}
	e.add(s, "palette", map[string]string{"texture": e.rel(texPath), "json": e.rel(jsonPath)}, nil)
	return nil
}

// tilemap exports the nametable as JSON and, when the tiles and palette are
// known, one pre-coloured atlas per palette line plus a full render.
func (e *exporter) tilemap(s types.Segment) error {
	data := e.decoded[s.Name]
	width := s.Width
	if width <= 0 {
		width = 64
	}
	words := make([]int, len(data)/2)
	raw := make([]uint16, len(data)/2)
	for i := range words {
		raw[i] = uint16(data[i*2])<<8 | uint16(data[i*2+1])
		words[i] = int(raw[i])
	}
	d := e.dir("tilemaps", s.SubDir)
	files := map[string]string{}
	doc := map[string]any{
		"name": s.Name, "width": width, "height": (len(words) + width - 1) / width,
		"tile_base": s.TileBase, "tiles": s.Tiles, "palette": s.Palette, "words": words,
	}
	tiles, haveTiles := e.decoded[s.Tiles]
	cols := e.paletteColors(s.Palette)
	if haveTiles && cols != nil {
		const perRow = 16
		var atlases []string
		for line := 0; line < 4; line++ {
			img, err := types.TileSheet(tiles, perRow, types.PaletteLine(cols, line), true)
			if err != nil {
				return err
			}
			p := filepath.Join(d, fmt.Sprintf("%s.line%d.png", s.Name, line))
			if err := types.WritePNG(p, img); err != nil {
				return err
			}
			atlases = append(atlases, e.rel(p))
		}
		doc["atlases"] = atlases
		doc["atlas_columns"] = perRow
		doc["tile_count"] = len(tiles) / 32
		render, _ := types.RenderTilemap(raw, width, tiles, s.TileBase, cols)
		rp := filepath.Join(d, s.Name+".png")
		if err := types.WritePNG(rp, render); err == nil {
			files["render"] = e.rel(rp)
		}
	}
	jp := filepath.Join(d, s.Name+".json")
	if err := writeJSON(jp, doc); err != nil {
		return err
	}
	files["json"] = e.rel(jp)
	e.add(s, "tilemap", files, func(a *Asset) { a.Tiles, a.Palette = s.Tiles, s.Palette })
	return nil
}

func (e *exporter) pcm(s types.Segment) error {
	start, end := uint32(s.Start), uint32(s.End)
	d := e.dir("sound", s.SubDir)
	p := filepath.Join(d, s.Name+".wav")
	data := e.rom[start:end]
	if s.Signed {
		data = audio.Unsigned(data)
	}
	if err := audio.WritePCMAsWAV(data, p, s.SampleRate); err != nil {
		return err
	}
	e.add(s, "pcm", map[string]string{"wav": e.rel(p)}, nil)
	return nil
}

func (e *exporter) text(s types.Segment) error {
	start, end := uint32(s.Start), uint32(s.End)
	d := e.dir("text", s.SubDir)
	var strs []string
	cur := []byte{}
	for _, b := range e.rom[start:end] {
		if b == 0xFF || b == 0x00 {
			strs = append(strs, e.cmap.DecodeAll(cur))
			cur = cur[:0]
			continue
		}
		cur = append(cur, b)
	}
	if len(cur) > 0 {
		strs = append(strs, e.cmap.DecodeAll(cur))
	}
	p := filepath.Join(d, s.Name+".json")
	if err := writeJSON(p, map[string]any{"name": s.Name, "strings": strs}); err != nil {
		return err
	}
	e.add(s, "text", map[string]string{"json": e.rel(p)}, nil)
	return nil
}

// writeTemplates copies the embedded Godot project skeleton.
func (e *exporter) writeTemplates() error {
	return fs.WalkDir(templates, "templates", func(p string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		b, err := templates.ReadFile(p)
		if err != nil {
			return err
		}
		out := filepath.Join(e.o.OutDir, filepath.FromSlash(strings.TrimPrefix(p, "templates/")))
		out = strings.TrimSuffix(out, ".tmpl")
		if strings.HasSuffix(p, ".tmpl") {
			b = []byte(strings.ReplaceAll(string(b), "{{TITLE}}", e.o.Title))
		}
		if err := os.MkdirAll(filepath.Dir(out), 0755); err != nil {
			return err
		}
		return os.WriteFile(out, b, 0644)
	})
}

func writeJSON(p string, v any) error {
	if err := os.MkdirAll(filepath.Dir(p), 0755); err != nil {
		return err
	}
	b, err := json.MarshalIndent(v, "", " ")
	if err != nil {
		return err
	}
	return os.WriteFile(p, b, 0644)
}

func copyDir(src, dst string) error {
	return filepath.WalkDir(src, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		r, _ := filepath.Rel(src, p)
		t := filepath.Join(dst, r)
		if d.IsDir() {
			return os.MkdirAll(t, 0755)
		}
		b, err := os.ReadFile(p)
		if err != nil {
			return err
		}
		return os.WriteFile(t, b, 0644)
	})
}
