package types

import (
	"fmt"
	"strings"
)

// LabelKind ranks where a label name came from; lower values win.
type LabelKind int

const (
	LabelUser    LabelKind = iota // symbols file
	LabelHint                     // hint label in the YAML
	LabelSegment                  // segment name
	LabelSub                      // subroutine / pointer target
	LabelLoc                      // local branch target
	LabelData                     // data reference
)

// Labels is the global label table built before any segment is written.
// Only addresses that will actually be defined in the output (instruction
// boundaries, segment starts, hint starts, equates outside the ROM) are
// present, so every emitted label reference assembles.
type Labels struct {
	ByAddr LabelMap
	Kind   map[uint32]LabelKind
	ByName map[string]uint32
	// Imm is the subset of ByAddr that may replace 32-bit immediates.
	Imm LabelMap
	// Comments holds documentation for labels (from the symbols file).
	Comments map[uint32]string
}

// NewLabels returns an empty label table.
func NewLabels() *Labels {
	return &Labels{ByAddr: LabelMap{}, Kind: map[uint32]LabelKind{}, ByName: map[string]uint32{}, Imm: LabelMap{}, Comments: map[uint32]string{}}
}

// Set assigns name to addr unless a higher-priority label already exists or
// the name is taken by another address. Returns true when name was stored.
func (l *Labels) Set(addr uint32, name string, kind LabelKind) bool {
	if name == "" {
		return false
	}
	if old, ok := l.Kind[addr]; ok && old <= kind {
		return false
	}
	if other, ok := l.ByName[name]; ok && other != addr {
		return false
	}
	if oldName, ok := l.ByAddr[addr]; ok {
		delete(l.ByName, oldName)
	}
	l.ByAddr[addr] = name
	l.Kind[addr] = kind
	l.ByName[name] = addr
	return true
}

// Get returns the label at addr.
func (l *Labels) Get(addr uint32) (string, bool) {
	if l == nil {
		return "", false
	}
	n, ok := l.ByAddr[addr]
	return n, ok
}

// OrHex returns the label at addr or a "$XXXXXX" literal.
func (l *Labels) OrHex(addr uint32) string {
	if n, ok := l.Get(addr); ok {
		return n
	}
	return fmt.Sprintf("$%06X", addr)
}

// Def returns the text that defines the label at addr: an optional comment
// block followed by "name:". It returns "" when addr has no label.
func (l *Labels) Def(addr uint32) string {
	n, ok := l.Get(addr)
	if !ok {
		return ""
	}
	c := l.Comments[addr]
	if c == "" {
		return n + ":\n"
	}
	out := ""
	for _, line := range strings.Split(c, "\\n") {
		out += "; " + strings.TrimSpace(line) + "\n"
	}
	return out + n + ":\n"
}
