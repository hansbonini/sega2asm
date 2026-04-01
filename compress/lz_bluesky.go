package compress

import (
	"encoding/binary"
	"fmt"
	"sega2asm/types"
)

func init() {
	types.RegisterAlgorithm(types.Algorithm{
		Name:        "lzbluesky",
		Family:      types.FamilyMixed,
		Description: "BlueSky Software LZ+RLE (Shadowrun, etc.)",
		Decompress:  DecompressLZBlueSky,
	})
}

const (
	blueSkyRingSize = 0x800
	blueSkyRingMask = blueSkyRingSize - 1
)

// DecompressLZBlueSky decompresses data using the BlueSky Software LZ+RLE format.
//
// Header: 2 bytes big-endian — output size minus 1.
//
// Flag byte: 8 bits, processed MSB-first.
//
//	bit=0 → literal byte: copy to output and ring buffer.
//	bit=1 → two bytes b0, b1:
//	    b0 & 0x80 → back-reference:
//	        length = (b0 & 0x0F) + 3
//	        offset = ((b1 << 3) | ((b0 >> 4) & 7)) — 11-bit offset from ring pointer
//	    else → RLE fill:
//	        length = (b0 & 0x7F) + 3
//	        fill   = b1
func DecompressLZBlueSky(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("lzbluesky: too short")
	}
	total := int(binary.BigEndian.Uint16(src[0:2])) + 1
	pos := 2

	ring := make([]byte, blueSkyRingSize)
	rp := 0
	out := make([]byte, 0, total)

	read := func() (byte, bool) {
		if pos >= len(src) {
			return 0, false
		}
		b := src[pos]
		pos++
		return b, true
	}

	for len(out) < total {
		flag, ok := read()
		if !ok {
			break
		}
		for bit := 7; bit >= 0 && len(out) < total; bit-- {
			if (flag>>uint(bit))&1 == 0 {
				b, ok := read()
				if !ok {
					return nil, fmt.Errorf("lzbluesky: unexpected EOF (literal)")
				}
				out = append(out, b)
				ring[rp] = b
				rp = (rp + 1) & blueSkyRingMask
			} else {
				b0, ok0 := read()
				b1, ok1 := read()
				if !ok0 || !ok1 {
					return nil, fmt.Errorf("lzbluesky: unexpected EOF (ref/rle)")
				}
				if b0&0x80 != 0 {
					length := int(b0&0x0F) + 3
					off11 := (int(b1)<<3 | int((b0>>4)&7)) & blueSkyRingMask
					srcPtr := (rp - off11) & blueSkyRingMask
					for i := 0; i < length && len(out) < total; i++ {
						b := ring[srcPtr&blueSkyRingMask]
						out = append(out, b)
						ring[rp] = b
						rp = (rp + 1) & blueSkyRingMask
						srcPtr++
					}
				} else {
					length := int(b0&0x7F) + 3
					fill := b1
					for i := 0; i < length && len(out) < total; i++ {
						out = append(out, fill)
						ring[rp] = fill
						rp = (rp + 1) & blueSkyRingMask
					}
				}
			}
		}
	}

	if len(out) != total {
		return nil, fmt.Errorf("lzbluesky: expected %d bytes, got %d", total, len(out))
	}
	return out, nil
}
