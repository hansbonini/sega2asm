package types

import (
	"fmt"
	"image"
	"image/color"
	"image/png"
	"os"
)

// TileDecoder decodes raw tile bytes for a specific bit depth.
type TileDecoder interface {
	BPP() int
	BytesPerTile() int
	DefaultPalette() []color.RGBA
	Decode(tile []byte, setPixel func(col, row, colorIdx int))
}

// gfxDecoders maps BPP → TileDecoder implementation.
var gfxDecoders = map[int]TileDecoder{}

// RegisterGfxDecoder registers a tile decoder for a given BPP.
func RegisterGfxDecoder(d TileDecoder) { gfxDecoders[d.BPP()] = d }

func gfxDecoder(bpp int) TileDecoder {
	if d, ok := gfxDecoders[bpp]; ok {
		return d
	}
	return gfxDecoders[4]
}

// GfxOptions controls graphics dump behaviour.
type GfxOptions struct {
	TilesPerRow int          // tiles per row in the sheet (default 16)
	BPP         int          // bits per pixel: 1, 2, 4 (default), 8
	Palette     []color.RGBA // nil = use built-in default for the given BPP
	Scale       int          // pixel scale factor (default 1)
}

// TileCount returns the number of complete 8x8 tiles in data for the given BPP.
func TileCount(data []byte, bpp int) int {
	return len(data) / gfxDecoder(bpp).BytesPerTile()
}

// DumpTiles converts raw tile data to a PNG image and writes it to path.
func DumpTiles(data []byte, path string, opts GfxOptions) error {
	if opts.TilesPerRow <= 0 {
		opts.TilesPerRow = 16
	}
	if opts.Scale <= 0 {
		opts.Scale = 1
	}
	if opts.BPP == 0 {
		opts.BPP = 4
	}

	dec := gfxDecoder(opts.BPP)
	pal := opts.Palette
	if pal == nil {
		pal = dec.DefaultPalette()
	}

	tb := dec.BytesPerTile()
	numTiles := len(data) / tb
	if numTiles == 0 {
		return fmt.Errorf("gfx: no complete %dbpp tiles in data (size=%d)", opts.BPP, len(data))
	}

	cols := opts.TilesPerRow
	rows := (numTiles + cols - 1) / cols
	scale := opts.Scale
	img := image.NewRGBA(image.Rect(0, 0, cols*8*scale, rows*8*scale))

	for t := 0; t < numTiles; t++ {
		ox := (t % cols) * 8 * scale
		oy := (t / cols) * 8 * scale
		tile := data[t*tb : t*tb+tb]
		dec.Decode(tile, func(col, row, idx int) {
			c := pal[idx&(len(pal)-1)]
			for sy := 0; sy < scale; sy++ {
				for sx := 0; sx < scale; sx++ {
					img.SetRGBA(ox+col*scale+sx, oy+row*scale+sy, c)
				}
			}
		})
	}

	f, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("gfx: creating %q: %w", path, err)
	}
	defer f.Close()
	return png.Encode(f, img)
}