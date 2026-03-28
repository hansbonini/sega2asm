package compress

import "fmt"

func init() {
	Register(Algorithm{Name: "rlesc", Family: FamilyRLE, Description: "Software Creations RLE", Decompress: DecompressRLESC})
}

// DecompressRLESC decompresses data using the Software Creations
// RLE format (Maximum Carnage, Venom, The Tick, Cutthroat Island).
//
// Header:
//
//	[0] escape byte — the trigger value for run-length encoding
//
// Encoding: when the escape byte appears, the next two bytes form a run:
//
//	escape, value, count → emit count bytes of value
//	any other byte       → emit verbatim
func DecompressRLESC(src []byte) ([]byte, error) {
	if len(src) < 1 {
		return nil, fmt.Errorf("rlesc: too short")
	}
	escape := src[0]
	pos := 1
	remaining := len(src) - 1
	var out []byte
	for remaining > 0 && pos < len(src) {
		b := src[pos]
		pos++
		if b == escape {
			if pos+1 >= len(src) {
				break
			}
			val := src[pos]
			pos++
			length := int(src[pos])
			pos++
			for i := 0; i < length; i++ {
				out = append(out, val)
			}
			remaining -= 3
		} else {
			out = append(out, b)
			remaining--
		}
	}
	return out, nil
}
