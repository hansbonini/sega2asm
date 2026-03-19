package compress

import (
	"encoding/binary"
	"sega2asm/helpers"
	"fmt"
)

// DecompressLZNamco decompresses data using the LZNamco format
// (Ball Jacks, Klax, Marvel Land, Pac-Attack, Pac-Man 2, Phelios).
//
// Window: 0x1000 bytes, cursor at 0xFEE, fill 0x00.
//
// Header:
//
//	[0..1] big-endian word — uncompressed size
//
// Control stream: 8-bit descriptor byte, LSB first.
//
//	bit=1 → literal byte
//	bit=0 → back-reference: big-endian word (hi, lo)
//	          length = (lo & 0x0F) + 3
//	          offset = ((lo & 0xF0) << 4) | hi
func DecompressLZNamco(src []byte) ([]byte, error) { return decompressNamco(src, 0x1000, 0xFEE) }

// DecompressLZStrike decompresses data using the LZStrike variant
// (Desert Strike, Jungle Strike, Urban Strike). Same encoding as LZNamco
// with a smaller window: 0x800 bytes, cursor at 0x7EE.
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
