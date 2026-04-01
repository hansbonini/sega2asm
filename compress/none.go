package compress

import "sega2asm/types"

func init() {
	// Pass-through (no compression); has no dedicated file.
	types.RegisterAlgorithm(types.Algorithm{Name: "none", Family: types.FamilyNone, Description: "No compression; data copied verbatim", Decompress: func(src []byte) ([]byte, error) {
		dst := make([]byte, len(src))
		copy(dst, src)
		return dst, nil
	}})
}
