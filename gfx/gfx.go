// Package gfx converts Sega Mega Drive tile graphics to PNG images.
// Each tile is 8x8 pixels in 4bpp planar format (2 pixels per byte).
// Reference: smd_alteredbeast/tools/gfxdump/gfxdump.go
package gfx

import (
	"fmt"
	"image"
	"image/color"
	"image/png"
	"os"
)

// Default Mega Drive debug palette (greyscale ramp for visualization).
var DefaultPalette = [16]color.RGBA{
	{0x00, 0x00, 0x00, 0xFF}, // 0 – black (transparent)
	{0x22, 0x22, 0x22, 0xFF}, // 1
	{0x44, 0x44, 0x44, 0xFF}, // 2
	{0x66, 0x66, 0x66, 0xFF}, // 3
	{0x88, 0x88, 0x88, 0xFF}, // 4
	{0xAA, 0xAA, 0xAA, 0xFF}, // 5
	{0xCC, 0xCC, 0xCC, 0xFF}, // 6
	{0xEE, 0xEE, 0xEE, 0xFF}, // 7
	{0xFF, 0x00, 0x00, 0xFF}, // 8 – red accent
	{0x00, 0xFF, 0x00, 0xFF}, // 9 – green
	{0x00, 0x00, 0xFF, 0xFF}, // A – blue
	{0xFF, 0xFF, 0x00, 0xFF}, // B – yellow
	{0x00, 0xFF, 0xFF, 0xFF}, // C – cyan
	{0xFF, 0x00, 0xFF, 0xFF}, // D – magenta
	{0xFF, 0x88, 0x00, 0xFF}, // E – orange
	{0xFF, 0xFF, 0xFF, 0xFF}, // F – white
}

// Options controls graphics dump behaviour.
type Options struct {
	TilesPerRow int           // tiles per row in the sheet (default 16)
	Palette     *[16]color.RGBA
	Scale       int           // pixel scale factor (default 1)
}

// DumpTiles converts raw 4bpp tile data to a PNG image and writes it to path.
func DumpTiles(data []byte, path string, opts Options) error {
	if opts.TilesPerRow <= 0 {
		opts.TilesPerRow = 16
	}
	if opts.Scale <= 0 {
		opts.Scale = 1
	}
	pal := &DefaultPalette
	if opts.Palette != nil {
		pal = opts.Palette
	}

	numTiles := len(data) / 32 // 32 bytes per 8x8 4bpp tile
	if numTiles == 0 {
		return fmt.Errorf("gfx: no complete tiles in data (size=%d)", len(data))
	}

	cols := opts.TilesPerRow
	rows := (numTiles + cols - 1) / cols
	imgW := cols * 8 * opts.Scale
	imgH := rows * 8 * opts.Scale
	img := image.NewRGBA(image.Rect(0, 0, imgW, imgH))

	for t := 0; t < numTiles; t++ {
		tileX := (t % cols) * 8 * opts.Scale
		tileY := (t / cols) * 8 * opts.Scale
		tileData := data[t*32 : t*32+32]
		for row := 0; row < 8; row++ {
			for col := 0; col < 4; col++ {
				b := tileData[row*4+col]
				pix0 := (b >> 4) & 0x0F
				pix1 := b & 0x0F
				// Each pixel scaled
				for sy := 0; sy < opts.Scale; sy++ {
					for sx := 0; sx < opts.Scale; sx++ {
						x0 := tileX + col*2*opts.Scale + sx
						y0 := tileY + row*opts.Scale + sy
						x1 := tileX + (col*2+1)*opts.Scale + sx
						img.SetRGBA(x0, y0, pal[pix0])
						img.SetRGBA(x1, y0, pal[pix1])
					}
				}
			}
		}
	}

	f, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("gfx: creating %q: %w", path, err)
	}
	defer f.Close()
	return png.Encode(f, img)
}

// TileCount returns the number of complete 8x8 4bpp tiles in data.
func TileCount(data []byte) int { return len(data) / 32 }
