package types

import "encoding/binary"

// NibbleWriter packs 4-bit nibbles MSB-first into 32-bit big-endian
// longwords. Used by tile graphics decompressors (Nemesis, Sloane, etc.)
// that output 4bpp pixel data.
//
// Each longword holds 8 nibbles: the first nibble written occupies
// bits 31:28 (most significant), the last occupies bits 3:0.
//
// When XOR mode is enabled, each completed longword is XOR'd with the
// running accumulator before being written (delta encoding).
type NibbleWriter struct {
	out      []byte
	wp       int
	accum    uint32
	nibLeft  int
	lwLeft   int
	xorMode  bool
	xorAccum uint32
}

// NewNibbleWriter creates a writer that will emit longwordCount longwords
// (longwordCount × 4 bytes total). If xorMode is true, each longword is
// XOR'd with the running accumulator before output.
func NewNibbleWriter(longwordCount int, xorMode bool) *NibbleWriter {
	return &NibbleWriter{
		out:     make([]byte, longwordCount*4),
		nibLeft: 8,
		lwLeft:  longwordCount,
		xorMode: xorMode,
	}
}

// PutNibble writes a single 4-bit nibble. Returns true when all
// longwords have been emitted.
func (w *NibbleWriter) PutNibble(nib byte) bool {
	w.accum = (w.accum << 4) | uint32(nib&0x0F)
	w.nibLeft--
	if w.nibLeft == 0 {
		w.flush()
	}
	return w.lwLeft == 0
}

// PutNibbleRun writes count copies of the same nibble value.
// Returns true when all longwords have been emitted.
func (w *NibbleWriter) PutNibbleRun(nib byte, count int) bool {
	fill := uint32(nib&0x0F) * 0x11111111
	for count > 0 && w.lwLeft > 0 {
		if count < w.nibLeft {
			newLeft := w.nibLeft - count
			mask := NibMask[w.nibLeft] - NibMask[newLeft]
			w.accum |= fill & mask
			w.nibLeft = newLeft
			break
		} else if count == w.nibLeft {
			w.accum |= fill & NibMask[w.nibLeft]
			w.flush()
			break
		} else {
			w.accum |= fill & NibMask[w.nibLeft]
			count -= w.nibLeft
			w.flush()
		}
	}
	return w.lwLeft == 0
}

// Done returns whether all longwords have been emitted.
func (w *NibbleWriter) Done() bool { return w.lwLeft == 0 }

// Bytes returns the output buffer.
func (w *NibbleWriter) Bytes() []byte { return w.out }

func (w *NibbleWriter) flush() {
	val := w.accum
	if w.xorMode {
		w.xorAccum ^= val
		val = w.xorAccum
	}
	if w.wp+4 <= len(w.out) {
		binary.BigEndian.PutUint32(w.out[w.wp:], val)
	}
	w.wp += 4
	w.accum = 0
	w.nibLeft = 8
	w.lwLeft--
}

// NibMask is the cumulative mask for the lowest n nibbles of a 32-bit word.
var NibMask = [9]uint32{
	0x00000000, 0x0000000F, 0x000000FF, 0x00000FFF,
	0x0000FFFF, 0x000FFFFF, 0x00FFFFFF, 0x0FFFFFFF,
	0xFFFFFFFF,
}
