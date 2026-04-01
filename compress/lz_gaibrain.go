package compress

import (
	"sega2asm/types"
	"encoding/binary"
	"fmt"
)

func init() {
	types.RegisterAlgorithm(types.Algorithm{Name: "lzgaibrain", Family: types.FamilyLZ, Description: "Gaibrain variable-split LZSS", Decompress: DecompressLZGaibrain})
	types.RegisterSignature(types.CompressSig{
		Name: "lzgaibrain", WordAligned: true,
		Sig: []byte{
			0x3E, 0x18, 0x34, 0x07, 0x02, 0x47, 0x3F, 0xFF, 0xBF, 0x42,
			0xE5, 0x5A, 0x72, 0x04, 0x92, 0x42, 0x74, 0x01, 0xE3, 0x6A,
			0x53, 0x42,
		},
	})
}

// DecompressLZGaibrain decompresses data using the Gaibrain LZ scheme found in
// Fatal Fury / Garou Densetsu and other Gaibrain-developed Mega Drive titles.
//
// Stream layout:
//
//	word 0: header (big-endian)
//	  bits 15-14: mode (0-3) — controls offset/length split in command bytes
//	    mode 0: 4-bit offset (max 16),  4-bit length (max 16)
//	    mode 1: 5-bit offset (max 32),  3-bit length (max 8)
//	    mode 2: 6-bit offset (max 64),  2-bit length (max 4)
//	    mode 3: 7-bit offset (max 128), 1-bit length (max 2)
//	  bits 13-0:  chunk count minus 1 (each chunk = 1 flag byte + up to 8 ops)
//	byte 2+: compressed data
//
// Each chunk starts with a flag byte whose 8 bits are consumed MSB-first:
//
//	bit = 0: literal — copy next byte from stream to output
//	bit = 1: back-reference — read 1 command byte, split into offset (upper)
//	          and length (lower), copy (length+1) bytes from output history
//	          at distance (offset+1) behind the write cursor.
func DecompressLZGaibrain(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("lzgaibrain: input too short")
	}

	header := binary.BigEndian.Uint16(src)
	chunks := int(header&0x3FFF) + 1
	mode := int(header >> 14)

	shift := uint(4 - mode) // bits used for offset in command byte
	mask := (1 << shift) - 1 // mask for length bits

	pos := 2
	dst := make([]byte, 0, chunks*8)

	for c := 0; c < chunks; c++ {
		if pos >= len(src) {
			return nil, fmt.Errorf("lzgaibrain: unexpected end of input at chunk %d/%d", c, chunks)
		}
		flags := src[pos]
		pos++

		for bit := 7; bit >= 0; bit-- {
			if flags&(1<<uint(bit)) == 0 {
				// Literal byte
				if pos >= len(src) {
					return nil, fmt.Errorf("lzgaibrain: unexpected end of input (literal)")
				}
				dst = append(dst, src[pos])
				pos++
			} else {
				// Back-reference
				if pos >= len(src) {
					return nil, fmt.Errorf("lzgaibrain: unexpected end of input (backref)")
				}
				cmd := int(src[pos])
				pos++

				offset := cmd >> shift  // distance - 1 (neg.w in original ASM)
				length := (cmd & mask) + 1 // dbf count + 1

				base := len(dst) - offset - 1
				if base < 0 {
					return nil, fmt.Errorf("lzgaibrain: back-reference out of bounds (offset=%d, outpos=%d)", offset+1, len(dst))
				}
				for i := 0; i < length; i++ {
					dst = append(dst, dst[base+i])
				}
			}
		}
	}

	return dst, nil
}
