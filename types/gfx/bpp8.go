package gfx

import (
	"image/color"

	"sega2asm/types"
)

func init() { types.RegisterGfxDecoder(bpp8{}) }

type bpp8 struct{}

func (bpp8) BPP() int          { return 8 }
func (bpp8) BytesPerTile() int { return 64 } // 64 pixels x 8 bits

func (bpp8) DefaultPalette() []color.RGBA {
	pal := make([]color.RGBA, 256)
	for i := range pal {
		v := uint8(i)
		pal[i] = color.RGBA{v, v, v, 0xFF}
	}
	return pal
}

// Decode decodes one 8x8 8bpp tile.
// 64 bytes: one byte per pixel.
func (bpp8) Decode(tile []byte, set func(col, row, idx int)) {
	for row := 0; row < 8; row++ {
		for col := 0; col < 8; col++ {
			set(col, row, int(tile[row*8+col]))
		}
	}
}