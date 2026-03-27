package compress

import "fmt"

// DecompressLZKosinski decompresses data using the Kosinski compression format.
//
// No size header; stream is self-terminating via an end-of-stream token.
//
// Control stream: 16-bit little-endian descriptor word, LSB first.
//
//	bit=1                → literal byte
//	bit=0, next bit=1    → full back-reference: 2 bytes
//	                          offset = -( 0x1FFF - ((b0 >> 3) | (b1 << 5)) )  (13-bit)
//	                          length = b0 & 7; 0 → read next byte + 1; 1 → end of stream
//	bit=0, next bit=0    → short back-reference: next 2 bits = length-2 (1..3), next byte = distance
//
// Reference: https://segaretro.org/Kosinski_compression
func DecompressLZKosinski(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("kosinski: too short")
	}
	var out []byte
	pos := 0
	read := func() byte {
		if pos >= len(src) {
			return 0
		}
		b := src[pos]
		pos++
		return b
	}
	var desc uint16
	descBitsLeft := 0
	getBit := func() int {
		if descBitsLeft == 0 {
			lo := uint16(read())
			hi := uint16(read())
			desc = hi<<8 | lo
			descBitsLeft = 16
		}
		b := int(desc & 1)
		desc >>= 1
		descBitsLeft--
		return b
	}
	for {
		if getBit() == 1 {
			out = append(out, read())
		} else {
			var offset, count int
			if getBit() == 1 {
				lo := int(read())
				hi := int(read())
				offset = lo | ((hi & 0xF8) << 5) | 0xFFFFE000
				count = hi & 7
				if count == 0 {
					count = int(read())
					if count == 0 {
						break
					}
					if count == 1 {
						continue
					}
					count++
				} else {
					count += 2
				}
			} else {
				b0 := getBit()
				b1 := getBit()
				count = (b0<<1 | b1) + 2
				offset = int(int8(read())) | 0xFFFFFF00
			}
			start := len(out) + offset
			for i := 0; i < count; i++ {
				idx := start + i
				if idx < 0 || idx >= len(out) {
					out = append(out, 0)
				} else {
					out = append(out, out[idx])
				}
			}
		}
	}
	return out, nil
}
