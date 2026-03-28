package compress

import "fmt"

func init() {
	Register(Algorithm{Name: "lzfactor5", Family: FamilyLZ, Description: "Factor 5 LZ; auto-detected v1/v2", Decompress: DecompressLZFactor5})
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
