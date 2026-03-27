package compress

// DecompressLZSSBlizzard decompresses data using the Blizzard LZSS format
// (Rock N Roll Racing). Based on Haruhiko Okumura's LZSS (1989).
//
// Parameters:
//
//	N         = 4096  ring buffer size
//	F         = 18    max match length
//	THRESHOLD = 2
//
// Control stream: 1 byte encodes 8 flags (LSB first).
//
//	bit=1 → literal byte
//	bit=0 → back-reference: 2 bytes
//	          offset = byte0 | ((byte1 & 0x0F) << 8)  — absolute ring-buffer index
//	          length = ((byte1 & 0xF0) >> 4) + THRESHOLD  — copies length+1 bytes
func DecompressLZSSBlizzard(src []byte) ([]byte, error) {
	const (
		n         = 4096
		threshold = 2
	)

	var textBuf [n]byte // ring buffer, zero-initialized
	writePos := 0

	pos := 0
	read := func() (byte, bool) {
		if pos >= len(src) {
			return 0, false
		}
		b := src[pos]
		pos++
		return b, true
	}

	var out []byte
	flags := uint(0)

	for {
		flags >>= 1
		if flags&0x100 == 0 {
			c, ok := read()
			if !ok {
				break
			}
			flags = uint(c) | 0xff00
		}
		if flags&1 != 0 {
			// Literal byte
			c, ok := read()
			if !ok {
				break
			}
			out = append(out, c)
			textBuf[writePos] = c
			writePos = (writePos + 1) & (n - 1)
		} else {
			// Back-reference
			b0, ok0 := read()
			b1, ok1 := read()
			if !ok0 || !ok1 {
				break
			}
			matchOffset := int(b0) | ((int(b1) & 0x0F) << 8)
			matchLength := ((int(b1) & 0xF0) >> 4) + threshold
			for k := 0; k <= matchLength; k++ {
				c := textBuf[(matchOffset+k)&(n-1)]
				out = append(out, c)
				textBuf[writePos] = c
				writePos = (writePos + 1) & (n - 1)
			}
		}
	}

	return out, nil
}
