package compress

import (
	"encoding/binary"
	"fmt"

	"sega2asm/types"
)

func init() {
	types.RegisterAlgorithm(types.Algorithm{Name: "huffsloane", Family: types.FamilyHuffman, Description: "Burt Sloane nibble-packed Huffman", Decompress: DecompressHuffSloane})
	types.RegisterSignature(types.CompressSig{
		Name: "huffsloane", WordAligned: false,
		Sig: []byte{
			0x11, 0x11, 0x11, 0x11, 0x22, 0x22, 0x22, 0x22, 0x33, 0x33, 0x33, 0x33, 0x44, 0x44, 0x44, 0x44,
			0x55, 0x55, 0x55, 0x55, 0x66, 0x66, 0x66, 0x66, 0x77, 0x77, 0x77, 0x77, 0x88, 0x88, 0x88, 0x88,
			0x99, 0x99, 0x99, 0x99, 0xAA, 0xAA, 0xAA, 0xAA, 0xBB, 0xBB, 0xBB, 0xBB, 0xCC, 0xCC, 0xCC, 0xCC,
			0xDD, 0xDD, 0xDD, 0xDD, 0xEE, 0xEE, 0xEE, 0xEE, 0xFF, 0xFF, 0xFF, 0xFF,
			0x00, 0x00, 0x00, 0x00,
			0x00, 0x00, 0x00, 0x0F, 0x00, 0x00, 0x00, 0xFF,
			0x00, 0x00, 0x0F, 0xFF, 0x00, 0x00, 0xFF, 0xFF,
			0x00, 0x0F, 0xFF, 0xFF, 0x00, 0xFF, 0xFF, 0xFF,
			0x0F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
		},
	})
}

// DecompressHuffSloane decompresses 4bpp tile pixel data using Burt Sloane's
// Huffman nibble-packing scheme, found in titles by Technopop, HeadGames,
// Nu Romantic Productions, Foley Hi-Tech, Recreational Brainware, and
// Extended Play Productions.
//
// Block layout:
//
//	+0x00  2 bytes  (skipped / reserved)
//	+0x02  u16be    longword count — number of 32-bit big-endian longwords to output
//	+0x04  Huffman table definition:
//	         repeated (code_length_byte, symbol_byte) pairs, terminated by 0xFF.
//	         code_length_byte : 1..8  (bits in this Huffman code)
//	         An L-bit code fills 2^(8-L) consecutive slots in the 256-entry table.
//	+...   compressed bitstream (16-bit MSB-first, then byte-refilled)
//
// Huffman decode:
//
//	Peek top 8 bits of the stream → index into the 256-entry lookup table.
//	If index >= 0xFC: 6-bit escape prefix (111111b), then read 8-bit raw symbol.
//	Otherwise: table gives (code_length, symbol); consume code_length bits.
//
// Symbol byte format:
//
//	bits 7:4 = count − 1  (0..15 → writes 1..16 nibbles)
//	bits 3:0 = color       (0..15, Genesis palette index)
//
// Output:
//
//	Nibbles are packed MSB-first into 32-bit big-endian longwords (8 nibbles
//	per longword). The total output is longword_count × 4 bytes.
func DecompressHuffSloane(src []byte) ([]byte, error) {
	if len(src) < 6 {
		return nil, fmt.Errorf("huffsloane: input too short")
	}

	lwCount := int(binary.BigEndian.Uint16(src[2:4]))
	if lwCount == 0 {
		return []byte{}, nil
	}
	outSize := lwCount * 4
	if outSize > 0x200000 {
		return nil, fmt.Errorf("huffsloane: output size %d too large", outSize)
	}

	// --- Build Huffman lookup table ---
	pos := 4
	var pairs [][2]byte

	for {
		if pos >= len(src) {
			return nil, fmt.Errorf("huffsloane: unexpected end of input in table")
		}
		codeLen := src[pos]
		pos++
		if codeLen == 0xFF {
			break
		}
		if codeLen < 1 || codeLen > 8 {
			return nil, fmt.Errorf("huffsloane: invalid code length %d at offset 0x%X", codeLen, pos-1)
		}
		if pos >= len(src) {
			return nil, fmt.Errorf("huffsloane: unexpected end of input in table (symbol)")
		}
		symbol := src[pos]
		pos++
		pairs = append(pairs, [2]byte{codeLen, symbol})
	}

	table := types.BuildHuffTable256Pairs(pairs)

	// --- Bitstream reader (MSB-first, byte-refill when bits < 9) ---
	if pos+1 >= len(src) {
		return nil, fmt.Errorf("huffsloane: no bitstream data")
	}
	buf := uint32(src[pos])<<8 | uint32(src[pos+1])
	pos += 2
	bits := 16

	refill := func() {
		if bits < 9 && pos < len(src) {
			buf = ((buf << 8) & 0xFFFF) | uint32(src[pos])
			bits += 8
			pos++
		}
	}

	peek8 := func() int {
		return int((buf >> uint(bits-8)) & 0xFF)
	}

	consume := func(n int) {
		bits -= n
		refill()
	}

	readEscape := func() byte {
		// Consume 6-bit escape prefix, then read 8-bit literal symbol
		bits -= 6
		refill()
		bits -= 8
		sym := byte((buf >> uint(bits)) & 0xFF)
		refill()
		return sym
	}

	// --- Decompression loop ---
	nw := types.NewNibbleWriter(lwCount, false)

	for !nw.Done() {
		code := peek8()

		var sym byte
		if code >= 0xFC {
			sym = readEscape()
		} else {
			entry := table[code]
			consume(entry.BitsUsed)
			sym = entry.Symbol
		}

		color := sym & 0x0F
		count := int(sym>>4) + 1

		if nw.PutNibbleRun(color, count) {
			break
		}
	}

	return nw.Bytes(), nil
}
