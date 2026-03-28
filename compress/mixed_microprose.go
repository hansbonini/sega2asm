package compress

import (
	"encoding/binary"
	"fmt"
	"sega2asm/types"
)

func init() {
	Register(Algorithm{Name: "mixedmicroprose", Family: FamilyMixed, Description: "MicroProse delta-coded scanline scheme", Decompress: DecompressMixedMicroprose})
}

// DecompressMixedMicroprose decompresses tile graphics using the MicroProse
// delta-coded scanline scheme found in Star Trek: The Next Generation -
// Echoes from the Past.
//
// Stream layout:
//
//	u32be: decompressed size in bytes
//	then:  nibble-aligned command bitstream
//
// Each command is a pair of nibbles (cmd, param) followed by optional extra
// data. Commands produce one 4-byte scanline (8 pixels at 4bpp) relative to
// the previous scanline, except RLE (0x0) and Raw (0x4) which produce
// multiple scanlines.
//
// Commands:
//
//	0X — RLE: repeat previous scanline X+1 times
//	1X — OneColor: fill scanline with color X
//	2X — MirrorBack: byte-reverse scanline X+1 positions back in output
//	3X YY — MirrorBackExt: byte-reverse scanline (X*256+YY+1) back
//	4X CC CC CC CC... — Raw: copy next X+1 scanlines (4 bytes each)
//	5X MM — SetByMask: set pixels where mask bit=1 to color X (MSB=leftmost)
//	6X — (unused/abandoned)
//	7X — ShiftLeft: shift scanline left one pixel, fill right with X
//	8X — ShiftRight: shift scanline right one pixel, fill left with X
//	9R LC — OneBorder: C pixels of R on right, rest L
//	AR ML CK — TwoBorder: K pixels of R on right, C pixels of M in middle, rest L
//	BX ... — Extension: set one or two byte pairs at specific positions
//	CX-FX — Next: skip, read next command
func DecompressMixedMicroprose(src []byte) ([]byte, error) {
	if len(src) < 4 {
		return nil, fmt.Errorf("mixedmicroprose: input too short")
	}

	dstSize := int(binary.BigEndian.Uint32(src[:4]))
	if dstSize == 0 {
		return nil, nil
	}

	br := types.NewMSBBitReader(src, 4)

	getNibble := func() byte { return byte(br.ReadBits(4)) }
	getByte := func() byte { return byte(br.ReadBits(8)) }

	// Output includes an initial [0,0,0,0] scanline (stripped at end).
	dst := []byte{0, 0, 0, 0}

	appendScan := func(scan []byte) {
		dst = append(dst, scan...)
	}

	prev := func() []byte { return dst[len(dst)-4:] }

	// Nibble helpers (8 nibbles = 4 bytes).
	toNibs := func(scan []byte) [8]byte {
		var n [8]byte
		for i := 0; i < 4; i++ {
			n[i*2] = scan[i] >> 4
			n[i*2+1] = scan[i] & 0x0F
		}
		return n
	}

	packNibs := func(n [8]byte) []byte {
		return []byte{
			(n[0] << 4) | (n[1] & 0x0F),
			(n[2] << 4) | (n[3] & 0x0F),
			(n[4] << 4) | (n[5] & 0x0F),
			(n[6] << 4) | (n[7] & 0x0F),
		}
	}

	for len(dst)-4 < dstSize {
		if br.EOF() {
			break
		}
		cmd := getNibble()
		param := getNibble()

		switch {
		case cmd == 0x0: // RLE: repeat previous scanline (param+1) times
			p := prev()
			for i := 0; i <= int(param); i++ {
				scan := make([]byte, 4)
				copy(scan, p)
				appendScan(scan)
			}

		case cmd == 0x1: // OneColor: fill with color param
			var n [8]byte
			for i := range n {
				n[i] = param
			}
			appendScan(packNibs(n))

		case cmd == 0x2: // MirrorBack: byte-reverse scanline (param+1) back
			off := int(param) + 1
			numScans := len(dst) / 4 // includes initial
			refIdx := numScans - 1 - off
			if refIdx < 0 {
				return nil, fmt.Errorf("mixedmicroprose: mirrorback out of bounds (off=%d, scans=%d)", off, numScans-1)
			}
			ref := dst[refIdx*4 : refIdx*4+4]
			appendScan([]byte{ref[3], ref[2], ref[1], ref[0]})

		case cmd == 0x3: // MirrorBackExt
			lo := getByte()
			off := int(param)*0x100 + int(lo) + 1
			numScans := len(dst) / 4
			refIdx := numScans - 1 - off
			if refIdx < 0 {
				return nil, fmt.Errorf("mixedmicroprose: mirrorback ext out of bounds")
			}
			ref := dst[refIdx*4 : refIdx*4+4]
			appendScan([]byte{ref[3], ref[2], ref[1], ref[0]})

		case cmd == 0x4: // Raw: copy (param+1) scanlines
			for i := 0; i <= int(param); i++ {
				scan := make([]byte, 4)
				for j := 0; j < 4; j++ {
					scan[j] = getByte()
				}
				appendScan(scan)
			}

		case cmd == 0x5: // SetByMask
			mask := getByte()
			n := toNibs(prev())
			for bit := 7; bit >= 0; bit-- {
				if mask&(1<<uint(bit)) != 0 {
					n[7-bit] = param
				}
			}
			appendScan(packNibs(n))

		case cmd == 0x6: // Abandoned command
			return nil, fmt.Errorf("mixedmicroprose: command 0x6 not implemented")

		case cmd == 0x7: // ShiftLeft: shift left, fill right with param
			n := toNibs(prev())
			for i := 0; i < 7; i++ {
				n[i] = n[i+1]
			}
			n[7] = param
			appendScan(packNibs(n))

		case cmd == 0x8: // ShiftRight: shift right, fill left with param
			n := toNibs(prev())
			for i := 7; i > 0; i-- {
				n[i] = n[i-1]
			}
			n[0] = param
			appendScan(packNibs(n))

		case cmd == 0x9: // OneBorder: R=param, then read L, C
			lCol := getNibble()
			rCount := getNibble()
			var n [8]byte
			for i := 0; i < 8; i++ {
				n[i] = lCol
			}
			for i := 0; i < int(rCount) && (8-1-i) >= 0; i++ {
				n[8-1-i] = param
			}
			appendScan(packNibs(n))

		case cmd == 0xA: // TwoBorder: R=param, then read M, L, rCount, mCount
			mCol := getNibble()
			lCol := getNibble()
			rCount := getNibble()
			mCount := getNibble()
			var n [8]byte
			pos := 7
			for i := 0; i < int(rCount) && pos >= 0; i++ {
				n[pos] = param
				pos--
			}
			for i := 0; i < int(mCount) && pos >= 0; i++ {
				n[pos] = mCol
				pos--
			}
			for ; pos >= 0; pos-- {
				n[pos] = lCol
			}
			appendScan(packNibs(n))

		case cmd == 0xB: // Extension: set byte pairs
			p := getByte()
			if param < 4 {
				scan := make([]byte, 4)
				copy(scan, prev())
				scan[param] = p
				appendScan(scan)
			} else if param >= 0xA {
				scan := make([]byte, 4)
				copy(scan, prev())
				appendScan(scan)
			} else {
				p2 := getByte()
				scan := make([]byte, 4)
				copy(scan, prev())
				var pos1, pos2 byte
				switch param {
				case 4:
					pos1, pos2 = 0, 1
				case 5:
					pos1, pos2 = 0, 2
				case 6:
					pos1, pos2 = 0, 3
				case 7:
					pos1, pos2 = 1, 2
				case 8:
					pos1, pos2 = 1, 3
				case 9:
					pos1, pos2 = 2, 3
				}
				scan[pos1] = p
				scan[pos2] = p2
				appendScan(scan)
			}

		default: // 0xC-0xF: skip, read next command
			continue
		}
	}

	// Strip initial scanline and trim to exact size.
	result := dst[4:]
	if len(result) > dstSize {
		result = result[:dstSize]
	}
	return result, nil
}
