package compress

import (
	"encoding/binary"
	"sega2asm/helpers"
	"fmt"
)

// DecompressLZNextech decompresses data using the LZNextech format
// (Crusader of Centy). Window 0x1000 with a special non-uniform initialization pattern.
//
// Header:
//
//	[0..3] little-endian dword — compressed size
//	[4..7] little-endian dword — uncompressed size
//
// Back-reference encoding is identical to LZNamco (8-bit ctrl LSB first,
// bit=1 → literal, bit=0 → big-endian word match).
func DecompressLZNextech(src []byte) ([]byte, error) { return decompressNextech(src) }

// DecompressLZWolfteam decompresses data using the LZWolfteam format
// (El Viento, Granada, Earnest Evans, Final Zone, Ranger-X, Zan Yasha).
// Uses the same algorithm and window initialization as LZNextech.
func DecompressLZWolfteam(src []byte) ([]byte, error) { return decompressNextech(src) }

func decompressNextech(src []byte) ([]byte, error) {
	if len(src) < 8 {
		return nil, fmt.Errorf("lznextech: too short")
	}
	uncompSize := int(binary.LittleEndian.Uint32(src[4:8]))
	pos := 8
	win := helpers.NewWin(0x1000, 0xFEE, 0)
	initWindowNextech(win)
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
	if len(out) > uncompSize {
		out = out[:uncompSize]
	}
	return out, nil
}

func initWindowNextech(w *helpers.WinBuf) {
	for i := 0; i < 0x100; i++ {
		for j := 0; j < 0x0D && i*0x0D+j < w.Size; j++ {
			w.Data[i*0x0D+j] = byte(i)
		}
		if 0xD00+i < w.Size {
			w.Data[0xD00+i] = byte(i)
		}
		if 0xE00+i < w.Size {
			w.Data[0xE00+i] = byte(0xFF - i)
		}
		if i < 0x80 && 0xF00+i < w.Size {
			w.Data[0xF00+i] = 0x00
		}
		if i < 0x6E {
			w.Data[i] = 0x20
		}
	}
	w.Cursor = 0xFEE
}
