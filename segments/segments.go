// Package segments implements per-type ROM segment processors.
// Each segment type registers itself via init(), following the same
// self-registration pattern used by the compress package.
package segments

import "sega2asm/types"

// Type aliases — all segment processors use types.* directly.
type (
	ProcessFunc = types.ProcessFunc
	Context     = types.Context
	Result      = types.Result
	Include     = types.Include
)

// Register and Lookup delegate to the types registry.
func Register(name string, fn ProcessFunc) { types.Register(name, fn) }
func Lookup(name string) ProcessFunc       { return types.Lookup(name) }
