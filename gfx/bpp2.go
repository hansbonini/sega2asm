package gfx

import (
	"image/color"

	"sega2asm/types"
)

func init() { types.RegisterGfxDecoder(bpp2{}) }

type bpp2 struct{}

func (bpp2) BPP() int          { return 2 }
func (bpp2) BytesPerTile() int { return 16 } // 64 pixels x 2 bits

func (bpp2) DefaultPalette() []color.RGBA {
	return []color.RGBA{
		{0x00, 0x00, 0x00, 0xFF},
		{0x55, 0x55, 0x55, 0xFF},
		{0xAA, 0xAA, 0xAA, 0xFF},
		{0xFF, 0xFF, 0xFF, 0xFF},
	}
}

// Decode decodes one 8x8 2bpp tile.
// 16 bytes: each byte holds 4 pixels (2 bits each), MSB first.
func (bpp2) Decode(tile []byte, set func(col, row, idx int)) {
	for row := 0; row < 8; row++ {
		for col := 0; col < 4; col++ {
			b := tile[row*2+col/2]
			shift := uint(6 - (col%2)*4)
			set(col*2, row, int((b>>shift)&3))
			set(col*2+1, row, int((b>>(shift-2))&3))
		}
	}
}
