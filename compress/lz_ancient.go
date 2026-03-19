package compress

import (
	"encoding/binary"
	"fmt"
)

// DecompressLZAncient decompresses data using the LZAncient format
// (Beyond Oasis, Streets of Rage 2).
//
// Header:
//
//	[0..1] little-endian word — compressed data size
//	[2]    if 0 → empty output, return immediately
//
// No descriptor bitstream; each block begins with a control byte
// whose bits 7:6 select the operation:
//
//	0b10 → LZ back-reference: remaining bits encode distance and length
//	0b01 → RLE: repeat one byte N times
//	0b00 → literal run: copy N bytes verbatim
func DecompressLZAncient(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("lzancient: too short")
	}
	compSize := int(binary.LittleEndian.Uint16(src[0:2]))
	if len(src) >= 3 && src[2] == 0 {
		return []byte{}, nil
	}
	pos := 2
	end := compSize
	if end > len(src) {
		end = len(src)
	}
	var out []byte
	read := func() byte {
		if pos >= end {
			return 0
		}
		b := src[pos]
		pos++
		return b
	}
	bitClear := func(v, idx int) int {
		if (v>>uint(idx))&1 != 0 {
			return v ^ (1 << uint(idx))
		}
		return v
	}
	rotL := func(v, n int) int { n %= 8; return ((v << uint(n)) & 0xFF) | ((v & 0xFF) >> uint(8-n)) }
	for pos < end {
		ctrl := int(read())
		if ctrl&0x80 != 0 {
			ctrl = bitClear(ctrl, 7)
			repeats := rotL(ctrl&0x60, 3) + 4
			next := int(read())
			position := ((ctrl & 0x1F) << 8) | next
			if position > 0 {
				for i := 0; i < repeats; i++ {
					out = append(out, out[len(out)-position])
				}
			}
			for {
				ctrl2 := int(read())
				if (ctrl2 & 0xE0) == 0x60 {
					extra := ctrl2 & 0x1F
					for i := 0; i < extra; i++ {
						out = append(out, out[len(out)-position])
					}
				} else {
					pos--
					break
				}
			}
		} else if ctrl&0x40 != 0 {
			ctrl = bitClear(ctrl, 6)
			var repeats int
			if bitClear(ctrl, 4) == ctrl {
				repeats = ctrl + 4
			} else {
				ctrl = bitClear(ctrl, 4)
				repeats = ((ctrl << 8) | int(read())) + 4
			}
			val := read()
			for i := 0; i < repeats; i++ {
				out = append(out, val)
			}
		} else {
			var length int
			if bitClear(ctrl, 5) == ctrl {
				length = ctrl
			} else {
				length = int(read())
			}
			for i := 0; i < length; i++ {
				out = append(out, read())
			}
		}
	}
	return out, nil
}
