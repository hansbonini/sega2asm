package segments

import (
	"fmt"
	"image"
	"image/color"
	"os"

	_ "sega2asm/compress"
	_ "sega2asm/gfx"
	"sega2asm/types"
)

func init() {
	Register("gfx", func(ctx *Context) (*Result, error) { return processGFX(ctx, false) })
	Register("gfxcomp", func(ctx *Context) (*Result, error) { return processGFX(ctx, true) })
	Register("palette", processPalette)
	Register("tilemap", processTilemap)
}

// decodeSegment writes the original bytes (always what gets incbin'd) and,
// for compressed segments, the decompressed data. It returns the decoded
// bytes and registers them in ctx.Assets under the segment name.
func decodeSegment(ctx *Context, compressed bool) (string, []byte, error) {
	binPath := ctx.SegPath(ctx.AssetDir, ".bin")
	if err := ctx.EnsureDir(binPath); err != nil {
		return binPath, nil, err
	}
	raw := ctx.ROMData()
	if err := os.WriteFile(binPath, raw, 0644); err != nil {
		return binPath, nil, err
	}
	data := raw
	if compressed || (ctx.Seg.Compression != "" && ctx.Seg.Compression != "none") {
		dec, err := types.Decompress(ctx.Seg.Compression, raw)
		if err != nil {
			ctx.Warn("  decompression failed (%s): %v", ctx.Seg.Compression, err)
			return binPath, nil, nil
		}
		data = dec
		if err := os.WriteFile(ctx.SegPath(ctx.AssetDir, ".decompressed.bin"), data, 0644); err != nil {
			ctx.Warn("  writing decompressed bin failed: %v", err)
		}
	}
	if ctx.Assets != nil && ctx.Seg.Name != "" {
		ctx.Assets[ctx.Seg.Name] = data
	}
	return binPath, data, nil
}

func binResult(ctx *Context, binPath string) *Result {
	return &Result{
		Includes: []Include{{Path: binPath, Addr: ctx.Start(), Name: ctx.Seg.Name}},
		IsBinary: true,
	}
}

func processGFX(ctx *Context, compressed bool) (*Result, error) {
	if ctx.DryRun {
		return binResult(ctx, ctx.SegPath(ctx.AssetDir, ".bin")), nil
	}
	binPath, data, err := decodeSegment(ctx, compressed)
	if err != nil || data == nil {
		return binResult(ctx, binPath), err
	}
	pngPath := ctx.SegPath(ctx.AssetDir, ".png")
	seg := ctx.Seg
	if seg.BPP != 0 && seg.BPP != 4 {
		opts := types.GfxOptions{TilesPerRow: 16, Scale: 1, BPP: seg.BPP}
		if err := types.DumpTiles(data, pngPath, opts); err != nil {
			ctx.Warn("  PNG render failed: %v", err)
		}
		return binResult(ctx, binPath), nil
	}
	perRow := seg.Width
	if perRow <= 0 {
		perRow = 16
	}
	render := func() {
		pal := types.GrayPalette(16)
		if seg.Palette != "" {
			if p, ok := ctx.Assets[seg.Palette]; ok {
				pal = types.PaletteLine(types.DecodePalette(p), seg.PaletteLine)
			} else {
				ctx.Warn("  %s: palette %q not found; rendering in grey", seg.Name, seg.Palette)
			}
		}
		img, err := types.TileSheet(data, perRow, pal, true)
		if err != nil {
			ctx.Warn("  %s: PNG render failed: %v", seg.Name, err)
			return
		}
		if err := types.WritePNG(pngPath, img); err != nil {
			ctx.Warn("  %s: PNG write failed: %v", seg.Name, err)
		}
	}
	if seg.Palette != "" {
		ctx.Defer(render)
	} else {
		render()
	}
	return binResult(ctx, binPath), nil
}

// processPalette decodes CRAM colours: writes a swatch PNG (16 colours per
// row), a GIMP .gpl palette and a JSON file with the raw words and RGB values.
func processPalette(ctx *Context) (*Result, error) {
	if ctx.DryRun {
		return binResult(ctx, ctx.SegPath(ctx.AssetDir, ".bin")), nil
	}
	binPath, data, err := decodeSegment(ctx, false)
	if err != nil || data == nil {
		return binResult(ctx, binPath), err
	}
	cols := types.DecodePalette(data)
	if len(cols) == 0 {
		return binResult(ctx, binPath), nil
	}
	img := newSwatch(cols)
	if err := types.WritePNG(ctx.SegPath(ctx.AssetDir, ".png"), img); err != nil {
		ctx.Warn("  palette PNG: %v", err)
	}
	gpl := "GIMP Palette\nName: " + ctx.Seg.Name + "\nColumns: 16\n#\n"
	raw := make([]string, len(cols))
	hex := make([]string, len(cols))
	for i, c := range cols {
		gpl += itoa3(c.R) + " " + itoa3(c.G) + " " + itoa3(c.B) + "\t" + types.HexColor(c) + "\n"
		raw[i] = "$" + hex4(uint16(data[i*2])<<8|uint16(data[i*2+1]))
		hex[i] = types.HexColor(c)
	}
	_ = os.WriteFile(ctx.SegPath(ctx.AssetDir, ".gpl"), []byte(gpl), 0644)
	_ = types.WriteJSON(ctx.SegPath(ctx.AssetDir, ".json"), map[string]any{
		"name": ctx.Seg.Name, "address": ctx.Start(), "colors": hex, "cram": raw,
	})
	return binResult(ctx, binPath), nil
}

// processTilemap decodes VDP nametable words. It writes a JSON description
// (width, height, raw words) and, once its tiles and palette segments are
// available, a rendered PNG.
//
//	width:     cells per row (default 64)
//	tiles:     name of the segment holding the tiles
//	tile_base: VRAM tile index of the first tile in that segment
//	palette:   name of a palette segment (up to 4 lines)
func processTilemap(ctx *Context) (*Result, error) {
	if ctx.DryRun {
		return binResult(ctx, ctx.SegPath(ctx.AssetDir, ".bin")), nil
	}
	binPath, data, err := decodeSegment(ctx, false)
	if err != nil || data == nil {
		return binResult(ctx, binPath), err
	}
	seg := ctx.Seg
	width := seg.Width
	if width <= 0 {
		width = 64
	}
	words := make([]uint16, len(data)/2)
	for i := range words {
		words[i] = uint16(data[i*2])<<8 | uint16(data[i*2+1])
	}
	_ = types.WriteJSON(ctx.SegPath(ctx.AssetDir, ".json"), map[string]any{
		"name": seg.Name, "width": width, "height": (len(words) + width - 1) / width,
		"tiles": seg.Tiles, "tile_base": seg.TileBase, "palette": seg.Palette,
		"format": "VDP nametable word: priority(15) palette(14-13) vflip(12) hflip(11) tile(10-0)",
		"words":  words,
	})
	ctx.Defer(func() {
		var tiles []byte
		if seg.Tiles != "" {
			var ok bool
			if tiles, ok = ctx.Assets[seg.Tiles]; !ok {
				ctx.Warn("  %s: tiles %q not found", seg.Name, seg.Tiles)
			}
		}
		pal := types.GrayPalette(64)
		if seg.Palette != "" {
			if p, ok := ctx.Assets[seg.Palette]; ok {
				pal = types.DecodePalette(p)
			} else {
				ctx.Warn("  %s: palette %q not found", seg.Name, seg.Palette)
			}
		}
		if tiles == nil {
			return
		}
		img, missing := types.RenderTilemap(words, width, tiles, seg.TileBase, pal)
		if missing > 0 {
			ctx.Logv("  %s: %d cells reference tiles outside %s", seg.Name, missing, seg.Tiles)
		}
		if err := types.WritePNG(ctx.SegPath(ctx.AssetDir, ".png"), img); err != nil {
			ctx.Warn("  %s: PNG write failed: %v", seg.Name, err)
		}
	})
	return binResult(ctx, binPath), nil
}

func newSwatch(cols []color.RGBA) *image.RGBA {
	rows := (len(cols) + 15) / 16
	img := image.NewRGBA(image.Rect(0, 0, 16*8, rows*8))
	for i, c := range cols {
		ox, oy := (i%16)*8, (i/16)*8
		for y := 0; y < 8; y++ {
			for x := 0; x < 8; x++ {
				img.SetRGBA(ox+x, oy+y, c)
			}
		}
	}
	return img
}

func itoa3(v uint8) string { return fmt.Sprintf("%3d", v) }
func hex4(v uint16) string { return fmt.Sprintf("%04X", v) }
