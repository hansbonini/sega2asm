package compress

import "fmt"

// DecompressMixedEnigma decompresses data using the Enigma (clownlzss) format,
// designed for encoding Mega Drive VDP block map data as incrementing or literal words.
//
// Header:
//
//	[0]    inline_bits  — number of bits inlined per symbol
//	[1]    render_flags — bitmask applied during inline-bit blending
//	[2..3] incr_word    — big-endian initial value for the auto-incrementing counter
//	[4..5] lit_word     — big-endian initial literal word value
//
// Control stream: 8-bit descriptor byte, MSB first. For each bit:
//
//	bit=1 → read inline_bits from stream, blend into incr_word (masked by render_flags), emit result
//	bit=0 → read 3 sub-bits:
//	          00 = emit current lit_word
//	          01 = emit incr_word
//	          10 = read 2 bytes → new lit_word, emit it
//	          11 = read 2 bytes → new incr_word
func DecompressMixedEnigma(src []byte) ([]byte, error) {
	if len(src) < 6 {
		return nil, fmt.Errorf("mixedenigma: too short")
	}
	pos := 0
	readByte := func() (byte, bool) {
		if pos >= len(src) {
			return 0, false
		}
		b := src[pos]
		pos++
		return b, true
	}
	readBE16 := func() (uint16, bool) {
		hi, ok1 := readByte()
		lo, ok2 := readByte()
		return uint16(hi)<<8 | uint16(lo), ok1 && ok2
	}
	totalInlineBits, _ := readByte()
	renderFlagsMask, _ := readByte()
	incrWord, _ := readBE16()
	litWord, _ := readBE16()
	var descByte byte
	descBitsLeft := 0
	popBit := func() (int, bool) {
		if descBitsLeft == 0 {
			b, ok := readByte()
			if !ok {
				return 0, false
			}
			descByte = b
			descBitsLeft = 8
		}
		bit := int((descByte >> 7) & 1)
		descByte <<= 1
		descBitsLeft--
		return bit, true
	}
	popBitsU := func(n int) (uint, bool) {
		v := uint(0)
		for i := 0; i < n; i++ {
			b, ok := popBit()
			if !ok {
				return v, false
			}
			v = (v << 1) | uint(b)
		}
		return v, true
	}
	var out []byte
	writeU16BE := func(w uint16) { out = append(out, byte(w>>8), byte(w)) }
	getInlineValue := func() (uint16, bool) {
		renderFlags := uint(0)
		for i := 0; i < 5; i++ {
			renderFlags <<= 1
			if renderFlagsMask&(1<<uint(5-i-1)) != 0 {
				b, ok := popBit()
				if !ok {
					return 0, false
				}
				renderFlags |= uint(b)
			}
		}
		renderFlags <<= 11
		tileIdx, ok := popBitsU(int(totalInlineBits))
		if !ok {
			return 0, false
		}
		return uint16(renderFlags | tileIdx), true
	}
	for {
		b0, ok := popBit()
		if !ok {
			break
		}
		var action uint
		if b0 == 1 {
			hi2, ok := popBitsU(2)
			if !ok {
				break
			}
			action = 2 + hi2
		} else {
			b1, ok := popBit()
			if !ok {
				break
			}
			action = uint(b1)
		}
		cnt, ok := popBitsU(4)
		if !ok {
			break
		}
		count := int(cnt) + 1
		if action == 5 && count == 16 {
			break
		}
		switch action {
		case 0:
			for i := 0; i < count; i++ {
				writeU16BE(incrWord)
				incrWord++
			}
		case 1:
			for i := 0; i < count; i++ {
				writeU16BE(litWord)
			}
		case 2:
			v, ok := getInlineValue()
			if !ok {
				goto enigmaDone
			}
			for i := 0; i < count; i++ {
				writeU16BE(v)
			}
		case 3:
			v, ok := getInlineValue()
			if !ok {
				goto enigmaDone
			}
			for i := 0; i < count; i++ {
				writeU16BE(v)
				v++
			}
		case 4:
			v, ok := getInlineValue()
			if !ok {
				goto enigmaDone
			}
			for i := 0; i < count; i++ {
				writeU16BE(v)
				v--
			}
		case 5:
			for i := 0; i < count; i++ {
				v, ok := getInlineValue()
				if !ok {
					goto enigmaDone
				}
				writeU16BE(v)
			}
		}
	}
enigmaDone:
	return out, nil
}
