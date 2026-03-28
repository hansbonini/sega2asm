package compress

import (
	"fmt"
	"sega2asm/types"
)

func init() {
	Register(Algorithm{Name: "lzbeam", Family: FamilyLZ, Description: "Beam Software LZ; Elias-coded counts", Decompress: DecompressLZBeam})
}

// DecompressLZBeam decompresses data using the Beam Software compression format.
//
// Header layout:
//
//	[0..1] big-endian word  — uncompressed size
//	[2..3] big-endian word  — offset to command bitstream (cmddata at src[off+2])
//	[4..]  literal/back-reference payload
//
// The command bitstream encodes:
//   - Copy counts using an Elias-like variable-length code (leading 0-bits + data bits + stop bit 1)
//   - Back-reference offsets as absolute output positions, with bit width = bitLen(writePos)
//     (or 8+bitLen(writePos>>8) when writePos >= 256)
//
// Main decompression pattern: initial literal run, then loop of (back-ref + optional literal run).
// Reference: https://github.com/lab313ru/bsct/blob/master/ucompressor.pas
func DecompressLZBeam(src []byte) ([]byte, error) {
	if len(src) < 4 {
		return nil, fmt.Errorf("lzbeam: input too short")
	}

	outLen := int(src[0])<<8 | int(src[1])
	cmdOff := int(src[2])<<8 | int(src[3])
	cmdDataStart := cmdOff + 2
	if cmdDataStart > len(src) {
		return nil, fmt.Errorf("lzbeam: cmddata offset %d out of range", cmdDataStart)
	}

	rpos := 4
	out := make([]byte, 0, outLen)
	br := types.NewMSBBitReader(src, cmdDataStart)

	// bitLen returns the number of bits needed to represent v (0→0, 1→1, 2-3→2, …).
	bitLen := func(v int) int {
		n := 0
		for v > 0 {
			n++
			v >>= 1
		}
		return n
	}

	// readCopyCount decodes an Elias-like variable-length count.
	// Bit pattern: leading zeros double+extend the accumulator; a 1-bit stops the loop.
	readCopyCount := func() int {
		result := 1
		for br.ReadBit() == 0 && len(out)+result < outLen {
			result = (result << 1) | br.ReadBit()
		}
		return result
	}

	// readOffset reads an absolute back-reference position.
	// Bit width depends on how much output has been written so far.
	readOffset := func() int {
		writePos := len(out)
		var nbits int
		if writePos < 256 {
			nbits = bitLen(writePos)
		} else {
			nbits = 8 + bitLen(writePos>>8)
		}
		return br.ReadBits(nbits)
	}

	copySrcToDst := func() {
		count := readCopyCount()
		for i := 0; i < count; i++ {
			if rpos >= len(src) {
				break
			}
			out = append(out, src[rpos])
			rpos++
		}
	}

	copyDstToDst := func(offset int) {
		count := readCopyCount() + 2
		for i := 0; i < count && len(out) < outLen; i++ {
			idx := offset + i
			if idx < 0 || idx >= len(out) {
				out = append(out, 0)
			} else {
				out = append(out, out[idx])
			}
		}
	}

	// Initial literal run.
	copySrcToDst()

	for len(out) < outLen {
		offset := readOffset()
		copyDstToDst(offset)

		if len(out) < outLen && br.ReadBit() == 0 {
			copySrcToDst()
		}
	}

	return out, nil
}
