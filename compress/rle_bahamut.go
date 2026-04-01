package compress

import (
	"sega2asm/types"
	"fmt"
)

func init() {
	types.RegisterAlgorithm(types.Algorithm{Name: "rlebahamut", Family: types.FamilyRLE, Description: "Bahamut Senki byteplane-interleaved RLE", Decompress: DecompressRLEBahamut})
	types.RegisterSignature(types.CompressSig{
		Name: "rlebahamut", WordAligned: true,
		Sig: []byte{
			0x14, 0x00, 0xC4, 0x7C, 0x00, 0x0F, 0x53, 0x42, 0x6A, 0x04, 0x74, 0x00, 0x14, 0x18, 0xC0, 0x7C, 0x00, 0x70, 0xE4, 0x48,
		},
	})
}

// DecompressRLEBahamut decompresses font/tile data using the Bahamut Senki
// byteplane-interleaved command-nibble scheme.
//
// Format:
//
//	+0x00  u8   numEntries (number of 16-bit output words)
//	+0x01  i8   initialCmpByte
//	  - If bit 7 set: even plane is constant (next byte << 8), cmpByte negated for odd plane
//	  - Otherwise: even plane compressed data follows, then odd plane cmpByte + data
//
// Each plane is decompressed with decmpPlane: a command byte encodes
// cmd (bits 6-4) and length (bits 3-0, or extended via next byte if 0).
//
// Commands (bits 6-4):
//
//	0 = terminate
//	1 = RLE fill (repeat one byte)
//	2 = literal copy
//	3 = incrementing fill (byte + 1 each iteration)
//	4 = repeated sub-run (copy N-byte run M times)
//	5 = repeated incremental run (N-byte incrementing run, M times)
//	6 = uncompressed passthrough (copy remaining, terminate)
//
// Output is numEntries × 2 bytes (big-endian 16-bit words) with even and odd
// byte planes interleaved.
func DecompressRLEBahamut(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("rlebahamut: input too short")
	}

	pos := 0

	rd8 := func() (byte, error) {
		if pos >= len(src) {
			return 0, fmt.Errorf("rlebahamut: unexpected end of input at offset %d", pos)
		}
		b := src[pos]
		pos++
		return b, nil
	}

	numEntries, _ := rd8()
	n := int(numEntries)
	if n == 0 {
		return []byte{}, nil
	}

	out := make([]byte, n*2)

	// decmpPlane decompresses one byte plane into out at stride 2.
	// wp is the starting write index (0 for even plane, 1 for odd plane).
	// Returns error if any.
	decmpPlane := func(wp int, cmpByte byte) error {
		for {
			length := int(cmpByte & 0x0F)
			length-- // -1; if low nibble was 0, this becomes -1
			if length < 0 {
				b, err := rd8()
				if err != nil {
					return err
				}
				length = int(b)
			}
			length++ // increment for use as loop counter

			cmd := (cmpByte & 0x70) >> 4

			switch cmd {
			case 0:
				// terminate
				return nil

			case 1:
				// RLE: repeat next byte
				b, err := rd8()
				if err != nil {
					return err
				}
				for i := 0; i < length; i++ {
					if wp < len(out) {
						out[wp] = b
					}
					wp += 2
				}

			case 2:
				// literal copy
				for i := 0; i < length; i++ {
					b, err := rd8()
					if err != nil {
						return err
					}
					if wp < len(out) {
						out[wp] = b
					}
					wp += 2
				}

			case 3:
				// incrementing fill
				b, err := rd8()
				if err != nil {
					return err
				}
				val := int(b)
				for i := 0; i < length; i++ {
					if wp < len(out) {
						out[wp] = byte(val & 0xFF)
					}
					wp += 2
					val = (val + 1) & 0xFF
				}

			case 4:
				// repeated sub-run: copy runLen-byte pattern length times
				rl, err := rd8()
				if err != nil {
					return err
				}
				runLen := int(rl) + 1
				runStart := pos
				// read the run bytes once to advance pos
				run := make([]byte, runLen)
				for j := 0; j < runLen; j++ {
					b, err := rd8()
					if err != nil {
						return err
					}
					run[j] = b
				}
				_ = runStart
				for i := 0; i < length; i++ {
					for j := 0; j < runLen; j++ {
						if wp < len(out) {
							out[wp] = run[j]
						}
						wp += 2
					}
				}

			case 5:
				// repeated incremental run
				rl, err := rd8()
				if err != nil {
					return err
				}
				runLen := int(rl) + 1
				initB, err := rd8()
				if err != nil {
					return err
				}
				initialVal := int(initB)
				for i := 0; i < length; i++ {
					val := initialVal
					for j := 0; j < runLen; j++ {
						if wp < len(out) {
							out[wp] = byte(val & 0xFF)
						}
						wp += 2
						val = (val + 1) & 0xFFFF
					}
				}

			case 6:
				// uncompressed: seek back 1 byte (re-read cmpByte as data),
				// copy numEntries+1 bytes
				pos--
				for i := 0; i < n+1; i++ {
					b, err := rd8()
					if err != nil {
						return err
					}
					if wp < len(out) {
						out[wp] = b
					}
					wp += 2
				}
				return nil

			default:
				return fmt.Errorf("rlebahamut: illegal command %d", cmd)
			}

			// read next command byte
			if pos >= len(src) {
				return nil
			}
			cmpByte = src[pos]
			pos++
			if cmpByte == 0x00 {
				return nil
			}
		}
	}

	// Read initial compression byte (signed).
	initCmp, err := rd8()
	if err != nil {
		return nil, err
	}

	if initCmp&0x80 != 0 {
		// Even plane doesn't exist: next byte is the constant high byte.
		hi, err := rd8()
		if err != nil {
			return nil, err
		}
		for i := 0; i < n; i++ {
			out[i*2] = hi
		}
		// Negate the signed cmpByte for odd plane.
		initCmp = byte(-int8(initCmp))
	} else {
		// Decompress even plane (high bytes at indices 0, 2, 4...).
		if err := decmpPlane(0, initCmp); err != nil {
			return nil, err
		}
		// Read next cmpByte for odd plane.
		initCmp, err = rd8()
		if err != nil {
			return nil, err
		}
	}

	// Decompress odd plane (low bytes at indices 1, 3, 5...).
	if err := decmpPlane(1, initCmp); err != nil {
		return nil, err
	}

	return out, nil
}
