package types

import (
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"os"
)

// Mega Drive video helpers: CRAM colours, indexed tile sheets and nametable
// (tilemap) rendering. Output images are paletted PNGs so the original colour
// indices survive a round trip through an image editor or game engine.

// mdLevels maps a 3-bit Mega Drive colour channel to 8 bits (linear ramp).
var mdLevels = [8]uint8{0, 36, 73, 109, 146, 182, 219, 255}

// MDColor converts a CRAM word (----BBB-GGG-RRR-) to RGBA.
func MDColor(w uint16) color.RGBA {
	r := (w >> 1) & 7
	g := (w >> 5) & 7
	b := (w >> 9) & 7
	return color.RGBA{mdLevels[r], mdLevels[g], mdLevels[b], 0xFF}
}

// DecodePalette converts big-endian CRAM words to colours.
func DecodePalette(data []byte) []color.RGBA {
	out := make([]color.RGBA, 0, len(data)/2)
	for i := 0; i+1 < len(data); i += 2 {
		out = append(out, MDColor(uint16(data[i])<<8|uint16(data[i+1])))
	}
	return out
}

// GrayPalette returns n shades of grey (index 0 black).
func GrayPalette(n int) []color.RGBA {
	out := make([]color.RGBA, n)
	for i := range out {
		v := uint8(i * 255 / (n - 1))
		out[i] = color.RGBA{v, v, v, 0xFF}
	}
	return out
}

// PaletteLine returns 16 colours of line `line` from pal, padding with grey.
func PaletteLine(pal []color.RGBA, line int) []color.RGBA {
	out := GrayPalette(16)
	for i := 0; i < 16; i++ {
		if j := line*16 + i; j >= 0 && j < len(pal) {
			out[i] = pal[j]
		}
	}
	return out
}

func toPalette(cols []color.RGBA, transparent0 bool) color.Palette {
	p := make(color.Palette, len(cols))
	for i, c := range cols {
		if transparent0 && i%16 == 0 {
			c.A = 0
		}
		p[i] = c
	}
	return p
}

// TileSheet renders 4bpp tiles into an indexed image, perRow tiles wide.
func TileSheet(tiles []byte, perRow int, pal []color.RGBA, transparent0 bool) (*image.Paletted, error) {
	n := len(tiles) / 32
	if n == 0 {
		return nil, fmt.Errorf("no complete 4bpp tiles (%d bytes)", len(tiles))
	}
	if perRow <= 0 {
		perRow = 16
	}
	rows := (n + perRow - 1) / perRow
	img := image.NewPaletted(image.Rect(0, 0, perRow*8, rows*8), toPalette(pal, transparent0))
	for t := 0; t < n; t++ {
		ox, oy := (t%perRow)*8, (t/perRow)*8
		drawTile(img, tiles[t*32:t*32+32], ox, oy, 0, false, false)
	}
	return img, nil
}

func drawTile(img *image.Paletted, tile []byte, ox, oy, palOff int, hflip, vflip bool) {
	for row := 0; row < 8; row++ {
		for col := 0; col < 8; col++ {
			b := tile[row*4+col/2]
			v := b >> 4
			if col&1 == 1 {
				v = b & 0x0F
			}
			x, y := col, row
			if hflip {
				x = 7 - col
			}
			if vflip {
				y = 7 - row
			}
			img.SetColorIndex(ox+x, oy+y, uint8(palOff+int(v)))
		}
	}
}

// NameCell is one decoded nametable entry.
type NameCell struct {
	Tile     int  `json:"tile"`
	Palette  int  `json:"palette"`
	HFlip    bool `json:"hflip"`
	VFlip    bool `json:"vflip"`
	Priority bool `json:"priority"`
}

// DecodeNameCell splits a VDP nametable word (PCCVHTTT TTTTTTTT).
func DecodeNameCell(w uint16) NameCell {
	return NameCell{
		Tile:     int(w & 0x07FF),
		Palette:  int(w>>13) & 3,
		HFlip:    w&0x0800 != 0,
		VFlip:    w&0x1000 != 0,
		Priority: w&0x8000 != 0,
	}
}

// RenderTilemap renders nametable words (width cells per row) using tiles
// (tile index = cell tile - tileBase) and a 64-colour palette.
func RenderTilemap(words []uint16, width int, tiles []byte, tileBase int, pal []color.RGBA) (*image.Paletted, int) {
	if width <= 0 {
		width = 64
	}
	height := (len(words) + width - 1) / width
	full := make([]color.RGBA, 64)
	for l := 0; l < 4; l++ {
		copy(full[l*16:], PaletteLine(pal, l))
	}
	img := image.NewPaletted(image.Rect(0, 0, width*8, height*8), toPalette(full, true))
	missing := 0
	nt := len(tiles) / 32
	for i, w := range words {
		c := DecodeNameCell(w)
		t := c.Tile - tileBase
		if t < 0 || t >= nt {
			if c.Tile != 0 {
				missing++
			}
			continue
		}
		drawTile(img, tiles[t*32:t*32+32], (i%width)*8, (i/width)*8, c.Palette*16, c.HFlip, c.VFlip)
	}
	return img, missing
}

// WritePNG encodes img to path.
func WritePNG(path string, img image.Image) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	return png.Encode(f, img)
}

// WriteJSON writes v as indented JSON.
func WriteJSON(path string, v any) error {
	b, err := json.MarshalIndent(v, "", " ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, b, 0644)
}

// HexColor formats c as #RRGGBB.
func HexColor(c color.RGBA) string { return fmt.Sprintf("#%02X%02X%02X", c.R, c.G, c.B) }
