package types

import "fmt"

// LabelMap maps ROM addresses to human-readable label names.
// It is a type alias for map[uint32]string so it is fully interchangeable
// with the underlying map type across all packages.
type LabelMap = map[Addr]string

// LookupOrHex returns the label name for addr from labels,
// or a generated "loc_XXXXXX" fallback when addr has no symbol.
func LookupOrHex(labels LabelMap, addr Addr) string {
	if name, ok := labels[addr]; ok {
		return name
	}
	return fmt.Sprintf("loc_%06X", addr)
}
