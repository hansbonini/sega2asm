package compress

import (
	"encoding/binary"
	"fmt"
)

// DecompressLZClimax3 decompresses data using the Camelot/Climax "basic"
// tile compressor found in Shining Force 2 (LoadBasicCompressedData).
//
// Unlike lzclimax (LZSS) and lzclimax2 (spatial nibble graphics), this is
// a bitstream LZ with addx word-chaining, inline literal copies (longword
// and word), back-references with rotated 12-bit offset + inverse 5-bit
// length, and word-repeat RLE.
//
// No header; the stream is self-terminating (reference word = 0).
func DecompressLZClimax3(src []byte) ([]byte, error) {
	if len(src) < 4 {
		return nil, fmt.Errorf("lzclimax3: input too short")
	}

	out := make([]byte, 0, len(src)*4)
	pos := 0
	var d0 uint16
	xFlag := 1 // X flag — initialized to 1 (moveq #-1,d0; add.w d0,d0)

	// --- helpers ---

	rd16 := func() uint16 {
		if pos+1 >= len(src) {
			return 0
		}
		w := binary.BigEndian.Uint16(src[pos:])
		pos += 2
		return w
	}

	emit16 := func(w uint16) {
		out = append(out, byte(w>>8), byte(w))
	}

	emitLong := func() {
		w1 := rd16()
		w2 := rd16()
		out = append(out, byte(w1>>8), byte(w1), byte(w2>>8), byte(w2))
	}

	// addx reload: move.w (a0)+,d0; addx.w d0,d0
	// Returns carry (first bit of new control word).
	loadCtrl := func() int {
		w := rd16()
		r := uint32(w)*2 + uint32(xFlag)
		xFlag = int(r >> 16)
		d0 = uint16(r)
		return xFlag
	}

	// add.w d0,d0 — consume one bit, return carry.
	shift := func() int {
		r := uint32(d0) << 1
		xFlag = int(r >> 16)
		d0 = uint16(r)
		return xFlag
	}

	isEmpty := func() bool { return d0 == 0 }

	// Process a back-reference word. Returns false on end marker (word == 0).
	doRef := func(refW uint16) bool {
		if refW == 0 {
			return false
		}

		skip := int(refW & 0x1F)       // bits 0-4: inverse length / table offset
		distField := refW & 0xFFE0     // bits 5-15: distance or RLE marker
		evenSkip := skip & ^1          // clear bit 0
		hasInitWord := (skip & 1) == 0 // even → copy initial word
		nLongs := 16 - evenSkip/2      // longwords to copy from jump table

		if distField == 0x0020 {
			// RLE: repeat last output word
			if len(out) < 2 {
				return true
			}
			rleW := uint16(out[len(out)-2])<<8 | uint16(out[len(out)-1])
			if hasInitWord {
				emit16(rleW)
			}
			for i := 0; i < nLongs; i++ {
				emit16(rleW)
				emit16(rleW)
			}
		} else {
			// Back-reference copy
			offset := int(distField >> 4) // ror.w #4 on value with bits 0-4 = 0
			base := len(out) - offset
			ci := base

			if hasInitWord {
				for j := 0; j < 2; j++ {
					if ci >= 0 && ci < len(out) {
						out = append(out, out[ci])
					} else {
						out = append(out, 0)
					}
					ci++
				}
			}
			for i := 0; i < nLongs*4; i++ {
				if ci >= 0 && ci < len(out) {
					out = append(out, out[ci])
				} else {
					out = append(out, 0)
				}
				ci++
			}
		}
		return true
	}

	const maxOut = 0x200000 // 2 MB safety limit

	for len(out) < maxOut {
		// ---- loc_1A92: load control word ----
		bit := loadCtrl()

		// ---- pair 0 (no reload check — word is fresh) ----
		if bit == 1 {
			// bit A = 1 → reference (loc_1B2A)
			if !doRef(rd16()) {
				return out, nil
			}
		} else {
			bit = shift()
			if bit == 1 {
				// bit B = 1 (loc_1B10)
				if isEmpty() {
					// d0 empty → copy word + reload (loc_1A90)
					emit16(rd16())
					continue
				}
				emit16(rd16())
				if !doRef(rd16()) {
					return out, nil
				}
			} else {
				// bits AB = 00 → literal longword
				emitLong()
			}
		}

		// ---- loc_1AA2: pairs 1-7 (with reload checks) ----
		pairsLeft := 7
		for pairsLeft > 0 {
			bit = shift()
			if bit == 1 {
				if isEmpty() {
					break // reload
				}
				if !doRef(rd16()) {
					return out, nil
				}
				pairsLeft = 7 // restart after reference
				continue
			}
			bit = shift()
			if bit == 1 {
				if isEmpty() {
					emit16(rd16())
					break // reload
				}
				emit16(rd16())
				if !doRef(rd16()) {
					return out, nil
				}
				pairsLeft = 7
				continue
			}
			emitLong()
			pairsLeft--
		}

		if pairsLeft > 0 {
			continue // early reload
		}

		// ---- end section: 1-bit check + word literal + chain ----
		bit = shift()
		if bit == 1 {
			if isEmpty() {
				continue // reload
			}
			if !doRef(rd16()) {
				return out, nil
			}
			// After reference at end, restart pairs (loc_1AA2).
			// Re-enter the pairs loop.
			pairsLeft = 7
			for pairsLeft > 0 {
				bit = shift()
				if bit == 1 {
					if isEmpty() {
						break
					}
					if !doRef(rd16()) {
						return out, nil
					}
					pairsLeft = 7
					continue
				}
				bit = shift()
				if bit == 1 {
					if isEmpty() {
						emit16(rd16())
						break
					}
					emit16(rd16())
					if !doRef(rd16()) {
						return out, nil
					}
					pairsLeft = 7
					continue
				}
				emitLong()
				pairsLeft--
			}
			continue
		}
		emit16(rd16()) // word literal
		shift()        // chain bit
	}

	return out, nil
}
