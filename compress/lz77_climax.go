package compress

import "sega2asm/types"

func init() {
	Register(Algorithm{Name: "lz77climax", Family: FamilyLZ77, Description: "Climax LZ77; MSB-first control, 12-bit offset", Decompress: DecompressLZ77Climax})
}

// DecompressLZ77Climax decompresses data using the Climax LZ77 format (Landstalker / Climax engine).
//
// Stream structure: groups of up to 8 entries preceded by a control byte (MSB-first).
//
//	bit=1 → literal: copy 1 byte verbatim
//	bit=0 → back-reference: 2 bytes
//	          b0 = (offset >> 4) & 0xF0 | (18 - length) & 0x0F
//	          b1 = offset & 0xFF
//	          offset = (b0 & 0xF0) << 4 | b1   (12-bit, 1..4095)
//	          length = 18 - (b0 & 0x0F)         (3..18)
//	          offset == 0 → end of stream
//
// No size header; stream is self-terminating.
// Reference: liblandstalker LZ77.cpp (lordmir)
func DecompressLZ77Climax(src []byte) ([]byte, error) {
	dr := types.NewMSBDescReader(src, 0)
	var out []byte

	for dr.Pos() < len(src) {
		if dr.PopBit() == 1 {
			out = append(out, dr.ReadByte())
		} else {
			b0 := dr.ReadByte()
			b1 := dr.ReadByte()
			offset := int(b0&0xF0)<<4 | int(b1)
			length := 18 - int(b0&0x0F)
			if offset == 0 {
				break
			}
			types.CopyDist(&out, offset, length)
		}
	}
	return out, nil
}
