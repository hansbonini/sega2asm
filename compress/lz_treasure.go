package compress

import "fmt"

// DecompressLZTreasure decompresses data using the LZ Treasure format.
//
// Header: 2 bytes (big-endian) = total compressed size.
// Control byte:
//   - bit7=1: backreference; bits 4-2 = count-1, bottom 10 bits of (ctrl<<8|next) = distance-1
//   - bit7=0, bit5=1, bit6=1: RLE alternating — read z, then (cnt+1) pairs of (z, nextByte)
//   - bit7=0, bit5=1, bit6=0: RLE single byte — repeat next byte (cnt+1) times
//   - bit7=0, bit5=0, bit6=1: RLE byte pairs — repeat two bytes (cnt+1) times
//   - bit7=0, bit5=0, bit6=0: literal run — copy (cnt+1) bytes verbatim
func DecompressLZTreasure(src []byte) ([]byte, error) {
	if len(src) < 3 {
		return nil, fmt.Errorf("lztreasure: input too small (%d bytes)", len(src))
	}

	size := int(src[0])*0x100 + int(src[1])
	if size < 2 {
		return nil, fmt.Errorf("lztreasure: invalid size header: %d", size)
	}
	if size > len(src) {
		return nil, fmt.Errorf("lztreasure: size header (%d) exceeds input (%d bytes)", size, len(src))
	}

	var res []byte
	idx := 2

	for idx <= size && idx < len(src) {
		b := src[idx]

		if b >= 0x80 { // Backreference
			cnt := int((b>>2)&0x1F) + 1
			tmp := int(b) << 8
			idx++
			if idx >= len(src) {
				return nil, fmt.Errorf("lztreasure: unexpected end at offset %d (backreference)", idx)
			}
			tmp += int(src[idx])
			dist := (tmp & 0x3FF) + 1
			idxWindow := len(res) - dist
			if idxWindow < 0 {
				return nil, fmt.Errorf("lztreasure: invalid backreference at offset %d", idx)
			}
			for i := 0; i < cnt+1; i++ {
				if idxWindow >= len(res) {
					return nil, fmt.Errorf("lztreasure: backreference out of bounds at offset %d", idx)
				}
				res = append(res, res[idxWindow])
				idxWindow++
			}
		} else if b&0x20 != 0 { // bit 5 set
			if b&0x40 != 0 { // RLE alternating: z, s0, z, s1, ...
				cnt := int(b&0x1F) + 1
				idx++
				if idx >= len(src) {
					return nil, fmt.Errorf("lztreasure: unexpected end at offset %d (RLE varying)", idx)
				}
				z := src[idx]
				for i := 0; i < cnt+1; i++ {
					res = append(res, z)
					idx++
					if idx >= len(src) {
						return nil, fmt.Errorf("lztreasure: unexpected end at offset %d", idx)
					}
					res = append(res, src[idx])
				}
			} else { // RLE single byte
				cnt := int(b&0x1F) + 1
				idx++
				if idx >= len(src) {
					return nil, fmt.Errorf("lztreasure: unexpected end at offset %d (RLE single)", idx)
				}
				s := src[idx]
				for i := 0; i < cnt+1; i++ {
					res = append(res, s)
				}
			}
		} else { // bit 5 clear
			if b&0x40 != 0 { // RLE byte pairs
				cnt := int(b&0x1F) + 1
				if idx+2 >= len(src) {
					return nil, fmt.Errorf("lztreasure: unexpected end at offset %d (RLE pairs)", idx)
				}
				s1 := src[idx+1]
				s2 := src[idx+2]
				idx += 2
				for i := 0; i < cnt+1; i++ {
					res = append(res, s1, s2)
				}
			} else { // Literal run
				cnt := int(b & 0x1F)
				for i := 0; i < cnt+1; i++ {
					idx++
					if idx >= len(src) {
						return nil, fmt.Errorf("lztreasure: unexpected end at offset %d (literal)", idx)
					}
					res = append(res, src[idx])
				}
			}
		}

		idx++
	}

	if len(res) == 0 {
		return nil, fmt.Errorf("lztreasure: decompression produced no output")
	}

	return res, nil
}
