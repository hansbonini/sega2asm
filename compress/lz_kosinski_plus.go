package compress

import "sega2asm/types"

func init() {
	types.RegisterAlgorithm(types.Algorithm{Name: "lzkosinskiplus", Family: types.FamilyLZ, Description: "Extended Kosinski with larger offset/count fields", Decompress: DecompressLZKosinskiPlus})
}

// DecompressLZKosinskiPlus decompresses data using the KosinskiPlus (clownlzss) format,
// a variant of Kosinski with 8-bit descriptors and updated match encodings.
//
// No size header; stream is self-terminating.
//
// Control stream: 8-bit descriptor byte, MSB first.
//
//	bit=1              → literal byte
//	bit=0, next bit=1  → full back-reference: 2 bytes
//	                        offset = 0x2000 - (((b0 & 0xF8) << 5) | b1)  (13-bit)
//	                        length = b0 & 7; 0 → read next byte + 9; 1 → end of stream
//	bit=0, next bit=0  → short back-reference: next 2 bits = length-2 (1..3), next byte = distance
func DecompressLZKosinskiPlus(src []byte) ([]byte, error) {
	dr := types.NewMSBDescReader(src, 0)
	var out []byte
	for {
		if dr.PopBit() == 1 {
			out = append(out, dr.ReadByte())
		} else if dr.PopBit() == 1 {
			hi := int(dr.ReadByte())
			lo := int(dr.ReadByte())
			offset := 0x2000 - (((hi & 0xF8) << 5) | lo)
			count := hi & 7
			if count == 0 {
				count = int(dr.ReadByte()) + 9
				if count == 9 {
					break
				}
			} else {
				count = 10 - count
			}
			types.CopyDist(&out, offset, count)
		} else {
			offset := 0x100 - int(dr.ReadByte())
			count := 2
			if dr.PopBit() == 1 {
				count += 2
			}
			if dr.PopBit() == 1 {
				count++
			}
			types.CopyDist(&out, offset, count)
		}
	}
	return out, nil
}
