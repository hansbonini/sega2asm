package compress

import "fmt"

// lzKoeiPLen is the position-length lookup table (p_len) used to determine
// how many bits to read for a back-reference offset.
var lzKoeiPLen = [64]byte{
	0x00, 0x00, 0x00, 0x00, 0x01, 0x01, 0x02, 0x02,
	0x02, 0x02, 0x02, 0x02, 0x03, 0x03, 0x03, 0x03,
	0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03,
	0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04,
	0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05,
	0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06,
	0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07,
	0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08,
}

// DecompressLZSSKoei decompresses data using the KOEI LZSS variant.
// Direct port of TLZ.Decompress from LZSS.pas.
//
// The compressed stream interleaves flag/literal bytes with 16-bit "pairs"
// words that carry back-reference data:
//
//	bit=1 in flag → literal byte
//	bit=0 in flag → back-reference
//	              match length: Elias-gamma encoded
//	              match offset: variable-width with p_len bias table
//	End marker: back-reference whose decoded length + 1 equals 255
func DecompressLZSSKoei(src []byte) ([]byte, error) {
	pos := 0
	readByte := func() (byte, error) {
		if pos >= len(src) {
			return 0, fmt.Errorf("lzsskoei: unexpected end of input at offset %d", pos)
		}
		b := src[pos]
		pos++
		return b, nil
	}

	// Compressed-stream bit reader (mirrors CompressedStreamReadBits).
	// Reads numBits bits MSB-first from the sequential byte stream.
	// Internal state is preserved between calls.
	var cLong uint32
	var cBitsUsed uint8
	readBits := func(numBits uint8) (uint32, error) {
		cLong &= 0xFFFF
		for numBits > 0 {
			numBits--
			if cBitsUsed == 0 {
				b0, err := readByte()
				if err != nil {
					return 0, err
				}
				b1, err := readByte()
				if err != nil {
					return 0, err
				}
				cLong = cLong | uint32(b0)<<8 | uint32(b1)
				cBitsUsed = 16
			}
			cLong <<= 1
			cBitsUsed--
		}
		return cLong >> 16, nil
	}

	// Pairs-buffer state (mirrors BitStream[0/1] + BitCounts).
	// bsLo = BitStream[0]: current working window, consumed MSB-first.
	// bsHi = BitStream[1]: prefetch word.
	// bitCounts = valid bits remaining in bsHi.
	var bsLo, bsHi uint16
	var bitCounts uint8

	// bitMask[n] = (1<<n)-1 for n in [0..16].
	var bitMask [17]uint16
	for i := 0; i < 16; i++ {
		bitMask[i] = (1 << uint(i)) - 1
	}
	bitMask[16] = 0xFFFF

	// bitsLen is set as a side-effect by elliasGammaDecode and decodePosition.
	var bitsLen uint8

	// deleteBits consumes num bits from bsLo (MSB first), backfilling from bsHi.
	// Mirrors Pascal DeleteBits.
	deleteBits := func(num uint8) error {
		bsLo <<= num
		if bitCounts < num {
			a := num - bitCounts
			bsLo |= bsHi << a
			b0, err := readBits(8)
			if err != nil {
				return err
			}
			b1, err := readBits(8)
			if err != nil {
				return err
			}
			bsHi = uint16(b0) | uint16(b1)<<8
			num = a // dec(Num, old_BitCounts)
			bitCounts = 16
		}
		a := bitCounts - num
		bsLo |= bsHi >> a
		bsHi &= bitMask[a]
		bitCounts -= num
		return nil
	}

	// elliasGammaDecode decodes an Elias-gamma value from the MSB of value.
	// Sets bitsLen to the number of bits consumed.
	elliasGammaDecode := func(value uint16) uint16 {
		mask := uint16(0x8000)
		bitsLen = 1
		for mask != 0 && (mask&value) == 0 {
			bitsLen++
			mask >>= 1
		}
		bitsLen = bitsLen*2 - 1
		return value >> (16 - bitsLen)
	}

	// decodePosition decodes a back-reference offset from the MSB of value.
	// Sets bitsLen to the number of bits consumed.
	// Mirrors Pascal DecodePosition.
	decodePosition := func(value uint16) uint16 {
		temp := value >> 10 // top 6 bits index into p_len
		bitsLen = 6 + lzKoeiPLen[temp]
		value >>= 16 - bitsLen
		switch {
		case value <= 3:
			// no bias
		case value >= 8 && value <= 11:
			value -= 4
		case value >= 0x18 && value <= 0x2F:
			value -= 0x10
		case value >= 0x60 && value <= 0xBF:
			value -= 0x40
		case value >= 0x180 && value <= 0x1FF:
			value -= 0x100
		case value >= 0x400 && value <= 0x4FF:
			value -= 0x300
		case value >= 0xA00 && value <= 0xBFF:
			value -= 0x800
		case value >= 0x1800 && value <= 0x1BFF:
			value -= 0x1400
		case value >= 0x3800:
			value -= 0x1800 // as per original Pascal source
		}
		return value
	}

	// Initialise: load the first pairs word into bsLo (DeleteBits(16)).
	if err := deleteBits(16); err != nil {
		return nil, fmt.Errorf("lzsskoei: %w", err)
	}

	var out []byte
	for {
		flag, err := readBits(8)
		if err != nil {
			return nil, fmt.Errorf("lzsskoei: %w", err)
		}
		for mask := uint32(0x80); mask != 0; mask >>= 1 {
			if flag&mask != 0 {
				// Literal byte
				b, err := readBits(8)
				if err != nil {
					return nil, fmt.Errorf("lzsskoei: %w", err)
				}
				out = append(out, byte(b))
			} else {
				// Back-reference: decode length then offset
				length := uint(elliasGammaDecode(bsLo)) + 1
				if err := deleteBits(bitsLen); err != nil {
					return nil, fmt.Errorf("lzsskoei: %w", err)
				}
				if length == 255 {
					return out, nil
				}
				offset := uint(decodePosition(bsLo))
				if err := deleteBits(bitsLen); err != nil {
					return nil, fmt.Errorf("lzsskoei: %w", err)
				}
				for i := uint(0); i < length; i++ {
					srcIdx := len(out) - int(offset) - 1
					if srcIdx < 0 {
						return nil, fmt.Errorf("lzsskoei: back-ref out of bounds (offset=%d, outPos=%d)", offset, len(out))
					}
					out = append(out, out[srcIdx])
				}
			}
		}
	}
}
