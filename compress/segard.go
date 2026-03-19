package compress

import "fmt"

// DecompressSegaRD decompresses data using the Sega RD (Resource Data) format.
//
// Stream structure: sequence of blocks terminated by a count byte of 0xFF.
// Each block:
//
//	count byte                        — number of color/mask pairs in this block
//	count × (color byte + BE32 mask)  — each mask bit selects positions in the 32-byte window for that color
//	remaining literal bytes           — fill any bit positions not covered by the combined mask
//
// Output is always a multiple of 32 bytes; each block emits one 32-byte tile row.
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
