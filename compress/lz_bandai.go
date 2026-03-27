package compress

import (
	"encoding/binary"
	"sega2asm/helpers"
	"fmt"
)

// DecompressLZBandai decompresses data using the LZBandai format
// (Dragon Ball Z: Buyuu Retsuden).
//
// Window: 0x2000 bytes, cursor at 0x00, fill 0x00.
//
// Header:
//
//	[0..1] little-endian word — (uncompressed_size - 1) | bit 15 (bit 15 always set)
//
// Control stream: 8-bit descriptor byte, LSB first.
//
//	bit=1 → literal byte
//	bit=0 → back-reference: 2 bytes little-endian (word)
//	          length = (lo & 0x0F) + 3
//	          offset = word >> 4
func DecompressLZBandai(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("lzbandai: too short")
	}
	hdr := binary.LittleEndian.Uint16(src[0:2])
	uncompSize := int(hdr&0x7FFF) + 1
	pos := 2
	win := helpers.NewWin(0x2000, 0, 0)
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
				lo := int(read())
				hi := int(read())
				length := (lo & 0xF) + 3
				offset := ((hi << 8) | lo) >> 4
				base := (win.Cursor - offset + win.Size) & win.Mask
				win.CopyFrom(base, length, &out)
				decoded += length
			}
		}
	}
	if len(out) > uncompSize {
		out = out[:uncompSize]
	}
	return out, nil
}
