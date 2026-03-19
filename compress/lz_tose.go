package compress

import (
	"encoding/binary"
	"fmt"
)

// ── LZTose — Dragon Ball Z: Buyuu Retsuden ────────────────────────────────────
// Window 0x2000 cursor 0. Header: LE16 (uncompressed_size-1)|bit15.
// 8-bit ctrl (LSB first). Match: 2 bytes LE; len=(lo&0xF)+3; offset=word>>4.

func DecompressLZTose(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("lztose: too short")
	}
	hdr := binary.LittleEndian.Uint16(src[0:2])
	uncompSize := int(hdr&0x7FFF) + 1
	pos := 2
	win := newWin(0x2000, 0, 0)
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
				win.emit(b, &out)
				decoded++
			} else {
				lo := int(read())
				hi := int(read())
				length := (lo & 0xF) + 3
				offset := ((hi << 8) | lo) >> 4
				base := (win.cursor - offset + win.size) & win.mask
				win.copyFrom(base, length, &out)
				decoded += length
			}
		}
	}
	if len(out) > uncompSize {
		out = out[:uncompSize]
	}
	return out, nil
}
