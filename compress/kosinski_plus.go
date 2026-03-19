package compress

import "sega2asm/helpers"

// ── KosinskiPlus (clownlzss) ──────────────────────────────────────────────────

func DecompressKosinskiPlus(src []byte) ([]byte, error) {
	pos := 0
	read := func() byte {
		if pos >= len(src) {
			return 0
		}
		b := src[pos]
		pos++
		return b
	}
	var descByte byte
	descBitsLeft := 0
	popBit := func() int {
		if descBitsLeft == 0 {
			descByte = read()
			descBitsLeft = 8
		}
		bit := int((descByte >> 7) & 1)
		descByte <<= 1
		descBitsLeft--
		return bit
	}
	var out []byte
	for {
		if popBit() == 1 {
			out = append(out, read())
		} else if popBit() == 1 {
			hi := int(read())
			lo := int(read())
			offset := 0x2000 - (((hi & 0xF8) << 5) | lo)
			count := hi & 7
			if count == 0 {
				count = int(read()) + 9
				if count == 9 {
					break
				}
			} else {
				count = 10 - count
			}
			helpers.CopyDist(&out, offset, count)
		} else {
			offset := 0x100 - int(read())
			count := 2
			if popBit() == 1 {
				count += 2
			}
			if popBit() == 1 {
				count++
			}
			helpers.CopyDist(&out, offset, count)
		}
	}
	return out, nil
}
