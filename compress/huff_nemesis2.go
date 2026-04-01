package compress

import (
	"encoding/binary"
	"fmt"

	"sega2asm/types"
)

func init() {
	types.RegisterAlgorithm(types.Algorithm{Name: "huffnemesis2", Family: types.FamilyHuffman, Description: "Nemesis variant; canonical Huffman table, optional XOR delta", Decompress: DecompressHuffNemesis2})
	types.RegisterSignature(types.CompressSig{
		Name: "huffnemesis2", WordAligned: true,
		Sig: []byte{
			0x34, 0x18, 0xE3, 0x4A, 0x64, 0x04, 0xD6, 0xFC, 0x00, 0x0A,
			0xE5, 0x4A, 0x3A, 0x42, 0x76, 0x08, 0x74, 0x00, 0x78, 0x00,
		},
		Validator: func(rom []byte, offset int) bool {
			if offset+44 > len(rom) { return false }
			return rom[offset+40] == 0x0C && rom[offset+41] == 0x41 &&
				rom[offset+42] == 0x00 && rom[offset+43] == 0xFC
		},
	})
}

// DecompressHuffNemesis2 decompresses 4bpp tile data using the Mega Drive
// Huffman-nibble scheme (sub_1F32, used in Uzu Keobukseon and other
// titles).
//
// Format:
//
//	+0x00  u16be  header word
//	  - Bit 15: XOR mode flag (delta-encode longwords)
//	  - Bits 14-0: tile count (output longwords = tile_count × 8)
//	+0x02  Huffman table definition (canonical: 8 count bytes + symbols)
//	+...   u16be initial bitstream word, then packed bitstream
//
// The bitstream is read MSB-first in 16-bit chunks. 8-bit codes are looked up
// in a 256-entry Huffman table. Codes >= 0xFC use a 2+7 bit escape sequence.
//
// Each decoded value byte encodes: high nibble = repeat count - 1,
// low nibble = pixel value. Nibbles are packed 8 per longword (32 bits).
func DecompressHuffNemesis2(src []byte) ([]byte, error) {
	if len(src) < 4 {
		return nil, fmt.Errorf("huffnemesis2: input too short")
	}

	// --- Header ---
	header := binary.BigEndian.Uint16(src[0:2])
	xorMode := (header & 0x8000) != 0
	tileCount := int(header & 0x7FFF)
	longwords := tileCount << 3 // 8 longwords per tile
	if longwords == 0 {
		return []byte{}, nil
	}
	outSize := longwords * 4
	if outSize > 0x200000 {
		return nil, fmt.Errorf("huffnemesis2: output size %d too large", outSize)
	}

	// --- Build Huffman lookup table (canonical) ---
	pos := 2
	var counts [9]int
	for i := 1; i <= 8; i++ {
		if pos >= len(src) {
			return nil, fmt.Errorf("huffnemesis2: unexpected end of input in table counts")
		}
		counts[i] = int(src[pos])
		pos++
	}

	totalSymbols := 0
	for i := 1; i <= 8; i++ {
		totalSymbols += counts[i]
	}
	symbols := make([]byte, totalSymbols)
	for i := 0; i < totalSymbols; i++ {
		if pos >= len(src) {
			return nil, fmt.Errorf("huffnemesis2: unexpected end of input in table symbols")
		}
		symbols[i] = src[pos]
		pos++
	}

	table := types.BuildHuffTable256Canonical(counts, symbols)

	// --- Bitstream reader ---
	br := types.NewMSBWordBitReader(src, pos)

	// --- Decompression loop ---
	nw := types.NewNibbleWriter(longwords, xorMode)

	for !nw.Done() {
		codeVal, err := br.Peek(8)
		if err != nil {
			return nw.Bytes(), nil
		}

		var valueByte byte

		if codeVal >= 0xFC {
			// Escape sequence: consume 2-bit prefix (11b), then read 7-bit raw value.
			br.Consume(2)
			raw, err := br.ReadBits(7)
			if err != nil {
				return nw.Bytes(), nil
			}
			valueByte = byte(raw)
		} else {
			// Table lookup
			entry := table[codeVal]
			br.Consume(entry.BitsUsed)
			valueByte = entry.Symbol
		}

		// Decode value byte: high nibble = repeat-1, low nibble = pixel
		pixel := valueByte & 0x0F
		repeat := int(valueByte>>4) + 1

		for i := 0; i < repeat; i++ {
			if nw.PutNibble(pixel) {
				return nw.Bytes(), nil
			}
		}
	}

	return nw.Bytes(), nil
}
