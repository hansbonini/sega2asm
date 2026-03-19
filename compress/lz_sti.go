package compress

import (
	"encoding/binary"
	"sega2asm/helpers"
	"fmt"
)

// DecompressLZSTI decompresses data using the LZSTI format (Comix Zone).
//
// Window: 0x400 bytes, cursor at 0x00, fill 0x00.
//
// Header:
//
//	[0..1] big-endian word — uncompressed size
//
// Control stream: bit-packed MSB first (no byte-boundary alignment).
//
//	bit=1 → literal: read 8 bits verbatim
//	bit=0 → back-reference:
//	          offset = next 10 bits   (absolute ring buffer index)
//	          length = next 4 bits + 2
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
