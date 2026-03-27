package compress

import "fmt"

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

	r := swdReader{src: src}
	dst := make([]byte, 0, len(src)*2)

	for {
		// Command bit
		bit, err := r.readBits(1)
		if err != nil {
			return nil, fmt.Errorf("elmerswd: %w", err)
		}

		if bit == 0 {
			// Literal byte
			b, err := r.readBits(8)
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
func swdReadLength(r *swdReader) (int, bool, error) {
	bit, err := r.readBits(1)
	if err != nil {
		return 0, false, err
	}
	if bit == 0 {
		return 2, false, nil
	}

	v, err := r.readBits(2)
	if err != nil {
		return 0, false, err
	}
	if v != 0 {
		return 2 + v, false, nil
	}

	v, err = r.readBits(4)
	if err != nil {
		return 0, false, err
	}
	if v != 0 {
		return 5 + v, false, nil
	}

	v, err = r.readBits(8)
	if err != nil {
		return 0, false, err
	}
	if v == 0 {
		return 0, true, nil // end of stream
	}
	return 20 + v, false, nil
}

// swdReadOffset decodes the variable-width back-reference offset.
func swdReadOffset(r *swdReader) (int, error) {
	sel, err := r.readBits(2)
	if err != nil {
		return 0, err
	}
	switch sel {
	case 0:
		v, err := r.readBits(5)
		if err != nil {
			return 0, err
		}
		return v + 1, nil
	case 1:
		v, err := r.readBits(7)
		if err != nil {
			return 0, err
		}
		return v + 0x21, nil
	case 2:
		v, err := r.readBits(9)
		if err != nil {
			return 0, err
		}
		return v + 0xA1, nil
	default: // 3
		v, err := r.readBits(10)
		if err != nil {
			return 0, err
		}
		return v + 0x2A1, nil
	}
}

// swdReader is a big-endian bitstream reader that consumes 16-bit words,
// mirroring the M68K rotate-based reader in the original decompressor.
type swdReader struct {
	src  []byte
	pos  int    // byte position in src
	bits uint32 // bit buffer (upper bits hold data)
	n    int    // number of valid bits in buffer
}

func (r *swdReader) readBits(count int) (int, error) {
	for r.n < count {
		if r.pos+1 >= len(r.src) {
			return 0, fmt.Errorf("unexpected end of input at byte %d", r.pos)
		}
		word := uint32(r.src[r.pos])<<8 | uint32(r.src[r.pos+1])
		r.pos += 2
		r.bits |= word << uint(16-r.n)
		r.n += 16
	}
	val := int(r.bits >> uint(32-count))
	r.bits <<= uint(count)
	r.n -= count
	return val, nil
}
