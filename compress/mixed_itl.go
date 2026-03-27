package compress

// DecompressMixedITL decompresses data using the I.T.L (Sega) format:
// non-zero-byte literal selection + running XOR chain, operating on 32-byte blocks.
// Reference: https://github.com/lab313ru/itl_comp/blob/master/main.c
func DecompressMixedITL(src []byte) ([]byte, error) {
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
