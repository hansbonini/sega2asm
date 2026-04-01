package types

import (
	"bytes"
	"fmt"
	"sort"
)

// Family classifies a compression algorithm by its fundamental technique.
type Family int

const (
	FamilyLZ        Family = iota // Lempel-Ziv (sliding window, back-references)
	FamilyLZSS                    // LZSS variant (flag-driven literal/match)
	FamilyLZ77                    // LZ77 variant (control byte + offset/length)
	FamilyLZH                     // LZ + Huffman entropy coding
	FamilyHuffman                 // Pure Huffman / entropy coding
	FamilyRLE                     // Run-length encoding
	FamilyMixed                   // Combination of techniques (RLE+LZ, delta, etc.)
	FamilyExpGolomb               // Exponential-Golomb / spatial coding
	FamilyNone                    // No compression (pass-through)
)

// String returns the human-readable name of the compression family.
func (f Family) String() string {
	switch f {
	case FamilyLZ:
		return "LZ"
	case FamilyLZSS:
		return "LZSS"
	case FamilyLZ77:
		return "LZ77"
	case FamilyLZH:
		return "LZH"
	case FamilyHuffman:
		return "Huffman"
	case FamilyRLE:
		return "RLE"
	case FamilyMixed:
		return "Mixed"
	case FamilyExpGolomb:
		return "Exp-Golomb"
	case FamilyNone:
		return "None"
	default:
		return "Unknown"
	}
}

// Decompressor is the function signature shared by all decompression algorithms.
type Decompressor func(src []byte) ([]byte, error)

// Algorithm describes a registered compression format.
type Algorithm struct {
	Name        string       // Identifier used in YAML configs (e.g. "huffnemesis")
	Family      Family       // Compression family classification
	Description string       // Short description of the algorithm
	Decompress  Decompressor // Decompression function
}

// compressRegistry maps algorithm names to their Algorithm descriptors.
var compressRegistry = map[string]*Algorithm{}

// compressAlgorithms preserves insertion order for iteration.
var compressAlgorithms []*Algorithm

// RegisterAlgorithm adds an algorithm to the global registry.
func RegisterAlgorithm(a Algorithm) {
	alg := &Algorithm{
		Name:        a.Name,
		Family:      a.Family,
		Description: a.Description,
		Decompress:  a.Decompress,
	}
	compressRegistry[a.Name] = alg
	compressAlgorithms = append(compressAlgorithms, alg)
}

// LookupAlgorithm returns the Algorithm for the given name, or nil if not found.
func LookupAlgorithm(name string) *Algorithm {
	return compressRegistry[name]
}

// Algorithms returns all registered algorithms in registration order.
func Algorithms() []*Algorithm {
	return compressAlgorithms
}

// Decompress decompresses src using the named algorithm.
// Algorithm names are registered via init() in each compress/ file.
func Decompress(compression string, src []byte) ([]byte, error) {
	if compression == "" {
		compression = "none"
	}
	alg := LookupAlgorithm(compression)
	if alg == nil {
		return nil, fmt.Errorf("unknown compression %q", compression)
	}
	return alg.Decompress(src)
}

// Match reports a compression routine found in the ROM.
type Match struct {
	// Name is the compression identifier accepted by Decompress.
	Name string
	// Offset is the byte offset in the ROM where the routine signature begins.
	Offset int
}

// CompressSig describes a byte-pattern used to detect a compression algorithm in ROM.
type CompressSig struct {
	Name        string
	Sig         []byte
	WordAligned bool
	Validator   func(rom []byte, offset int) bool
}

// compressSigs holds all registered detection signatures.
var compressSigs []CompressSig

// RegisterSignature registers a detection signature for a compression algorithm.
// Call this from an algorithm's init() alongside RegisterAlgorithm.
func RegisterSignature(s CompressSig) {
	compressSigs = append(compressSigs, s)
}

// Detect scans rom for known compression routine signatures and returns all
// matches sorted by ROM offset.
func Detect(rom []byte) []Match {
	type candidate struct {
		Match
		sigLen int
	}
	var candidates []candidate
	for _, entry := range compressSigs {
		off := 0
		for {
			idx := bytes.Index(rom[off:], entry.Sig)
			if idx < 0 {
				break
			}
			absOff := off + idx
			if entry.WordAligned && absOff%2 != 0 {
				off = absOff + 1
				continue
			}
			if entry.Validator != nil && !entry.Validator(rom, absOff) {
				off = absOff + 1
				continue
			}
			candidates = append(candidates, candidate{
				Match:  Match{Name: entry.Name, Offset: absOff},
				sigLen: len(entry.Sig),
			})
			off = absOff + 1
		}
	}

	sort.Slice(candidates, func(i, j int) bool {
		if candidates[i].Offset != candidates[j].Offset {
			return candidates[i].Offset < candidates[j].Offset
		}
		return candidates[i].sigLen > candidates[j].sigLen
	})

	var accepted []candidate
	for _, c := range candidates {
		contained := false
		cEnd := c.Offset + c.sigLen
		for _, a := range accepted {
			aEnd := a.Offset + a.sigLen
			if c.Offset >= a.Offset && cEnd <= aEnd {
				contained = true
				break
			}
		}
		if !contained {
			accepted = append(accepted, c)
		}
	}

	matches := make([]Match, len(accepted))
	for i, a := range accepted {
		matches[i] = a.Match
	}
	sort.Slice(matches, func(i, j int) bool {
		return matches[i].Offset < matches[j].Offset
	})
	return matches
}
