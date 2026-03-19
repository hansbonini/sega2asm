package compress

import (
	"encoding/binary"
	"sega2asm/helpers"
	"fmt"
)

// ── Rocket (clownlzss) ────────────────────────────────────────────────────────
// Header: BE16 uncompressed size, BE16 compressed size.
// BitField 1-byte, LSB first. Match: BE16; dict=(word+0x40)%0x400; count=(word>>10)+1.

func DecompressRocket(src []byte) ([]byte, error) {
	if len(src) < 4 {
		return nil, fmt.Errorf("rocket: too short")
	}
	uncompSize := int(binary.BigEndian.Uint16(src[0:2]))
	compSize := int(binary.BigEndian.Uint16(src[2:4]))
	pos := 4
	var out []byte
	var descByte byte
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
			descByte = read()
			descBitsLeft = 8
		}
		bit := int(descByte & 1)
		descByte >>= 1
		descBitsLeft--
		return bit
	}
	inputEnd := 4 + compSize
	for pos < inputEnd && len(out) < uncompSize {
		if popBit() == 1 {
			out = append(out, read())
		} else {
			hi := int(read())
			lo := int(read())
			word := (hi << 8) | lo
			dictIdx := (word + 0x40) & 0x3FF
			count := (word >> 10) + 1
			dist := ((0x400 + len(out) - dictIdx - 1) & 0x3FF) + 1
			helpers.CopyDist(&out, dist, count)
		}
	}
	if len(out) > uncompSize {
		out = out[:uncompSize]
	}
	return out, nil
}
