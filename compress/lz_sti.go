package compress

import (
	"encoding/binary"
	"sega2asm/helpers"
	"fmt"
)

// ── LZSTI — Comix Zone ────────────────────────────────────────────────────────
// Window 0x400 cursor 0. Header: BE16 uncompressed size. Bit-packed stream (MSB first).
// bit=1→8-bit literal; bit=0→10-bit offset, 4-bit (len-2).

func DecompressLZSTI(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("lzsti: too short")
	}
	uncompSize := int(binary.BigEndian.Uint16(src[0:2]))
	win := helpers.NewWin(0x400, 0, 0)
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
			win.Emit(b, &out)
			decoded++
		} else {
			offset := readBits(10)
			length := readBits(4) + 2
			win.CopyFrom(offset, length, &out)
			decoded += length
		}
	}
	if len(out) > uncompSize {
		out = out[:uncompSize]
	}
	return out, nil
}
