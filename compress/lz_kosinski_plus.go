package compress

import "sega2asm/helpers"

// DecompressLZKosinskiPlus decompresses data using the KosinskiPlus (clownlzss) format,
// a variant of Kosinski with 8-bit descriptors and updated match encodings.
//
// No size header; stream is self-terminating.
//
// Control stream: 8-bit descriptor byte, MSB first.
//
//	bit=1              → literal byte
//	bit=0, next bit=1  → full back-reference: 2 bytes
//	                        offset = 0x2000 - (((b0 & 0xF8) << 5) | b1)  (13-bit)
//	                        length = b0 & 7; 0 → read next byte + 9; 1 → end of stream
//	bit=0, next bit=0  → short back-reference: next 2 bits = length-2 (1..3), next byte = distance
func DecompressLZKosinskiPlus(src []byte) ([]byte, error) {
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
