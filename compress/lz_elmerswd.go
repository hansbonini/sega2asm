package compress

import (
	"fmt"
	"sega2asm/types"
)

func init() {
	Register(Algorithm{Name: "lzelmerswd", Family: FamilyLZ, Description: "Elmer's SWD bitstream LZ", Decompress: DecompressLZElmerSWD})
}

// DecompressLZElmerSWD decompresses data in Elmer's SWD format, a bitstream-based
// LZ scheme used in Ex-Mutants (Sega Genesis) by Malibu Interactive
//
// Stream layout (word-aligned, big-endian bitstream):
//
//	The compressed stream is consumed 16 bits at a time from the source.
//	A rotating 32-bit register (upper word = data, lower word = workspace)
//	feeds single bits and multi-bit fields through ROL.L shifts.
//
// Command bit (1 bit):
//
//	0 = literal byte: read 8 bits → output byte
//	1 = back-reference: read length, then offset, copy from output history
//
// Length encoding (variable):
//
//	Read 1 bit:
//	  0 → length = 2
//	  1 → read 2 bits:
//	        non-zero → length = 2 + value   (3..5)
//	        zero     → read 4 bits:
//	                     non-zero → length = 5 + value   (6..20)
//	                     zero     → read 8 bits:
//	                                  non-zero → length = 20 + value (21..275)
//	                                  zero     → end of stream
//
// Offset encoding (variable):
//
//	Read 2-bit selector:
//	  0 → read 5 bits,  offset = value + 1      (1..32)
//	  1 → read 7 bits,  offset = value + 0x21   (33..160)
//	  2 → read 9 bits,  offset = value + 0xA1   (161..672)
//	  3 → read 10 bits, offset = value + 0x2A1  (673..1696)
//
// Copy: copy `length` bytes from (write_cursor − offset) to write_cursor.
func DecompressLZElmerSWD(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("elmerswd: input too short")
	}

	r := types.NewMSBWordBitReader(src, 0)
	dst := make([]byte, 0, len(src)*2)

	for {
		bit, err := r.ReadBits(1)
		if err != nil {
			return nil, fmt.Errorf("elmerswd: %w", err)
		}

		if bit == 0 {
			b, err := r.ReadBits(8)
			if err != nil {
				return nil, fmt.Errorf("elmerswd: %w", err)
			}
			dst = append(dst, byte(b))
			continue
		}

		// Back-reference: decode length
		length, eof, err := swdReadLength(&r)
		if err != nil {
			return nil, fmt.Errorf("elmerswd: %w", err)
		}
		if eof {
			return dst, nil
		}

		// Decode offset
		offset, err := swdReadOffset(&r)
		if err != nil {
			return nil, fmt.Errorf("elmerswd: %w", err)
		}

		// Copy from history
		base := len(dst) - offset
		if base < 0 {
			return nil, fmt.Errorf("elmerswd: back-reference out of bounds (offset=%d, outpos=%d)", offset, len(dst))
		}
		for i := 0; i < length; i++ {
			dst = append(dst, dst[base+i])
		}
	}
}

// swdReadLength decodes the variable-length match length.
// Returns (length, isEOF, error).
func swdReadLength(r *types.MSBWordBitReader) (int, bool, error) {
	bit, err := r.ReadBits(1)
	if err != nil {
		return 0, false, err
	}
	if bit == 0 {
		return 2, false, nil
	}

	v, err := r.ReadBits(2)
	if err != nil {
		return 0, false, err
	}
	if v != 0 {
		return 2 + v, false, nil
	}

	v, err = r.ReadBits(4)
	if err != nil {
		return 0, false, err
	}
	if v != 0 {
		return 5 + v, false, nil
	}

	v, err = r.ReadBits(8)
	if err != nil {
		return 0, false, err
	}
	if v == 0 {
		return 0, true, nil // end of stream
	}
	return 20 + v, false, nil
}

// swdReadOffset decodes the variable-width back-reference offset.
func swdReadOffset(r *types.MSBWordBitReader) (int, error) {
	sel, err := r.ReadBits(2)
	if err != nil {
		return 0, err
	}
	switch sel {
	case 0:
		v, err := r.ReadBits(5)
		if err != nil {
			return 0, err
		}
		return v + 1, nil
	case 1:
		v, err := r.ReadBits(7)
		if err != nil {
			return 0, err
		}
		return v + 0x21, nil
	case 2:
		v, err := r.ReadBits(9)
		if err != nil {
			return 0, err
		}
		return v + 0xA1, nil
	default: // 3
		v, err := r.ReadBits(10)
		if err != nil {
			return 0, err
		}
		return v + 0x2A1, nil
	}
}
