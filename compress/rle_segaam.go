package compress

import (
	"fmt"
	"sega2asm/types"
)

func init() {
	types.RegisterAlgorithm(types.Algorithm{
		Name:        "rlesegaam",
		Family:      types.FamilyRLE,
		Description: "Sega AM RLE (Sword of Vermilion); no header; byte<0x80=literal, byte>=0x80: count=(b-0x80)+1 then fill byte",
		Decompress:  DecompressRLESegaAM,
	})
	types.RegisterSignature(types.CompressSig{
		Name:        "rlesegaam",
		WordAligned: true,
		// MOVEM.w D0/D1,-(A7) + LEA -$20(A3),A3 + CLR.w D0 + MOVE.w D0,D1
		Sig: []byte{0x48, 0xE7, 0x00, 0xC0, 0x47, 0xEB, 0xFF, 0xE0, 0x42, 0x40, 0x32, 0x00},
	})
}

// DecompressRLESegaAM decompresses data using the Sega AM RLE format
// (Sword of Vermilion dungeon maps).
//
// No header; self-terminating by end of input.
//
//	byte < 0x80 → literal: emit byte as-is.
//	byte >= 0x80 → RLE run: count = (byte - 0x80) + 1, next byte = fill value.
//	              $80 = 1 copy, $81 = 2 copies, …, $FF = 128 copies.
func DecompressRLESegaAM(src []byte) ([]byte, error) {
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
				return nil, fmt.Errorf("rlesegaam: unexpected EOF (expected fill byte)")
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
