package compress

import (
	"fmt"
	"sega2asm/types"
)

func init() {
	types.RegisterAlgorithm(types.Algorithm{
		Name:        "rlevermilion",
		Family:      types.FamilyRLE,
		Description: "Sword of Vermilion RLE; no header; byte<0x80=literal, byte>=0x80: count=(b-0x80)+1 then fill byte",
		Decompress:  DecompressRLEVermilion,
	})
	types.RegisterSignature(types.CompressSig{
		Name:        "rlevermilion",
		WordAligned: true,
		// MOVEM.w D0/D1,-(A7) + LEA -$20(A3),A3 + CLR.w D0 + MOVE.w D0,D1
		Sig: []byte{
			0x48, 0xA7, 0xC0, 0x00, 0x47, 0xEB, 0xFF, 0xE0, 0x42, 0x40, 0x32, 0x00, 0x34, 0x00, 0x02, 0x42,
			0x00, 0x0F, 0x66, 0x04, 0x47, 0xEB, 0x00, 0x20, 0x12, 0x19, 0x0C, 0x41, 0x00, 0x80, 0x6D, 0x24,
			0x04, 0x41, 0x00, 0x80, 0x16, 0x19, 0x16, 0xC3, 0x52, 0x40, 0x34, 0x00, 0x02, 0x42, 0x00, 0x0F,
			0x66, 0x04, 0x47, 0xEB, 0x00, 0x20, 0x0C, 0x40, 0x01, 0x00, 0x6C, 0x12, 0x51, 0xC9, 0xFF, 0xE8,
			0x42, 0x41, 0x60, 0xD4, 0x16, 0xC1, 0x52, 0x40, 0x0C, 0x40, 0x01, 0x00, 0x6D, 0xBE, 0x4C, 0x9F,
			0x00, 0x03, 0x4E, 0x75,
		},
	})
}

// DecompressRLEVermilion decompresses data using the Vermilion RLE format
// (Sword of Vermilion dungeon maps).
//
// No header; self-terminating by end of input.
//
//	byte < 0x80 → literal: emit byte as-is.
//	byte >= 0x80 → RLE run: count = (byte - 0x80) + 1, next byte = fill value.
//	              $80 = 1 copy, $81 = 2 copies, …, $FF = 128 copies.
func DecompressRLEVermilion(src []byte) ([]byte, error) {
	var out []byte
	pos := 0
	for pos < len(src) {
		b := src[pos]
		pos++
		if b < 0x80 {
			out = append(out, b)
		} else {
			count := int(b-0x80) + 1
			if pos >= len(src) {
				return nil, fmt.Errorf("rlevermilion: unexpected EOF (expected fill byte)")
			}
			fill := src[pos]
			pos++
			for i := 0; i < count; i++ {
				out = append(out, fill)
			}
		}
	}
	return out, nil
}
