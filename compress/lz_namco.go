package compress

import (
	"encoding/binary"
	"sega2asm/helpers"
	"fmt"
)

// ── LZNamco ─ Ball Jacks, Klax, Marvel Land, Pac-Attack, PacMan2, Phelios …──
// Window 0x1000, cursor 0xFEE, fill 0x00. Header: BE16 uncompressed size.
// 8-bit ctrl (LSB first). bit=1→literal; bit=0→match BE16: len=(lo&0xF)+3, offset=((lo&0xF0)<<4)|hi.

func DecompressLZNamco(src []byte) ([]byte, error) { return decompressNamco(src, 0x1000, 0xFEE) }

// LZStrike — Desert/Jungle/Urban Strike. Same as Namco but window=0x800.
func DecompressLZStrike(src []byte) ([]byte, error) { return decompressNamco(src, 0x800, 0x7EE) }

func decompressNamco(src []byte, winSize, winCursor int) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("lznamco: too short")
	}
	uncompSize := int(binary.BigEndian.Uint16(src[0:2]))
	pos := 2
	win := helpers.NewWin(winSize, winCursor, 0)
	var out []byte
	decoded := 0
	read := func() byte {
		if pos >= len(src) {
			return 0
		}
		b := src[pos]
		pos++
		return b
	}
	for decoded < uncompSize {
		ctrl := read()
		for bit := 0; bit < 8 && decoded < uncompSize; bit++ {
			if (ctrl>>uint(bit))&1 == 1 {
				b := read()
				win.Emit(b, &out)
				decoded++
			} else {
				hi := int(read())
				lo := int(read())
				length := (lo & 0xF) + 3
				offset := ((lo & 0xF0) << 4) | hi
				win.CopyFrom(offset, length, &out)
				decoded += length
			}
		}
	}
	return out, nil
}
