package compress

import (
	"encoding/binary"
	"fmt"
)

// DecompressHuffNemesis2 decompresses 4bpp tile data using the Samsung Mega Drive
// Huffman-nibble scheme (sub_1F32, used in Uzu Keobukseon and other
// Samsung-developed titles).
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

	pos := 0

	rd8 := func() byte {
		if pos >= len(src) {
			return 0
		}
		b := src[pos]
		pos++
		return b
	}

	rd16 := func() uint16 {
		if pos+1 >= len(src) {
			return 0
		}
		w := binary.BigEndian.Uint16(src[pos:])
		pos += 2
		return w
	}

	// --- Header ---
	header := rd16()
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

	// --- Build Huffman lookup table (sub_1FF0) ---
	// Canonical Huffman: 8 count bytes (for code lengths 1-8),
	// followed by that many symbol bytes per length.
	// Table: 256 entries × 2 bytes [bits_to_give_back, value].
	type htEntry struct {
		adjust byte // bits to give back (8 - code_length)
		value  byte // decoded symbol
	}
	var table [256]htEntry

	var counts [9]int
	for i := 1; i <= 8; i++ {
		counts[i] = int(rd8())
	}

	code := 0
	for length := 1; length <= 8; length++ {
		for j := 0; j < counts[length]; j++ {
			sym := rd8()
			adjust := 8 - length
			nEntries := 1 << uint(adjust)
			base := code << uint(adjust)
			for k := 0; k < nEntries; k++ {
				idx := base + k
				if idx < 256 {
					table[idx] = htEntry{byte(adjust), sym}
				}
			}
			code++
		}
		code <<= 1
	}

	// --- Bitstream reader ---
	bits := uint32(rd16()) // 16-bit buffer
	bitCount := 16

	refill := func() {
		if bitCount <= 0 && pos+1 < len(src) {
			bits = uint32(rd16())
			bitCount = 16
		}
	}

	readBits := func(n int) int {
		result := 0
		for i := 0; i < n; i++ {
			if bitCount == 0 {
				bits = uint32(rd16())
				bitCount = 16
			}
			bitCount--
			result = (result << 1) | int((bits>>uint(bitCount))&1)
		}
		return result
	}

	giveback := func(n int) {
		bitCount += n
		// Bits are still in the buffer; just increase the counter.
		// If bitCount > 16, we need to rewind pos. Each 16 bits = 2 bytes.
		for bitCount > 16 {
			pos -= 2
			bitCount -= 16
		}
	}
	_ = refill

	// --- Decompression loop ---
	out := make([]byte, outSize)
	wp := 0
	var xorAccum uint32
	nibbleCount := 8   // nibbles per longword
	var accum uint32    // nibble accumulator
	lwLeft := longwords // longwords remaining

	emitNibble := func(nib byte) bool {
		accum = (accum << 4) | uint32(nib&0x0F)
		nibbleCount--
		if nibbleCount == 0 {
			// Output longword
			var val uint32
			if xorMode {
				xorAccum ^= accum
				val = xorAccum
			} else {
				val = accum
			}
			if wp+3 < outSize {
				out[wp] = byte(val >> 24)
				out[wp+1] = byte(val >> 16)
				out[wp+2] = byte(val >> 8)
				out[wp+3] = byte(val)
			}
			wp += 4
			lwLeft--
			nibbleCount = 8
			accum = 0
			return lwLeft == 0
		}
		return false
	}

	for lwLeft > 0 {
		// Read 8-bit code from bitstream
		codeVal := readBits(8)

		var valueByte byte

		if codeVal >= 0xFC {
			// Escape sequence: give back 6 bits (consumed 2 of the 8),
			// then read 7 bits for the raw value.
			giveback(6)
			valueByte = byte(readBits(7))
		} else {
			// Table lookup
			entry := table[codeVal]
			giveback(int(entry.adjust))
			valueByte = entry.value
		}

		// Decode value byte: high nibble = repeat-1, low nibble = pixel
		pixel := valueByte & 0x0F
		repeat := int(valueByte>>4) + 1

		for i := 0; i < repeat; i++ {
			if emitNibble(pixel) {
				return out, nil
			}
		}
	}

	return out, nil
}
