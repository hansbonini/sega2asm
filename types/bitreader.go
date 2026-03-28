package types

import (
	"encoding/binary"
	"fmt"
)

// ---------------------------------------------------------------------------
// MSBBitReader — MSB-first, byte-at-a-time refill
// ---------------------------------------------------------------------------

// MSBBitReader reads bits MSB-first from a byte stream, refilling one byte
// at a time when the current byte is exhausted.
type MSBBitReader struct {
	src   []byte
	pos   int
	buf   int
	avail int
}

// NewMSBBitReader creates a reader starting at startPos in src.
func NewMSBBitReader(src []byte, startPos int) MSBBitReader {
	return MSBBitReader{src: src, pos: startPos}
}

// ReadBit returns a single bit (0 or 1), refilling from the next byte when needed.
func (r *MSBBitReader) ReadBit() int {
	if r.avail == 0 {
		if r.pos < len(r.src) {
			r.buf = int(r.src[r.pos])
			r.pos++
		}
		r.avail = 8
	}
	r.avail--
	return (r.buf >> uint(r.avail)) & 1
}

// ReadBits returns n bits assembled MSB-first as an integer.
func (r *MSBBitReader) ReadBits(n int) int {
	val := 0
	for i := 0; i < n; i++ {
		val = (val << 1) | r.ReadBit()
	}
	return val
}

// ReadByte reads a raw byte from the source, bypassing the bit buffer.
// Any partial bits in the current byte are discarded.
func (r *MSBBitReader) ReadByte() byte {
	r.avail = 0
	if r.pos < len(r.src) {
		b := r.src[r.pos]
		r.pos++
		return b
	}
	return 0
}

// Pos returns the current byte position in the source.
func (r *MSBBitReader) Pos() int { return r.pos }

// EOF returns whether the source is exhausted and no bits remain.
func (r *MSBBitReader) EOF() bool { return r.pos >= len(r.src) && r.avail == 0 }

// ---------------------------------------------------------------------------
// LSBDescReader — LSB-first, 8-bit descriptor byte
// ---------------------------------------------------------------------------

// LSBDescReader reads descriptor bits LSB-first from an 8-bit byte.
// When all 8 bits are consumed, the next byte is loaded automatically.
type LSBDescReader struct {
	src  []byte
	pos  int
	desc byte
	left int
}

// NewLSBDescReader creates a reader starting at startPos in src.
func NewLSBDescReader(src []byte, startPos int) LSBDescReader {
	return LSBDescReader{src: src, pos: startPos}
}

// PopBit returns the least-significant bit of the current descriptor,
// then shifts right. Loads a new descriptor byte when exhausted.
func (r *LSBDescReader) PopBit() int {
	if r.left == 0 {
		if r.pos < len(r.src) {
			r.desc = r.src[r.pos]
			r.pos++
		}
		r.left = 8
	}
	bit := int(r.desc & 1)
	r.desc >>= 1
	r.left--
	return bit
}

// ReadByte reads a raw byte from the source (not from the descriptor).
func (r *LSBDescReader) ReadByte() byte {
	if r.pos < len(r.src) {
		b := r.src[r.pos]
		r.pos++
		return b
	}
	return 0
}

// Pos returns the current byte position in the source.
func (r *LSBDescReader) Pos() int { return r.pos }

// ---------------------------------------------------------------------------
// MSBDescReader — MSB-first, 8-bit descriptor byte
// ---------------------------------------------------------------------------

// MSBDescReader reads descriptor bits MSB-first from an 8-bit byte.
// When all 8 bits are consumed, the next byte is loaded automatically.
type MSBDescReader struct {
	src  []byte
	pos  int
	desc byte
	left int
}

// NewMSBDescReader creates a reader starting at startPos in src.
func NewMSBDescReader(src []byte, startPos int) MSBDescReader {
	return MSBDescReader{src: src, pos: startPos}
}

// PopBit returns the most-significant bit of the current descriptor,
// then shifts left. Loads a new descriptor byte when exhausted.
func (r *MSBDescReader) PopBit() int {
	if r.left == 0 {
		if r.pos < len(r.src) {
			r.desc = r.src[r.pos]
			r.pos++
		}
		r.left = 8
	}
	bit := int(r.desc >> 7)
	r.desc <<= 1
	r.left--
	return bit
}

// ReadByte reads a raw byte from the source (not from the descriptor).
func (r *MSBDescReader) ReadByte() byte {
	if r.pos < len(r.src) {
		b := r.src[r.pos]
		r.pos++
		return b
	}
	return 0
}

// Pos returns the current byte position in the source.
func (r *MSBDescReader) Pos() int { return r.pos }

// ---------------------------------------------------------------------------
// MSBWordBitReader — MSB-first, 16-bit BE word refill, 32-bit buffer
// ---------------------------------------------------------------------------

// MSBWordBitReader reads bits MSB-first from a 32-bit buffer that is
// refilled 16 bits at a time from big-endian source words. This mirrors
// the M68K ROL.L-based bitstream reader common in Genesis decompressors.
type MSBWordBitReader struct {
	src  []byte
	pos  int
	bits uint32
	n    int
}

// NewMSBWordBitReader creates a reader starting at startPos in src.
func NewMSBWordBitReader(src []byte, startPos int) MSBWordBitReader {
	return MSBWordBitReader{src: src, pos: startPos}
}

// ReadBits extracts count bits from the top of the buffer, refilling a
// 16-bit BE word when needed. Returns an error if the source is exhausted.
func (r *MSBWordBitReader) ReadBits(count int) (int, error) {
	if r.n < count {
		if err := r.refill(); err != nil {
			return 0, err
		}
	}
	val := int(r.bits >> uint(32-count))
	r.bits <<= uint(count)
	r.n -= count
	return val, nil
}

// Peek returns the top count bits without consuming them.
func (r *MSBWordBitReader) Peek(count int) (int, error) {
	if r.n < count {
		if err := r.refill(); err != nil {
			return 0, err
		}
	}
	return int(r.bits >> uint(32-count)), nil
}

// Consume drops count bits that were previously peeked.
func (r *MSBWordBitReader) Consume(count int) {
	r.bits <<= uint(count)
	r.n -= count
}

// GiveBack pushes count bits back into the stream. This is used by
// Huffman decoders that peek 8 bits but only consume the actual code length.
func (r *MSBWordBitReader) GiveBack(count int) {
	r.bits >>= uint(count)
	r.n += count
	for r.n > 16 {
		r.pos -= 2
		r.n -= 16
	}
}

// Pos returns the current byte position in the source.
func (r *MSBWordBitReader) Pos() int { return r.pos }

func (r *MSBWordBitReader) refill() error {
	if r.pos+1 >= len(r.src) {
		return fmt.Errorf("unexpected end of input at byte %d", r.pos)
	}
	word := uint32(binary.BigEndian.Uint16(r.src[r.pos:]))
	r.pos += 2
	r.bits |= word << uint(16-r.n)
	r.n += 16
	return nil
}
