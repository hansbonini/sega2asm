package compress

import "sega2asm/types"

func init() {
	Register(Algorithm{Name: "lzcomper", Family: FamilyLZ, Description: "Community format optimised for 68000 speed", Decompress: DecompressLZComper})
}

// DecompressLZComper decompresses data using the Comper (clownlzss) format.
//
// Word-oriented: all operations work on 16-bit units.
// No size header; stream terminates when a back-reference with raw_count == 0 is encountered.
//
// Control stream: 16-bit big-endian descriptor word, MSB first. For each bit:
//
//	bit=1 → literal word (2 bytes verbatim)
//	bit=0 → back-reference word pair (raw_dist, raw_count):
//	          distance = (0x100 - raw_dist) × 2 bytes
//	          length   = (raw_count + 1) × 2 bytes; raw_count == 0 → end of stream
func DecompressLZComper(src []byte) ([]byte, error) {
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
			types.CopyDist(&out, (0x100-rawDist)*2, (rawCount+1)*2)
		}
	}
	return out, nil
}
