// Package compress implements decompressors used in Sega Mega Drive ROMs.
// References: clownnemesis, clownlzss (Clownacy), RNC spec.
package compress

import (
	"encoding/binary"
	"fmt"
	"sort"
)

// ── Ring-buffer helper ─────────────────────────────────────────────────────────

type winBuf struct {
	data   []byte
	size   int
	mask   int
	cursor int
}

func newWin(size, cursor, fill int) *winBuf {
	w := &winBuf{data: make([]byte, size), size: size, mask: size - 1, cursor: cursor}
	for i := range w.data {
		w.data[i] = byte(fill)
	}
	return w
}

func (w *winBuf) emit(b byte, out *[]byte) {
	*out = append(*out, b)
	w.data[w.cursor] = b
	w.cursor = (w.cursor + 1) & w.mask
}

func (w *winBuf) copyFrom(offset, count int, out *[]byte) {
	for i := 0; i < count; i++ {
		b := w.data[(offset+i)&w.mask]
		w.emit(b, out)
	}
}

// copyDist copies count bytes from distance bytes behind the current end of out.
func copyDist(out *[]byte, distance, count int) {
	base := len(*out) - distance
	for i := 0; i < count; i++ {
		idx := base + i
		if idx < 0 {
			*out = append(*out, 0)
		} else {
			*out = append(*out, (*out)[idx])
		}
	}
}

// ── Nemesis ───────────────────────────────────────────────────────────────────

func DecompressNemesis(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("nemesis: data too short")
	}
	header := binary.BigEndian.Uint16(src[0:2])
	xorMode := (header & 0x8000) != 0
	totalTiles := int(header & 0x7FFF)
	pos := 2
	type nybbleRun struct{ codeBits, value, length byte }
	var runs [256]nybbleRun
	var curValue byte
	for pos < len(src) {
		b := src[pos]
		pos++
		if b == 0xFF {
			break
		}
		if b&0x80 != 0 {
			curValue = b & 0x0F
			continue
		}
		runLen := ((b >> 4) & 7) + 1
		codeBits := b & 0x0F
		if pos >= len(src) {
			break
		}
		code := src[pos]
		pos++
		if codeBits == 0 || codeBits > 8 {
			return nil, fmt.Errorf("nemesis: invalid code_bits=%d", codeBits)
		}
		idx := int(code) << (8 - int(codeBits))
		if idx >= 256 {
			return nil, fmt.Errorf("nemesis: code table index OOB")
		}
		runs[idx] = nybbleRun{codeBits: codeBits, value: curValue, length: runLen}
	}
	var bitsBuf byte
	bitsAvail := 0
	popBit := func() (int, bool) {
		bitsBuf <<= 1
		if bitsAvail == 0 {
			if pos >= len(src) {
				return 0, false
			}
			bitsBuf = src[pos]
			pos++
			bitsAvail = 8
		}
		bitsAvail--
		if bitsBuf&0x80 != 0 {
			return 1, true
		}
		return 0, true
	}
	popBits := func(n int) (int, bool) {
		v := 0
		for i := 0; i < n; i++ {
			b, ok := popBit()
			if !ok {
				return v, false
			}
			v = (v << 1) | b
		}
		return v, true
	}
	var outBuf, prevBuf [4]byte
	nybbleDone := 0
	var out []byte
	outputNybble := func(nyb byte) {
		shift := uint(28 - (nybbleDone%8)*4)
		var acc uint32
		if nybbleDone%8 != 0 {
			acc = uint32(outBuf[0])<<24 | uint32(outBuf[1])<<16 | uint32(outBuf[2])<<8 | uint32(outBuf[3])
		}
		acc = (acc &^ (0xF << shift)) | (uint32(nyb&0xF) << shift)
		outBuf[0] = byte(acc >> 24)
		outBuf[1] = byte(acc >> 16)
		outBuf[2] = byte(acc >> 8)
		outBuf[3] = byte(acc)
		nybbleDone++
		if nybbleDone%8 == 0 {
			var final [4]byte
			if xorMode {
				for i := range final {
					final[i] = outBuf[i] ^ prevBuf[i]
				}
			} else {
				final = outBuf
			}
			prevBuf = final
			out = append(out, final[:]...)
			outBuf = [4]byte{}
		}
	}
	nybsRemaining := totalTiles * 64
	for nybsRemaining > 0 {
		code := 0
		var run *nybbleRun
		for n := 1; n <= 8; n++ {
			b, ok := popBit()
			if !ok {
				goto done
			}
			code = (code << 1) | b
			if n == 6 && code == 0x3F {
				runLen, ok1 := popBits(3)
				nyb, ok2 := popBits(4)
				if !ok1 || !ok2 {
					goto done
				}
				runLen++
				for i := 0; i < runLen && nybsRemaining > 0; i++ {
					outputNybble(byte(nyb))
					nybsRemaining--
				}
				run = nil
				goto nextRun
			}
			idx := code << (8 - n)
			r := &runs[idx]
			if r.length != 0 && int(r.codeBits) == n {
				run = r
				break
			}
		}
		if run == nil {
			return out, fmt.Errorf("nemesis: no code match")
		}
		for i := 0; i < int(run.length) && nybsRemaining > 0; i++ {
			outputNybble(run.value)
			nybsRemaining--
		}
		continue
	nextRun:
	}
done:
	return out, nil
}

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
			copyDist(&out, offset, count)
		} else {
			offset := 0x100 - int(read())
			count := 2
			if popBit() == 1 {
				count += 2
			}
			if popBit() == 1 {
				count++
			}
			copyDist(&out, offset, count)
		}
	}
	return out, nil
}

// ── Enigma (clownlzss) ────────────────────────────────────────────────────────

func DecompressEnigma(src []byte) ([]byte, error) {
	if len(src) < 6 {
		return nil, fmt.Errorf("enigma: too short")
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

// ── SegaRD ────────────────────────────────────────────────────────────────────

func DecompressSegaRD(src []byte) ([]byte, error) {
	var out []byte
	pos := 0
	read1 := func() (byte, bool) {
		if pos >= len(src) {
			return 0, false
		}
		b := src[pos]
		pos++
		return b, true
	}
	readU32BE := func() (uint32, bool) {
		if pos+4 > len(src) {
			return 0, false
		}
		v := uint32(src[pos])<<24 | uint32(src[pos+1])<<16 | uint32(src[pos+2])<<8 | uint32(src[pos+3])
		pos += 4
		return v, true
	}
	var window [32]byte
	for {
		count, ok := read1()
		if !ok {
			break
		}
		if count == 0xFF {
			break
		}
		var pattern uint32
		for i := uint8(0); i < count; i++ {
			a, ok := read1()
			if !ok {
				return out, fmt.Errorf("segard: EOF color")
			}
			b, ok := readU32BE()
			if !ok {
				return out, fmt.Errorf("segard: EOF mask")
			}
			pattern |= b
			k := 0
			for y := 31; y >= 0; y-- {
				if (b>>uint(y))&1 == 1 {
					window[k] = a
				}
				k++
			}
		}
		if pattern != 0xFFFFFFFF {
			x := 0
			for y := 31; y >= 0; y-- {
				if (pattern>>uint(y))&1 == 0 {
					b, ok := read1()
					if !ok {
						return out, fmt.Errorf("segard: EOF literal")
					}
					window[x] = b
				}
				x++
			}
		}
		out = append(out, window[:]...)
	}
	return out, nil
}

// ── Saxman (clownlzss) ────────────────────────────────────────────────────────

func DecompressSaxman(src []byte) ([]byte, error)         { return decompressSaxman(src, true) }
func DecompressSaxmanNoHeader(src []byte) ([]byte, error) { return decompressSaxman(src, false) }

func decompressSaxman(src []byte, hasHeader bool) ([]byte, error) {
	var data []byte
	if hasHeader {
		if len(src) < 2 {
			return nil, fmt.Errorf("saxman: too short")
		}
		n := int(binary.LittleEndian.Uint16(src[0:2]))
		end := 2 + n
		if end > len(src) {
			end = len(src)
		}
		data = src[2:end]
	} else {
		data = src
	}
	pos := 0
	var out []byte
	var descByte byte
	descBitsLeft := 0
	read := func() byte {
		if pos >= len(data) {
			return 0
		}
		b := data[pos]
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
	for pos < len(data) {
		if popBit() == 1 {
			out = append(out, read())
		} else {
			b1 := int(read())
			b2 := int(read())
			dictIdx := (b1 | ((b2 << 4) & 0xF00)) + 18
			count := (b2 & 0xF) + 3
			outPos := len(out)
			dist := (outPos - dictIdx%0x1000 + 0x1000) % 0x1000
			if dist == 0 || dist > outPos {
				for i := 0; i < count; i++ {
					out = append(out, 0)
				}
			} else {
				base := outPos - dist
				for i := 0; i < count; i++ {
					out = append(out, out[base+i])
				}
			}
		}
	}
	return out, nil
}

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
			copyDist(&out, dist, count)
		}
	}
	if len(out) > uncompSize {
		out = out[:uncompSize]
	}
	return out, nil
}

// ── Faxman (clownlzss) ────────────────────────────────────────────────────────
// Header: LE16 descriptor-bit count. BitField 1-byte LE, LSB first.
// Out-of-bounds refs → zero-fill.

func DecompressFaxman(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("faxman: too short")
	}
	remaining := int(binary.LittleEndian.Uint16(src[0:2]))
	pos := 2
	var out []byte
	var descByte byte
	descBitsLeft := 0
	startLen := 0
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
		remaining--
		bit := int(descByte & 1)
		descByte >>= 1
		descBitsLeft--
		return bit
	}
	zeroOrCopy := func(distance, count int) {
		if distance > len(out)-startLen {
			for i := 0; i < count; i++ {
				out = append(out, 0)
			}
		} else {
			copyDist(&out, distance, count)
		}
	}
	for remaining > 0 {
		if popBit() == 1 {
			out = append(out, read())
		} else {
			if popBit() == 1 {
				b1 := int(read())
				b2 := int(read())
				zeroOrCopy((b1|((b2<<3)&0x700))+1, (b2&0x1F)+3)
			} else {
				dist := 0x100 - int(read())
				count := 2
				if popBit() == 1 {
					count += 2
				}
				if popBit() == 1 {
					count++
				}
				zeroOrCopy(dist, count)
			}
		}
	}
	return out, nil
}

// ── Rage (clownlzss) — Streets of Rage ───────────────────────────────────────
// Header: LE16 compressed size. Command byte bits7:5 encode action.

func DecompressRage(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("rage: too short")
	}
	compSize := int(binary.LittleEndian.Uint16(src[0:2]))
	pos := 2
	end := 2 + compSize
	if end > len(src) {
		end = len(src)
	}
	var out []byte
	lastDist := 0
	read := func() byte {
		if pos >= end {
			return 0
		}
		b := src[pos]
		pos++
		return b
	}
	for pos < end {
		first := int(read())
		switch first >> 5 {
		case 0:
			for i := 0; i < first&0x1F; i++ {
				out = append(out, read())
			}
		case 1:
			count := ((first & 0x1F) << 8) | int(read())
			for i := 0; i < count; i++ {
				out = append(out, read())
			}
		case 2:
			var count int
			if first&0x10 != 0 {
				count = 4 + (((first & 0xF) << 8) | int(read()))
			} else {
				count = 4 + (first & 0xF)
			}
			val := read()
			for i := 0; i < count; i++ {
				out = append(out, val)
			}
		case 3:
			count := first & 0x1F
			if lastDist > 0 {
				copyDist(&out, lastDist, count)
			}
		default:
			second := int(read())
			count := ((first >> 5) & 3) + 4
			lastDist = ((first << 8) & 0x1F00) | second
			if lastDist > 0 {
				copyDist(&out, lastDist, count)
			}
		}
	}
	return out, nil
}

// ── Chameleon (clownlzss) ─────────────────────────────────────────────────────
// Header: BE16 offset from pos+2 to literal stream. Descriptor and data in separate sub-streams.

func DecompressChameleon(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("chameleon: too short")
	}
	offset := int(binary.BigEndian.Uint16(src[0:2]))
	descPos := 2
	dataPos := 2 + offset
	var descByte byte
	descBitsLeft := 0
	readDesc := func() byte {
		if descPos >= len(src) {
			return 0
		}
		b := src[descPos]
		descPos++
		return b
	}
	readData := func() byte {
		if dataPos >= len(src) {
			return 0
		}
		b := src[dataPos]
		dataPos++
		return b
	}
	descPop := func() int {
		if descBitsLeft == 0 {
			descByte = readDesc()
			descBitsLeft = 8
		}
		bit := int((descByte >> 7) & 1)
		descByte <<= 1
		descBitsLeft--
		return bit
	}
	var out []byte
	for {
		if descPop() == 1 {
			out = append(out, readData())
		} else {
			dist := int(readData())
			var count int
			if descPop() == 0 {
				count = 2 + descPop()
			} else {
				if descPop() == 1 {
					dist += 1 << 10
				}
				if descPop() == 1 {
					dist += 1 << 9
				}
				if descPop() == 1 {
					dist += 1 << 8
				}
				if descPop() == 0 {
					if descPop() == 0 {
						count = 3
					} else {
						count = 4
					}
				} else {
					if descPop() == 0 {
						count = 5
					} else {
						count = int(readData())
						if count < 6 {
							break
						}
					}
				}
			}
			if dist > 0 {
				copyDist(&out, dist, count)
			}
		}
	}
	return out, nil
}

// ── LZNamco ─ Ball Jacks, Klax, Marvel Land, Pac-Attack, PacMan2, Phelios …──
// Window 0x1000, cursor 0xFEE, fill 0x00. Header: BE16 uncompressed size.
// 8-bit ctrl (LSB first). bit=1→literal; bit=0→match BE16: len=(lo&0xF)+3, offset=((lo&0xF0)<<4)|hi.

func DecompressLZNamco(src []byte) ([]byte, error) { return decompressNamco(src, 0x1000, 0xFEE) }

// LZStrike — Desert/Jungle/Urban Strike. Same as Namco but window=0x800.
func DecompressLZStrike(src []byte) ([]byte, error) { return decompressNamco(src, 0x800, 0x7EE) }

func decompressNamco(src []byte, winSize, winCursor int) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("lznamco: too short")
	}
	uncompSize := int(binary.BigEndian.Uint16(src[0:2]))
	pos := 2
	win := newWin(winSize, winCursor, 0)
	var out []byte
	decoded := 0
	read := func() byte {
		if pos >= len(src) {
			return 0
		}
		b := src[pos]
		pos++
		return b
	}
	for decoded < uncompSize {
		ctrl := read()
		for bit := 0; bit < 8 && decoded < uncompSize; bit++ {
			if (ctrl>>uint(bit))&1 == 1 {
				b := read()
				win.emit(b, &out)
				decoded++
			} else {
				hi := int(read())
				lo := int(read())
				length := (lo & 0xF) + 3
				offset := ((lo & 0xF0) << 4) | hi
				win.copyFrom(offset, length, &out)
				decoded += length
			}
		}
	}
	return out, nil
}

// LZTechnosoft — Elemental Master. Same encoding but NO size header; consumes all src.
func DecompressLZTechnosoft(src []byte) ([]byte, error) {
	pos := 0
	win := newWin(0x1000, 0xFEE, 0)
	var out []byte
	read := func() byte {
		if pos >= len(src) {
			return 0
		}
		b := src[pos]
		pos++
		return b
	}
	consumed := 0
	for consumed < len(src) {
		ctrl := read()
		consumed++
		for bit := 0; bit < 8 && consumed < len(src); bit++ {
			if (ctrl>>uint(bit))&1 == 1 {
				b := read()
				consumed++
				win.emit(b, &out)
			} else {
				hi := int(read())
				lo := int(read())
				consumed += 2
				length := (lo & 0xF) + 3
				offset := ((lo & 0xF0) << 4) | hi
				win.copyFrom(offset, length, &out)
			}
		}
	}
	return out, nil
}

// ── LZKonami1 — Animaniacs, Contra Hard Corps, Lethal Enforcers II, Sparkster ─
// Window 0x400 cursor 0x3C0 fill 0x20. Header: BE16 uncompressed size.
// 8-bit ctrl (LSB first). For each bit: always read one byte.
//   bit=0 → literal; bit=1, byte=0x1F → end; >0x80 → long ref (+1); 0x80 → short ref.

func DecompressLZKonami1(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("lzkonami1: too short")
	}
	uncompSize := int(binary.BigEndian.Uint16(src[0:2]))
	pos := 2
	win := newWin(0x400, 0x3C0, 0x20)
	var out []byte
	decoded := 0
	read := func() byte {
		if pos >= len(src) {
			return 0
		}
		b := src[pos]
		pos++
		return b
	}
outer1:
	for decoded < uncompSize {
		ctrl := read()
		for bit := 0; bit < 8 && decoded < uncompSize; bit++ {
			r := read()
			if (ctrl>>uint(bit))&1 == 1 {
				if r == 0x1F {
					break outer1
				}
				if r > 0x80 {
					length := int(r&0x1F) + 3
					low := int(read())
					offset := ((int(r)<<3)&0xFF00 | low) & win.mask
					win.copyFrom(offset, length, &out)
					decoded += length
				} else if r == 0x80 {
					length := int(r>>4) - 6
					offset := (win.cursor - int(r&0xF) + win.size) & win.mask
					win.copyFrom(offset, length, &out)
					decoded += length
				}
				// r < 0x80 (not 0x1F): undefined per reference, ignore
			} else {
				win.emit(r, &out)
				decoded++
			}
		}
	}
	return out, nil
}

// ── LZKonami2 — Castlevania Bloodlines, Rocket Knight, TMNT Hyperstone, SunsetRiders …
// Window 0x400 cursor 0x3C0 fill 0x20. Header: BE16 compressed size.
// 8-bit ctrl (LSB first). bit=1→literal; bit=0→BE16: len=((word&0xFC00)>>10)+1; offset=word&0x3FF.

func DecompressLZKonami2(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("lzkonami2: too short")
	}
	compSize := int(binary.BigEndian.Uint16(src[0:2]))
	pos := 2
	end := pos + compSize
	if end > len(src) {
		end = len(src)
	}
	win := newWin(0x400, 0x3C0, 0x20)
	var out []byte
	read := func() byte {
		if pos >= end {
			return 0
		}
		b := src[pos]
		pos++
		return b
	}
	for pos < end {
		ctrl := read()
		for bit := 0; bit < 8 && pos <= end; bit++ {
			if (ctrl>>uint(bit))&1 == 1 {
				b := read()
				win.emit(b, &out)
			} else {
				hi := int(read())
				lo := int(read())
				word := (hi << 8) | lo
				length := ((word & 0xFC00) >> 10) + 1
				offset := word & 0x3FF
				win.copyFrom(offset, length, &out)
			}
		}
	}
	return out, nil
}

// ── LZKonami3 — Castlevania Bloodlines, Lethal Enforcers, TMNT Tournament Fighters …
// Window 0x400 cursor 0x3DF. Header: BE16 uncompressed size.
// bit=0→literal; bit=1:
//   0x1F→end; <0x80→long ref(+1); 0x80–0xBF→short ref; 0xC0–0xFF→run from stream.

func DecompressLZKonami3(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("lzkonami3: too short")
	}
	uncompSize := int(binary.BigEndian.Uint16(src[0:2]))
	pos := 2
	win := newWin(0x400, 0x3DF, 0)
	var out []byte
	decoded := 0
	read := func() byte {
		if pos >= len(src) {
			return 0
		}
		b := src[pos]
		pos++
		return b
	}
outer3:
	for decoded < uncompSize {
		ctrl := read()
		for bit := 0; bit < 8 && decoded < uncompSize; bit++ {
			r := read()
			if (ctrl>>uint(bit))&1 == 1 {
				if r == 0x1F {
					break outer3
				}
				if r < 0x80 {
					length := int(r&0x1F) + 3
					low := int(read())
					offset := (((int(r) & 0x60) << 3) | low) & win.mask
					win.copyFrom(offset, length, &out)
					decoded += length
				} else if r <= 0xBF {
					length := ((int(r) >> 4) & 0x3) + 2
					offset := (win.cursor - int(r&0xF) + win.size) & win.mask
					win.copyFrom(offset, length, &out)
					decoded += length
				} else {
					length := int(r&0x3F) + 8
					for i := 0; i < length && decoded < uncompSize; i++ {
						b := read()
						win.emit(b, &out)
						decoded++
					}
				}
			} else {
				win.emit(r, &out)
				decoded++
			}
		}
	}
	return out, nil
}

// ── LZAncient — Beyond Oasis, Streets of Rage 2 ───────────────────────────────
// Header: LE16 compressed size. byte[2]==0 → empty. No descriptor bitstream;
// control byte bits7:6 encode type: 0b10=LZ, 0b01=RLE, 0b00=RAW.

func DecompressLZAncient(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("lzancient: too short")
	}
	compSize := int(binary.LittleEndian.Uint16(src[0:2]))
	if len(src) >= 3 && src[2] == 0 {
		return []byte{}, nil
	}
	pos := 2
	end := compSize
	if end > len(src) {
		end = len(src)
	}
	var out []byte
	read := func() byte {
		if pos >= end {
			return 0
		}
		b := src[pos]
		pos++
		return b
	}
	bitClear := func(v, idx int) int {
		if (v>>uint(idx))&1 != 0 {
			return v ^ (1 << uint(idx))
		}
		return v
	}
	rotL := func(v, n int) int { n %= 8; return ((v << uint(n)) & 0xFF) | ((v & 0xFF) >> uint(8-n)) }
	for pos < end {
		ctrl := int(read())
		if ctrl&0x80 != 0 {
			ctrl = bitClear(ctrl, 7)
			repeats := rotL(ctrl&0x60, 3) + 4
			next := int(read())
			position := ((ctrl & 0x1F) << 8) | next
			if position > 0 {
				for i := 0; i < repeats; i++ {
					out = append(out, out[len(out)-position])
				}
			}
			for {
				ctrl2 := int(read())
				if (ctrl2 & 0xE0) == 0x60 {
					extra := ctrl2 & 0x1F
					for i := 0; i < extra; i++ {
						out = append(out, out[len(out)-position])
					}
				} else {
					pos--
					break
				}
			}
		} else if ctrl&0x40 != 0 {
			ctrl = bitClear(ctrl, 6)
			var repeats int
			if bitClear(ctrl, 4) == ctrl {
				repeats = ctrl + 4
			} else {
				ctrl = bitClear(ctrl, 4)
				repeats = ((ctrl << 8) | int(read())) + 4
			}
			val := read()
			for i := 0; i < repeats; i++ {
				out = append(out, val)
			}
		} else {
			var length int
			if bitClear(ctrl, 5) == ctrl {
				length = ctrl
			} else {
				length = int(read())
			}
			for i := 0; i < length; i++ {
				out = append(out, read())
			}
		}
	}
	return out, nil
}

// ── LZTose — Dragon Ball Z: Buyuu Retsuden ────────────────────────────────────
// Window 0x2000 cursor 0. Header: LE16 (uncompressed_size-1)|bit15.
// 8-bit ctrl (LSB first). Match: 2 bytes LE; len=(lo&0xF)+3; offset=word>>4.

func DecompressLZTose(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("lztose: too short")
	}
	hdr := binary.LittleEndian.Uint16(src[0:2])
	uncompSize := int(hdr&0x7FFF) + 1
	pos := 2
	win := newWin(0x2000, 0, 0)
	var out []byte
	decoded := 0
	read := func() byte {
		if pos >= len(src) {
			return 0
		}
		b := src[pos]
		pos++
		return b
	}
	for decoded < uncompSize {
		ctrl := read()
		for bit := 0; bit < 8 && decoded < uncompSize; bit++ {
			if (ctrl>>uint(bit))&1 == 1 {
				b := read()
				win.emit(b, &out)
				decoded++
			} else {
				lo := int(read())
				hi := int(read())
				length := (lo & 0xF) + 3
				offset := ((hi << 8) | lo) >> 4
				base := (win.cursor - offset + win.size) & win.mask
				win.copyFrom(base, length, &out)
				decoded += length
			}
		}
	}
	if len(out) > uncompSize {
		out = out[:uncompSize]
	}
	return out, nil
}

// ── LZNextech — Crusader of Centy ────────────────────────────────────────────
// ── LZWolfteam — El Viento, Granada, Earnest Evans, Final Zone, Ranger-X, Zan Yasha
// Both: window 0x1000 cursor 0xFEE, special init. Header: LE32 compSize + LE32 uncompSize.
// Same back-ref encoding as LZNamco.

func DecompressLZNextech(src []byte) ([]byte, error)  { return decompressNextech(src) }
func DecompressLZWolfteam(src []byte) ([]byte, error) { return decompressNextech(src) }

func decompressNextech(src []byte) ([]byte, error) {
	if len(src) < 8 {
		return nil, fmt.Errorf("lznextech: too short")
	}
	uncompSize := int(binary.LittleEndian.Uint32(src[4:8]))
	pos := 8
	win := newWin(0x1000, 0xFEE, 0)
	initWindowNextech(win)
	var out []byte
	decoded := 0
	read := func() byte {
		if pos >= len(src) {
			return 0
		}
		b := src[pos]
		pos++
		return b
	}
	for decoded < uncompSize {
		ctrl := read()
		for bit := 0; bit < 8 && decoded < uncompSize; bit++ {
			if (ctrl>>uint(bit))&1 == 1 {
				b := read()
				win.emit(b, &out)
				decoded++
			} else {
				hi := int(read())
				lo := int(read())
				length := (lo & 0xF) + 3
				offset := ((lo & 0xF0) << 4) | hi
				win.copyFrom(offset, length, &out)
				decoded += length
			}
		}
	}
	if len(out) > uncompSize {
		out = out[:uncompSize]
	}
	return out, nil
}

func initWindowNextech(w *winBuf) {
	for i := 0; i < 0x100; i++ {
		for j := 0; j < 0x0D && i*0x0D+j < w.size; j++ {
			w.data[i*0x0D+j] = byte(i)
		}
		if 0xD00+i < w.size {
			w.data[0xD00+i] = byte(i)
		}
		if 0xE00+i < w.size {
			w.data[0xE00+i] = byte(0xFF - i)
		}
		if i < 0x80 && 0xF00+i < w.size {
			w.data[0xF00+i] = 0x00
		}
		if i < 0x6E {
			w.data[i] = 0x20
		}
	}
	w.cursor = 0xFEE
}

// ── LZSTI — Comix Zone ────────────────────────────────────────────────────────
// Window 0x400 cursor 0. Header: BE16 uncompressed size. Bit-packed stream (MSB first).
// bit=1→8-bit literal; bit=0→10-bit offset, 4-bit (len-2).

func DecompressLZSTI(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("lzsti: too short")
	}
	uncompSize := int(binary.BigEndian.Uint16(src[0:2]))
	win := newWin(0x400, 0, 0)
	var out []byte
	data := src[2:]
	bytePos, bitBuf, bitsAvail := 0, 0, 0
	readBit := func() int {
		if bitsAvail == 0 {
			if bytePos >= len(data) {
				return 0
			}
			bitBuf = int(data[bytePos])
			bytePos++
			bitsAvail = 8
		}
		bitsAvail--
		return (bitBuf >> uint(bitsAvail)) & 1
	}
	readBits := func(n int) int {
		v := 0
		for i := 0; i < n; i++ {
			v = (v << 1) | readBit()
		}
		return v
	}
	decoded := 0
	for decoded < uncompSize {
		if readBit() == 1 {
			b := byte(readBits(8))
			win.emit(b, &out)
			decoded++
		} else {
			offset := readBits(10)
			length := readBits(4) + 2
			win.copyFrom(offset, length, &out)
			decoded += length
		}
	}
	if len(out) > uncompSize {
		out = out[:uncompSize]
	}
	return out, nil
}

// ── RLESoftwareCreations — Maximum Carnage, Venom, The Tick, Cutthroat Island ──
// src[0] = escape byte. Whenever escape appears twice → (value, count) follows.

func DecompressRLESoftwareCreations(src []byte) ([]byte, error) {
	if len(src) < 1 {
		return nil, fmt.Errorf("rlesc: too short")
	}
	escape := src[0]
	pos := 1
	remaining := len(src) - 1
	var out []byte
	for remaining > 0 && pos < len(src) {
		b := src[pos]
		pos++
		if b == escape {
			if pos+1 >= len(src) {
				break
			}
			val := src[pos]
			pos++
			length := int(src[pos])
			pos++
			for i := 0; i < length; i++ {
				out = append(out, val)
			}
			remaining -= 3
		} else {
			out = append(out, b)
			remaining--
		}
	}
	return out, nil
}

// ── RNC — Rob Northen Compression  (Method 1 & 2) ────────────────────────────
//
// 18-byte header:
//   [0..2]  "RNC"
//   [3]     method (0x01 or 0x02)
//   [4..7]  unpacked size  BE32
//   [8..11] packed size    BE32
//   [12..13] unpacked CRC16 (not verified)
//   [14..15] packed CRC16  (not verified)
//   [16]    leeway
//   [17]    pack_chunks  (Method 1 only)

// rncBR is a byte-by-byte bit reader that pops from LSB first.
type rncBR struct {
	src   []byte
	pos   int
	buf   uint64
	avail int
}

func (r *rncBR) fill() {
	for r.avail <= 56 && r.pos < len(r.src) {
		r.buf |= uint64(r.src[r.pos]) << uint(r.avail)
		r.pos++
		r.avail += 8
	}
}
func (r *rncBR) pop(n int) int {
	if n == 0 {
		return 0
	}
	r.fill()
	v := int(r.buf & ((1 << uint(n)) - 1))
	r.buf >>= uint(n)
	r.avail -= n
	return v
}
func (r *rncBR) alignByte() {
	if r.avail%8 != 0 {
		r.pop(r.avail % 8)
	}
}

type rncHuff struct{ revCode, length, symbol int }

func buildRNCTable(br *rncBR) []rncHuff {
	n := br.pop(5)
	if n == 0 {
		return nil
	}
	lengths := make([]int, n)
	for i := range lengths {
		lengths[i] = br.pop(4)
	}
	type e struct{ length, index int }
	var entries []e
	for i, l := range lengths {
		if l > 0 {
			entries = append(entries, e{l, i})
		}
	}
	sort.SliceStable(entries, func(i, j int) bool {
		if entries[i].length != entries[j].length {
			return entries[i].length < entries[j].length
		}
		return entries[i].index < entries[j].index
	})
	codes := make([]rncHuff, len(entries))
	code, prevLen := 0, 0
	for i, e := range entries {
		if prevLen > 0 {
			code++
			if e.length > prevLen {
				code <<= uint(e.length - prevLen)
			}
		}
		rev, c := 0, code
		for j := 0; j < e.length; j++ {
			rev = (rev << 1) | (c & 1)
			c >>= 1
		}
		codes[i] = rncHuff{revCode: rev, length: e.length, symbol: e.index}
		prevLen = e.length
	}
	return codes
}

func decodeRNC(br *rncBR, table []rncHuff) int {
	if len(table) == 0 {
		return 0
	}
	maxLen := 0
	for _, c := range table {
		if c.length > maxLen {
			maxLen = c.length
		}
	}
	acc := 0
	for n := 1; n <= maxLen; n++ {
		acc |= br.pop(1) << (n - 1)
		for _, c := range table {
			if c.length == n && c.revCode == acc {
				return c.symbol
			}
		}
	}
	return 0
}

// DecompressRNC1 decompresses RNC Method 1 (Huffman + LZ).
func DecompressRNC1(src []byte) ([]byte, error) {
	if len(src) < 18 {
		return nil, fmt.Errorf("rnc1: header too short")
	}
	if src[0] != 'R' || src[1] != 'N' || src[2] != 'C' || src[3] != 0x01 {
		return nil, fmt.Errorf("rnc1: bad magic/method")
	}
	unpackedSize := int(binary.BigEndian.Uint32(src[4:8]))
	chunks := int(src[17])
	br := &rncBR{src: src, pos: 18}
	out := make([]byte, 0, unpackedSize)
	for ch := 0; ch < chunks; ch++ {
		br.alignByte()
		rawTable := buildRNCTable(br)
		posTable := buildRNCTable(br)
		lenTable := buildRNCTable(br)
		numCmds := br.pop(16)
		for cmd := 0; cmd <= numCmds; cmd++ {
			rawCount := decodeRNC(br, rawTable)
			for i := 0; i < rawCount; i++ {
				out = append(out, byte(br.pop(8)))
			}
			if cmd < numCmds {
				dist := decodeRNC(br, posTable) + 1
				copyLen := decodeRNC(br, lenTable) + 2
				copyDist(&out, dist, copyLen)
			}
		}
	}
	if len(out) > unpackedSize {
		out = out[:unpackedSize]
	}
	return out, nil
}

// DecompressRNC2 decompresses RNC Method 2 (variable-length LZ, no Huffman).
// Stream after header: 2 bits initial raw count; then loop: dist bits, back-ref, raw count bits.
func DecompressRNC2(src []byte) ([]byte, error) {
	if len(src) < 18 {
		return nil, fmt.Errorf("rnc2: header too short")
	}
	if src[0] != 'R' || src[1] != 'N' || src[2] != 'C' || src[3] != 0x02 {
		return nil, fmt.Errorf("rnc2: bad magic/method")
	}
	unpackedSize := int(binary.BigEndian.Uint32(src[4:8]))
	br := &rncBR{src: src, pos: 18}
	out := make([]byte, 0, unpackedSize)
	readRaw := func(n int) {
		for i := 0; i < n; i++ {
			out = append(out, byte(br.pop(8)))
		}
	}
	readRaw(br.pop(2)) // initial raw bytes
	for len(out) < unpackedSize {
		var d int
		if br.pop(1) == 0 {
			d = br.pop(8)
		} else {
			d = br.pop(14)
		}
		if d == 0 {
			break
		}
		count := br.pop(4) + 2
		copyDist(&out, d, count)
		switch br.pop(2) {
		case 1:
			readRaw(1)
		case 2:
			readRaw(2)
		case 3:
			readRaw(br.pop(8))
		}
	}
	if len(out) > unpackedSize {
		out = out[:unpackedSize]
	}
	return out, nil
}

// DecompressRNC auto-detects Method 1 or 2 from the header.
func DecompressRNC(src []byte) ([]byte, error) {
	if len(src) < 4 {
		return nil, fmt.Errorf("rnc: too short")
	}
	if src[0] != 'R' || src[1] != 'N' || src[2] != 'C' {
		return nil, fmt.Errorf("rnc: bad magic")
	}
	switch src[3] {
	case 0x01:
		return DecompressRNC1(src)
	case 0x02:
		return DecompressRNC2(src)
	default:
		return nil, fmt.Errorf("rnc: unknown method 0x%02X", src[3])
	}
}

// ── Dispatcher ────────────────────────────────────────────────────────────────
//
// Compression name strings accepted by the YAML `compression:` field:
//
//   Original:     nemesis  kosinski  kosinskiplus  enigma  segard
//   clownlzss:    saxman  saxman_noheader  comper  rocket  faxman  rage  chameleon
//   py-port:      lznamco  lzstrike  lztechnosoft
//                 lzkonami1  lzkonami2  lzkonami3
//                 lzancient  lztose  lznextech  lzwolfteam  lzsti  rlesc
//   RNC:          rnc  rnc1  rnc2
//   Pass-through: none  (empty)

// ── Compile (Puyo Puyo / Aleste / MUSHA etc.) ─────────────────────────────────
//
// Algorithm: command-byte stream with two modes.
//   cmd == 0x00             → end of stream
//   cmd & 0x80 == 0         → literal run: emit (cmd & 0x7F) bytes verbatim
//   cmd & 0x80 != 0         → back-reference: copy (cmd & 0x7F)+2 bytes from
//                              a 256-byte circular history starting at
//                              (histHead - offset - 1) & 0xFF
// Output is buffered in a 4-byte FIFO; each time the FIFO fills it is flushed
// to the output slice.  Output size is always a multiple of 4.
//
// Reference: https://github.com/Nasina7/PuyoComp/blob/main/src/decompress.rs
func DecompressLZCompile(src []byte) ([]byte, error) {
	if len(src) == 0 {
		return nil, fmt.Errorf("compile: empty input")
	}

	var (
		out     []byte
		arr1    [256]byte // 256-byte circular history
		arr1Ind int
		arr2    [4]byte // 4-byte output accumulator
		arr2Ind int
		ptr     int
	)

	emit := func(b byte) {
		arr2[arr2Ind] = b
		arr2Ind = (arr2Ind + 1) & 0xFF
		if arr2Ind&0x4 != 0 {
			arr2Ind = 0
			out = append(out, arr2[:]...)
		}
		arr1[arr1Ind] = b
		arr1Ind = (arr1Ind + 1) & 0xFF
	}

	for ptr < len(src) {
		cmd := int(src[ptr])
		ptr++

		if cmd == 0 {
			break
		}

		if cmd&0x80 != 0 {
			// Back-reference
			count := (cmd & 0x7F) + 2
			if ptr >= len(src) {
				return nil, fmt.Errorf("compile: truncated at back-reference offset byte")
			}
			offset := int(src[ptr])
			ptr++
			calcInd := (arr1Ind - offset - 1) & 0xFF
			for i := 0; i < count; i++ {
				emit(arr1[calcInd])
				calcInd = (calcInd + 1) & 0xFF
			}
		} else {
			// Literal run
			count := cmd & 0x7F
			for i := 0; i < count; i++ {
				if ptr >= len(src) {
					return nil, fmt.Errorf("compile: truncated at literal byte %d/%d", i+1, count)
				}
				emit(src[ptr])
				ptr++
			}
		}
	}

	return out, nil
}

// DecompressLZFactor5 decompresses data using the Factor 5 LZ format (version '1' or '2').
//
// Header layout:
//
//	[0..1] big-endian word  — high byte = version ('1', '2', or other)
//	[2..3] little-endian word — uncompressed size
//
// Version '1' back-reference token (b >= 0x80):
//
//	reps  = ((b >> 3) & 0xF) + 3   (3–18)
//	dist  = ((b & 7) << 8) | nextByte   (11-bit offset)
//
// Version '2' back-reference token (b >= 0x80):
//
//	reps  = (b & 0x7F) + 4          (4–131)
//	dist  = nextWord (big-endian)   (16-bit offset)
//
// Literal token (b < 0x80): copy (b & 0x7F)+1 bytes verbatim from input.
// If version is neither '1' nor '2', the payload is stored uncompressed.
// Reference: https://github.com/lab313ru/fact5lz/blob/master/main.c
func DecompressLZFactor5(src []byte) ([]byte, error) {
	if len(src) < 4 {
		return nil, fmt.Errorf("lzfactor5: input too short")
	}
	rpos := 0

	// 2-byte big-endian version word; only the low byte matters as the version char.
	ver := src[rpos+1]
	rpos += 2

	// 2-byte little-endian output size.
	outSize := int(src[rpos]) | int(src[rpos+1])<<8
	rpos += 2

	// Unrecognised version — stored verbatim.
	if ver != '1' && ver != '2' {
		end := rpos + outSize
		if end > len(src) {
			end = len(src)
		}
		out := make([]byte, end-rpos)
		copy(out, src[rpos:end])
		return out, nil
	}

	minLen := 3
	if ver == '2' {
		minLen = 4
	}

	out := make([]byte, 0, outSize)

	for len(out) < outSize {
		if rpos >= len(src) {
			break
		}
		b := src[rpos]
		rpos++

		if b&0x80 != 0 {
			// Back-reference.
			var reps, dist int
			if ver == '1' {
				// Token: 1rrrrfff  + 1 byte offset extension.
				reps = int((b>>3)&0xF) + minLen
				dist = int(b&7) << 8
				if rpos >= len(src) {
					break
				}
				dist |= int(src[rpos])
				rpos++
			} else {
				// Token: 1rrrrrrr  + 2 byte offset.
				reps = int(b&0x7F) + minLen
				if rpos+1 >= len(src) {
					break
				}
				dist = int(src[rpos])<<8 | int(src[rpos+1])
				rpos += 2
			}
			// dist is the offset from current write position, 1-based.
			from := len(out) - dist - 1
			for i := 0; i < reps && len(out) < outSize; i++ {
				idx := from + i
				if idx < 0 || idx >= len(out) {
					out = append(out, 0)
				} else {
					out = append(out, out[idx])
				}
			}
		} else {
			// Literal run.
			reps := int(b&0x7F) + 1
			end := rpos + reps
			if end > len(src) {
				end = len(src)
			}
			out = append(out, src[rpos:end]...)
			rpos = end
		}
	}

	return out, nil
}

// DecompressITL decompresses data using the I.T.L. (Sega) format:
// non-zero-byte literal selection + running XOR chain, operating on 32-byte blocks.
// Reference: https://github.com/lab313ru/itl_comp/blob/master/main.c
func DecompressITL(src []byte) ([]byte, error) {
	rpos := 0
	var out []byte

	for rpos < len(src) {
		var tmp [32]byte
		tpos := 0

		// For each of the 4 token bytes, decode 8 output bytes.
		for c1 := 0; c1 < 4 && rpos < len(src); c1++ {
			d2 := src[rpos]
			rpos++

			for c2 := 0; c2 < 8 && rpos < len(src); c2++ {
				bit := d2 & 0x80
				d2 <<= 1
				if bit != 0 {
					tmp[tpos] = src[rpos]
					rpos++
				} else {
					tmp[tpos] = 0
				}
				tpos++
			}
		}

		// Running XOR chain across the 8 dwords in tmp.
		tpos = 0
		var xorVal uint32
		for c1 := 0; c1 < 8; c1++ {
			tmp[tpos+0] ^= byte(xorVal >> 24)
			tmp[tpos+1] ^= byte(xorVal >> 16)
			tmp[tpos+2] ^= byte(xorVal >> 8)
			tmp[tpos+3] ^= byte(xorVal)
			xorVal = uint32(tmp[tpos+0])<<24 | uint32(tmp[tpos+1])<<16 |
				uint32(tmp[tpos+2])<<8 | uint32(tmp[tpos+3])
			tpos += 4
		}

		out = append(out, tmp[:]...)
	}

	return out, nil
}

func Decompress(compression string, src []byte) ([]byte, error) {
	switch compression {
	case "nemesis":
		return DecompressNemesis(src)
	case "kosinski":
		return DecompressKosinski(src)
	case "kosinskiplus":
		return DecompressKosinskiPlus(src)
	case "enigma":
		return DecompressEnigma(src)
	case "segard":
		return DecompressSegaRD(src)
	case "saxman":
		return DecompressSaxman(src)
	case "saxman_noheader":
		return DecompressSaxmanNoHeader(src)
	case "comper":
		return DecompressComper(src)
	case "rocket":
		return DecompressRocket(src)
	case "faxman":
		return DecompressFaxman(src)
	case "rage":
		return DecompressRage(src)
	case "chameleon":
		return DecompressChameleon(src)
	case "lznamco":
		return DecompressLZNamco(src)
	case "lzstrike":
		return DecompressLZStrike(src)
	case "lztechnosoft":
		return DecompressLZTechnosoft(src)
	case "lzkonami1":
		return DecompressLZKonami1(src)
	case "lzkonami2":
		return DecompressLZKonami2(src)
	case "lzkonami3":
		return DecompressLZKonami3(src)
	case "lzancient":
		return DecompressLZAncient(src)
	case "lztose":
		return DecompressLZTose(src)
	case "lznextech":
		return DecompressLZNextech(src)
	case "lzwolfteam":
		return DecompressLZWolfteam(src)
	case "lzsti":
		return DecompressLZSTI(src)
	case "rlesc":
		return DecompressRLESoftwareCreations(src)
	case "rnc":
		return DecompressRNC(src)
	case "rnc1":
		return DecompressRNC1(src)
	case "rnc2":
		return DecompressRNC2(src)
	case "lzcompile":
		return DecompressLZCompile(src)
	case "itl":
		return DecompressITL(src)
	case "lzfactor5":
		return DecompressLZFactor5(src)
	case "none", "":
		dst := make([]byte, len(src))
		copy(dst, src)
		return dst, nil
	default:
		return nil, fmt.Errorf("unknown compression %q", compression)
	}
}
