package compress

// DecompressLZClimax decompresses data using the Climax LZ77 format (Landstalker / Climax engine).
//
// Stream structure: groups of up to 8 entries preceded by a control byte (MSB-first).
//
//	bit=1 → literal: copy 1 byte verbatim
//	bit=0 → back-reference: 2 bytes
//	          b0 = (offset >> 4) & 0xF0 | (18 - length) & 0x0F
//	          b1 = offset & 0xFF
//	          offset = (b0 & 0xF0) << 4 | b1   (12-bit, 1..4095)
//	          length = 18 - (b0 & 0x0F)         (3..18)
//	          offset == 0 → end of stream
//
// No size header; stream is self-terminating.
// Reference: liblandstalker LZ77.cpp (lordmir)
func DecompressLZClimax(src []byte) ([]byte, error) {
	var out []byte
	pos := 0
	ctrl := byte(0)
	bitsLeft := 0

	for pos < len(src) {
		if bitsLeft == 0 {
			ctrl = src[pos]
			pos++
			bitsLeft = 8
		}
		bit := ctrl & 0x80
		ctrl <<= 1
		bitsLeft--

		if bit != 0 {
			// Literal byte
			if pos >= len(src) {
				break
			}
			out = append(out, src[pos])
			pos++
		} else {
			// Back-reference
			if pos+1 >= len(src) {
				break
			}
			b0 := src[pos]
			b1 := src[pos+1]
			pos += 2
			offset := int(b0&0xF0)<<4 | int(b1)
			length := 18 - int(b0&0x0F)
			if offset == 0 {
				break
			}
			base := len(out) - offset
			for i := 0; i < length; i++ {
				idx := base + i
				if idx < 0 {
					out = append(out, 0)
				} else {
					out = append(out, out[idx])
				}
			}
		}
	}
	return out, nil
}
