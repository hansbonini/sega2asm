package compress

func init() {
	// Pass-through (no compression); has no dedicated file.
	Register(Algorithm{Name: "none", Family: FamilyNone, Description: "No compression; data copied verbatim", Decompress: func(src []byte) ([]byte, error) {
		dst := make([]byte, len(src))
		copy(dst, src)
		return dst, nil
	}})
}
