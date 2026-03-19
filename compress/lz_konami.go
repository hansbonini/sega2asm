package compress

import (
	"encoding/binary"
	"sega2asm/helpers"
	"fmt"
)

// DecompressLZKonami1 decompresses data using the LZKonami variant 1 format
// (Animaniacs, Contra Hard Corps, Lethal Enforcers II, Sparkster).
//
// Window: 0x400 bytes, cursor at 0x3C0, fill 0x20.
//
// Header:
//
//	[0..1] big-endian word — uncompressed size
//
// Control stream: 8-bit descriptor byte, LSB first. For each descriptor bit,
// one byte is always consumed from the stream:
//
//	bit=0              → literal byte
//	bit=1, byte=0x1F   → end of stream
//	bit=1, byte > 0x80 → long back-reference: high bits of byte + next byte encode offset; count from byte + 1
//	bit=1, byte = 0x80 → short back-reference: next byte encodes offset and count
func DecompressLZKonami1(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("lzkonami1: too short")
	}
	uncompSize := int(binary.BigEndian.Uint16(src[0:2]))
	pos := 2
	win := helpers.NewWin(0x400, 0x3C0, 0x20)
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
					offset := ((int(r)<<3)&0xFF00 | low) & win.Mask
					win.CopyFrom(offset, length, &out)
					decoded += length
				} else if r == 0x80 {
					length := int(r>>4) - 6
					offset := (win.Cursor - int(r&0xF) + win.Size) & win.Mask
					win.CopyFrom(offset, length, &out)
					decoded += length
				}
				// r < 0x80 (not 0x1F): undefined per reference, ignore
			} else {
				win.Emit(r, &out)
				decoded++
			}
		}
	}
	return out, nil
}

// DecompressLZKonami2 decompresses data using the LZKonami variant 2 format
// (Castlevania: Bloodlines, Rocket Knight Adventures, TMNT: The Hyperstone Heist, Sunset Riders).
//
// Window: 0x400 bytes, cursor at 0x3C0, fill 0x20.
//
// Header:
//
//	[0..1] big-endian word — compressed size
//
// Control stream: 8-bit descriptor byte, LSB first.
//
//	bit=1 → literal byte
//	bit=0 → back-reference: big-endian word
//	          length = ((word & 0xFC00) >> 10) + 1
//	          offset = word & 0x3FF
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
	win := helpers.NewWin(0x400, 0x3C0, 0x20)
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
				win.Emit(b, &out)
			} else {
				hi := int(read())
				lo := int(read())
				word := (hi << 8) | lo
				length := ((word & 0xFC00) >> 10) + 1
				offset := word & 0x3FF
				win.CopyFrom(offset, length, &out)
			}
		}
	}
	return out, nil
}

// DecompressLZKonami3 decompresses data using the LZKonami variant 3 format
// (Castlevania: Bloodlines, Lethal Enforcers, TMNT: Tournament Fighters).
//
// Window: 0x400 bytes, cursor at 0x3DF, fill 0x00.
//
// Header:
//
//	[0..1] big-endian word — uncompressed size
//
// Control stream: 8-bit descriptor byte, LSB first. For each descriptor bit,
// one byte is always consumed from the stream:
//
//	bit=0              → literal byte
//	bit=1, byte=0x1F   → end of stream
//	bit=1, byte < 0x80 → long back-reference: high bits of byte + next byte encode offset; count from byte + 1
//	bit=1, 0x80–0xBF   → short back-reference: low bits encode offset and count
//	bit=1, 0xC0–0xFF   → repeat run: byte encodes count; values read from stream
func DecompressLZKonami3(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("lzkonami3: too short")
	}
	uncompSize := int(binary.BigEndian.Uint16(src[0:2]))
	pos := 2
	win := helpers.NewWin(0x400, 0x3DF, 0)
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
					offset := (((int(r) & 0x60) << 3) | low) & win.Mask
					win.CopyFrom(offset, length, &out)
					decoded += length
				} else if r <= 0xBF {
					length := ((int(r) >> 4) & 0x3) + 2
					offset := (win.Cursor - int(r&0xF) + win.Size) & win.Mask
					win.CopyFrom(offset, length, &out)
					decoded += length
				} else {
					length := int(r&0x3F) + 8
					for i := 0; i < length && decoded < uncompSize; i++ {
						b := read()
						win.Emit(b, &out)
						decoded++
					}
				}
			} else {
				win.Emit(r, &out)
				decoded++
			}
		}
	}
	return out, nil
}
