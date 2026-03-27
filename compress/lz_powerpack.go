package compress

import (
	"encoding/binary"
	"fmt"
)

// DecompressLZPowerPack20 decompresses data using the PowerPacker 2.0 scheme
// as found in James Pond 3 (and other Amiga-ported titles).
//
// This variant has no "PP20" magic bytes. Instead the first 4 bytes are a
// big-endian offset to the end of the compressed block:
//
//	+0x00  u32be  total_size (offset from block start to end of compressed data)
//	+0x04  u8[4]  efficiency table (bits per offset for each selector 0-3)
//	+0x08  ...    compressed bitstream (read backwards)
//	total_size-4:  u32be  trailer: bits[31:8] = decompressed size, bits[7:0] = bit skip
//
// The algorithm decompresses backwards (from end to start) using LZ77 with a
// sentinel-based bitstream reader.
func DecompressLZPowerPack20(src []byte) ([]byte, error) {
	if len(src) < 12 {
		return nil, fmt.Errorf("powerpack20: input too short")
	}

	totalSize := int(binary.BigEndian.Uint32(src[0:4]))
	if totalSize < 12 || totalSize > len(src) {
		return nil, fmt.Errorf("powerpack20: invalid total size %d (have %d bytes)", totalSize, len(src))
	}

	effTable := [4]int{
		int(src[4]), int(src[5]), int(src[6]), int(src[7]),
	}
	for i, v := range effTable {
		if v > 16 {
			return nil, fmt.Errorf("powerpack20: efficiency table[%d]=%d out of range", i, v)
		}
	}

	trailer := binary.BigEndian.Uint32(src[totalSize-4 : totalSize])
	bitSkip := int(trailer & 0xFF)
	decSize := int(trailer >> 8)
	if decSize == 0 {
		return []byte{}, nil
	}
	if decSize > 0x200000 {
		return nil, fmt.Errorf("powerpack20: decompressed size %d too large", decSize)
	}

	// Sentinel-based backwards bitstream reader.
	readPos := totalSize - 4 // points at trailer, will move backwards
	bits := uint32(1)        // sentinel: when bits==0 we refill

	getBit := func() int {
		carry := int(bits & 1)
		bits >>= 1
		if bits == 0 {
			// Refill from next 32-bit word (reading backwards).
			readPos -= 4
			if readPos < 0 {
				readPos = 0
				return carry
			}
			word := binary.BigEndian.Uint32(src[readPos : readPos+4])
			// roxr.l #1: old carry goes into bit 31, word shifts right by 1.
			bits = (uint32(carry) << 31) | (word >> 1)
			carry = int(word & 1)
		}
		return carry
	}

	readBits := func(count int) int {
		result := uint32(0)
		for i := 0; i < count; i++ {
			result = (result << 1) | uint32(getBit())
		}
		return int(result & 0xFFFFFFFF)
	}

	// Output buffer, written backwards.
	output := make([]byte, decSize)
	wp := decSize // write position (decrements)

	// Initial bit skip.
	if bitSkip > 0 {
		getBit() // first bit consumed (triggers sentinel refill)
		if bitSkip > 1 {
			bits >>= uint(bitSkip - 1)
		}
	}

	for wp > 0 {
		if getBit() == 0 {
			// --- Literal bytes ---
			// Extended count: sum of 2-bit values while value == 3.
			count := 0
			for {
				val := readBits(2)
				count += val
				if val != 3 {
					break
				}
			}
			// Write count+1 literal bytes.
			for i := 0; i < count+1; i++ {
				wp--
				if wp < 0 {
					return output, nil
				}
				output[wp] = byte(readBits(8))
			}
			if wp <= 0 {
				break
			}
		}

		// --- Match (LZ77 back-reference) ---
		selector := readBits(2)
		offsetBits := effTable[selector]
		matchLen := selector

		var matchOffset int

		if selector == 3 {
			// Extended match.
			bit := getBit()
			nOffBits := 7 // fixed 7-bit offset
			if bit != 0 {
				nOffBits = offsetBits // use efficiency table
			}
			matchOffset = readBits(nOffBits) & 0xFFFF
			matchLen &= 0xFFFF

			// Extended length: sum of 3-bit values while value == 7.
			for {
				val := readBits(3)
				matchLen = (matchLen + val) & 0xFFFF
				if val != 7 {
					break
				}
			}
		} else {
			matchOffset = readBits(offsetBits) & 0xFFFF
		}

		// Convert unsigned 16-bit to signed for address displacement.
		matchOffsetSigned := matchOffset
		if matchOffset >= 0x8000 {
			matchOffsetSigned = matchOffset - 0x10000
		}

		// Copy matchLen+2 bytes from already-decompressed data.
		copyCount := (matchLen + 2) & 0xFFFF
		for i := 0; i < copyCount; i++ {
			wp--
			if wp < 0 {
				return output, nil
			}
			srcIdx := wp + matchOffsetSigned + 1
			if srcIdx < 0 || srcIdx >= decSize {
				output[wp] = 0
			} else {
				output[wp] = output[srcIdx]
			}
		}
	}

	return output, nil
}
