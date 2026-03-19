// Package gfx converts Sega Mega Drive tile graphics to PNG images.
// Supported formats: 1bpp, 2bpp, 4bpp (default), 8bpp.
package gfx

import (
	"fmt"
	"image"
	"image/color"
	"image/png"
	"os"
)

// Default palettes for each bit depth (greyscale ramps for visualization).
var defaultPalette1 = [2]color.RGBA{
	{0x00, 0x00, 0x00, 0xFF},
	{0xFF, 0xFF, 0xFF, 0xFF},
}

var defaultPalette2 = [4]color.RGBA{
	{0x00, 0x00, 0x00, 0xFF},
	{0x55, 0x55, 0x55, 0xFF},
	{0xAA, 0xAA, 0xAA, 0xFF},
	{0xFF, 0xFF, 0xFF, 0xFF},
}

var DefaultPalette = [16]color.RGBA{
	{0x00, 0x00, 0x00, 0xFF}, // 0 – black (transparent)
	{0x22, 0x22, 0x22, 0xFF}, // 1
	{0x44, 0x44, 0x44, 0xFF}, // 2
	{0x66, 0x66, 0x66, 0xFF}, // 3
	{0x88, 0x88, 0x88, 0xFF}, // 4
	{0xAA, 0xAA, 0xAA, 0xFF}, // 5
	{0xCC, 0xCC, 0xCC, 0xFF}, // 6
	{0xEE, 0xEE, 0xEE, 0xFF}, // 7
	{0x11, 0x11, 0x11, 0xFF}, // 8
	{0x33, 0x33, 0x33, 0xFF}, // 9
	{0x55, 0x55, 0x55, 0xFF}, // A
	{0x77, 0x77, 0x77, 0xFF}, // B
	{0x99, 0x99, 0x99, 0xFF}, // C
	{0xBB, 0xBB, 0xBB, 0xFF}, // D
	{0xDD, 0xDD, 0xDD, 0xFF}, // E
	{0xFF, 0xFF, 0xFF, 0xFF}, // F
}

// Options controls graphics dump behaviour.
type Options struct {
	TilesPerRow int            // tiles per row in the sheet (default 16)
	BPP         int            // bits per pixel: 1, 2, 4 (default), 8
	Palette     []color.RGBA   // nil = use built-in default for the given BPP
	Scale       int            // pixel scale factor (default 1)
}

// TileBytes returns the number of bytes per 8×8 tile for the given BPP.
func TileBytes(bpp int) int {
	switch bpp {
	case 1:
		return 8  // 64 pixels × 1 bit  = 8 bytes
	case 2:
		return 16 // 64 pixels × 2 bits = 16 bytes
	case 8:
		return 64 // 64 pixels × 8 bits = 64 bytes
	default: // 4
		return 32 // 64 pixels × 4 bits = 32 bytes
	}
}

// TileCount returns the number of complete 8×8 tiles in data for the given BPP.
func TileCount(data []byte, bpp int) int { return len(data) / TileBytes(bpp) }

// DumpTiles converts raw tile data to a PNG image and writes it to path.
// BPP defaults to 4 when opts.BPP is 0.
func DumpTiles(data []byte, path string, opts Options) error {
	if opts.TilesPerRow <= 0 {
		opts.TilesPerRow = 16
	}
	if opts.Scale <= 0 {
		opts.Scale = 1
	}
	if opts.BPP == 0 {
		opts.BPP = 4
	}

	pal := buildPalette(opts.BPP, opts.Palette)
	tileBytes := TileBytes(opts.BPP)
	numTiles := len(data) / tileBytes
	if numTiles == 0 {
		return fmt.Errorf("gfx: no complete %dbpp tiles in data (size=%d)", opts.BPP, len(data))
	}

	cols := opts.TilesPerRow
	rows := (numTiles + cols - 1) / cols
	imgW := cols * 8 * opts.Scale
	imgH := rows * 8 * opts.Scale
	img := image.NewRGBA(image.Rect(0, 0, imgW, imgH))

	for t := 0; t < numTiles; t++ {
		tileX := (t % cols) * 8 * opts.Scale
		tileY := (t / cols) * 8 * opts.Scale
		tile := data[t*tileBytes : t*tileBytes+tileBytes]
		decodeTile(img, tile, tileX, tileY, opts.BPP, opts.Scale, pal)
	}

	f, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("gfx: creating %q: %w", path, err)
	}
	defer f.Close()
	return png.Encode(f, img)
}

// decodeTile renders one 8×8 tile into img at pixel offset (ox, oy).
func decodeTile(img *image.RGBA, tile []byte, ox, oy, bpp, scale int, pal []color.RGBA) {
	setScaled := func(col, row, idx int) {
		c := pal[idx&(len(pal)-1)]
		for sy := 0; sy < scale; sy++ {
			for sx := 0; sx < scale; sx++ {
				img.SetRGBA(ox+col*scale+sx, oy+row*scale+sy, c)
			}
		}
	}

	switch bpp {
	case 1:
		// 8 bytes: each byte is one row, bit 7 = leftmost pixel.
		for row := 0; row < 8; row++ {
			b := tile[row]
			for col := 0; col < 8; col++ {
				setScaled(col, row, int((b>>(7-uint(col)))&1))
			}
		}
	case 2:
		// 16 bytes: each byte holds 4 pixels (2 bits each), MSB first.
		for row := 0; row < 8; row++ {
			for col := 0; col < 4; col++ {
				b := tile[row*2+col/2]
				shift := uint(6 - (col%2)*4)
				p0 := int((b >> shift) & 3)
				p1 := int((b >> (shift - 2)) & 3)
				setScaled(col*2, row, p0)
				setScaled(col*2+1, row, p1)
			}
		}
	case 8:
		// 64 bytes: one byte per pixel.
		for row := 0; row < 8; row++ {
			for col := 0; col < 8; col++ {
				setScaled(col, row, int(tile[row*8+col]))
			}
		}
	default: // 4bpp
		// 32 bytes: each byte holds 2 pixels (4 bits each).
		for row := 0; row < 8; row++ {
			for col := 0; col < 4; col++ {
				b := tile[row*4+col]
				setScaled(col*2, row, int((b>>4)&0x0F))
				setScaled(col*2+1, row, int(b&0x0F))
			}
		}
	}
}

// buildPalette returns the palette to use, falling back to the built-in default.
func buildPalette(bpp int, custom []color.RGBA) []color.RGBA {
	if custom != nil {
		return custom
	}
	switch bpp {
	case 1:
		s := make([]color.RGBA, 2)
		copy(s, defaultPalette1[:])
		return s
	case 2:
		s := make([]color.RGBA, 4)
		copy(s, defaultPalette2[:])
		return s
	case 8:
		s := make([]color.RGBA, 256)
		for i := range s {
			v := uint8(i)
			s[i] = color.RGBA{v, v, v, 0xFF}
		}
		return s
	default: // 4bpp
		s := make([]color.RGBA, 16)
		copy(s, DefaultPalette[:])
		return s
	}
}
