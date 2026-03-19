package compress

import (
	"encoding/binary"
	"fmt"
)

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
