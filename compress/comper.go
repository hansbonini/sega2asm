package compress

// ── Comper (clownlzss) ────────────────────────────────────────────────────────
// Word-oriented: raw=2 bytes; match=(raw_dist,raw_count); raw_count==0 → end.
// distance=(0x100-raw_dist)*2; count=(raw_count+1)*2.

func DecompressComper(src []byte) ([]byte, error) {
	pos := 0
	var out []byte
	var descWord uint16
	descBitsLeft := 0
	read := func() byte {
		if pos >= len(src) {
			return 0
		}
		b := src[pos]
		pos++
		return b
	}
	popBit := func() int {
		if descBitsLeft == 0 {
			hi := uint16(read())
			lo := uint16(read())
			descWord = (hi << 8) | lo
			descBitsLeft = 16
		}
		bit := int((descWord >> 15) & 1)
		descWord <<= 1
		descBitsLeft--
		return bit
	}
	for pos < len(src) || descBitsLeft > 0 {
		if popBit() == 0 {
			out = append(out, read(), read())
		} else {
			rawDist := int(read())
			rawCount := int(read())
			if rawCount == 0 {
				break
			}
			copyDist(&out, (0x100-rawDist)*2, (rawCount+1)*2)
		}
	}
	return out, nil
}
