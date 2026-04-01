package gfx

import (
	"image/color"

	"sega2asm/types"
)

func init() { types.RegisterGfxDecoder(bpp1{}) }

type bpp1 struct{}

func (bpp1) BPP() int          { return 1 }
func (bpp1) BytesPerTile() int { return 8 } // 64 pixels x 1 bit

func (bpp1) DefaultPalette() []color.RGBA {
	return []color.RGBA{
		{0x00, 0x00, 0x00, 0xFF},
		{0xFF, 0xFF, 0xFF, 0xFF},
	}
}

// Decode decodes one 8x8 1bpp tile.
// 8 bytes: each byte is one row, bit 7 = leftmost pixel.
func (bpp1) Decode(tile []byte, set func(col, row, idx int)) {
	for row := 0; row < 8; row++ {
		b := tile[row]
		for col := 0; col < 8; col++ {
			set(col, row, int((b>>(7-uint(col)))&1))
		}
	}
}
