package compress

import "fmt"

// ── Kosinski ──────────────────────────────────────────────────────────────────

func DecompressKosinski(src []byte) ([]byte, error) {
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
