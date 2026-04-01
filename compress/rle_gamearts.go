package compress

import (
	"sega2asm/types"
	"encoding/binary"
	"fmt"
)

func init() {
	types.RegisterAlgorithm(types.Algorithm{Name: "rlegamearts", Family: types.FamilyRLE, Description: "Game Arts 4-plane RLE", Decompress: DecompressRLEGameArts})
}

// DecompressRLEGameArts decompresses graphics data from Game Arts Mega Drive
// games (e.g. Alisia Dragoon). Reverse-engineered from sub_FA88 / sub_FB72.
//
// Header (16 bytes):
//
//	[0x00:0x02]  count   big-endian word; count×8 = bytes per plane
//	[0x02:0x0A]  8-byte lookup table (opcodes 0x00–0x1F)
//	[0x0A:0x0C]  plane 1 stream offset (relative to block start)
//	[0x0C:0x0E]  plane 2 stream offset
//	[0x0E:0x10]  plane 3 stream offset
//	[0x10:]      plane 0 stream
//
// Opcodes (per-plane compressed stream):
//
//	0x00–0x1F  table[op>>2&7] written twice + (op&3) literals
//	0x20–0x2F  fill 0x00 (2–5 bytes) + (op&3) literals
//	0x30–0x3F  fill 0xFF (2–5 bytes) + (op&3) literals
//	0x40–0x5F  fill 0x00 (6–37 bytes)
//	0x60–0x7F  fill 0xFF (6–37 bytes)
//	0x80–0xBF  repeat next byte (2–17 times) + (op&3) literals
//	0xC0–0xFF  copy (op&0x3F)+1 literals
//
// Output: Mega Drive 4bpp tile data (plane order 3,2,0,1 per sub_FB72).
func DecompressRLEGameArts(src []byte) ([]byte, error) {
	if len(src) < 0x10 {
		return nil, fmt.Errorf("rlegamearts: header too short (%d bytes)", len(src))
	}

	count := int(binary.BigEndian.Uint16(src[0:2])) * 8

	ptrs := [4]int{
		0x10,
		int(binary.BigEndian.Uint16(src[0x0A:])),
		int(binary.BigEndian.Uint16(src[0x0C:])),
		int(binary.BigEndian.Uint16(src[0x0E:])),
	}

	var bufs [4][0x100]byte
	out := make([]byte, 0, count*4)

	remaining := count
	for remaining > 0 {
		chunk := min(remaining, 0x100)
		remaining -= chunk

		for p := 0; p < 4; p++ {
			var err error
			ptrs[p], err = rleGameArtsDecompPlane(src, ptrs[p], bufs[p][:], chunk)
			if err != nil {
				return nil, fmt.Errorf("rlegamearts: plane %d: %w", p, err)
			}
		}

		rleGameArtsInterleave(bufs, chunk, &out)
	}

	return out, nil
}

// rleGameArtsDecompPlane decompresses exactly n bytes of one plane into buf.
func rleGameArtsDecompPlane(data []byte, src int, buf []byte, n int) (int, error) {
	dst := 0

	wb := func(v byte) {
		buf[dst] = v
		dst++
	}
	rb := func() (byte, error) {
		if src >= len(data) {
			return 0, fmt.Errorf("unexpected end of stream at src=%d", src)
		}
		b := data[src]
		src++
		return b, nil
	}

	for dst < n {
		op, err := rb()
		if err != nil {
			return src, err
		}
		hi4 := op & 0xF0

		// 0x20–0x3F: short fill (0x00 or 0xFF) + literals
		if hi4 == 0x20 || hi4 == 0x30 {
			fillVal := byte(0x00)
			if hi4 == 0x30 {
				fillVal = 0xFF
			}
			fillN := int((op&0x0C)>>2) + 2 // 2–5
			litN := int(op & 0x03)
			for i := 0; i < fillN; i++ {
				wb(fillVal)
			}
			for i := 0; i < litN; i++ {
				b, err := rb()
				if err != nil {
					return src, err
				}
				wb(b)
			}
			continue
		}

		hi3 := op & 0xE0

		// 0x40–0x7F: medium fill (0x00 or 0xFF)
		if hi3 == 0x40 || hi3 == 0x60 {
			fillVal := byte(0x00)
			if hi3 == 0x60 {
				fillVal = 0xFF
			}
			fillN := int(op&0x1F) + 6 // 6–37
			for i := 0; i < fillN; i++ {
				wb(fillVal)
			}
			continue
		}

		hi2 := op & 0xC0

		// 0xC0–0xFF: literal copy
		if hi2 == 0xC0 {
			litN := int(op&0x3F) + 1 // 1–64
			for i := 0; i < litN; i++ {
				b, err := rb()
				if err != nil {
					return src, err
				}
				wb(b)
			}
			continue
		}

		// 0x80–0xBF: repeat byte + literals
		if hi2 == 0x80 {
			fillVal, err := rb()
			if err != nil {
				return src, err
			}
			fillN := int((op&0x3C)>>2) + 2 // 2–17
			litN := int(op & 0x03)
			for i := 0; i < fillN; i++ {
				wb(fillVal)
			}
			for i := 0; i < litN; i++ {
				b, err := rb()
				if err != nil {
					return src, err
				}
				wb(b)
			}
			continue
		}

		// 0x00–0x1F: table lookup + literals
		tblIdx := (op & 0x1C) >> 2 // 0–7
		val := data[2+tblIdx]
		wb(val)
		wb(val)
		litN := int(op & 0x03)
		for i := 0; i < litN; i++ {
			b, err := rb()
			if err != nil {
				return src, err
			}
			wb(b)
		}
	}

	return src, nil
}

// rleGameArtsInterleave converts 4 plane buffers to Mega Drive 4bpp tile format.
// Bit interleaving order: plane3, plane2, plane0, plane1 (sub_FB72).
// Produces 4 output bytes per input byte (8 pixels, 2 per output byte).
func rleGameArtsInterleave(bufs [4][0x100]byte, count int, out *[]byte) {
	planeOrder := [4]int{3, 2, 0, 1}
	for i := 0; i < count; i++ {
		var planes [4]byte
		for j, p := range planeOrder {
			planes[j] = bufs[p][i]
		}
		for byteIdx := 0; byteIdx < 4; byteIdx++ {
			result := byte(0)
			for bitPair := 0; bitPair < 2; bitPair++ {
				bitPos := uint(7 - (byteIdx*2 + bitPair))
				for _, pb := range planes {
					result = (result << 1) | ((pb >> bitPos) & 1)
				}
			}
			*out = append(*out, result)
		}
	}
}
