package compress

import "fmt"

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

// registry maps algorithm names to their Algorithm descriptors.
var registry = map[string]*Algorithm{}

// algorithms preserves insertion order for iteration.
var algorithms []*Algorithm

// Register adds an algorithm to the global registry.
func Register(a Algorithm) {
	alg := &Algorithm{
		Name:        a.Name,
		Family:      a.Family,
		Description: a.Description,
		Decompress:  a.Decompress,
	}
	registry[a.Name] = alg
	algorithms = append(algorithms, alg)
}

// Lookup returns the Algorithm for the given name, or nil if not found.
func Lookup(name string) *Algorithm {
	return registry[name]
}

// Algorithms returns all registered algorithms in registration order.
func Algorithms() []*Algorithm {
	return algorithms
}

// Decompress decompresses src using the named algorithm.
// Algorithm names are registered via init() in each algorithm file.
func Decompress(compression string, src []byte) ([]byte, error) {
	if compression == "" {
		compression = "none"
	}
	alg := Lookup(compression)
	if alg == nil {
		return nil, fmt.Errorf("unknown compression %q", compression)
	}
	return alg.Decompress(src)
}
