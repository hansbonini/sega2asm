package analysis

import (
	"fmt"
	"io"
	"sort"

	"sega2asm/disasm/m68k"
	"sega2asm/types"
)

// Region is a maximal run of bytes with the same classification.
type Region struct {
	Start, End uint32
	Kind       ByteKind
}

func (k ByteKind) String() string {
	switch k {
	case CodeHead, CodeTail:
		return "code"
	case Data:
		return "data"
	}
	return "unknown"
}

// Regions returns the ROM split into code / data / unknown runs.
func (r *Result) Regions() []Region {
	var out []Region
	norm := func(k ByteKind) ByteKind {
		if k == CodeTail {
			return CodeHead
		}
		return k
	}
	n := uint32(len(r.Kind))
	start := uint32(0)
	for a := uint32(1); a <= n; a++ {
		if a == n || norm(r.Kind[a]) != norm(r.Kind[start]) {
			out = append(out, Region{Start: start, End: a, Kind: norm(r.Kind[start])})
			start = a
		}
	}
	return out
}

// Stats returns byte counts per class.
func (r *Result) Stats() (code, data, unknown int) {
	for _, k := range r.Kind {
		switch k {
		case CodeHead, CodeTail:
			code++
		case Data:
			data++
		default:
			unknown++
		}
	}
	return
}

// SortedEntries returns function entry points in address order.
func (r *Result) SortedEntries() []uint32 {
	out := make([]uint32, 0, len(r.Entries))
	for a := range r.Entries {
		out = append(out, a)
	}
	sort.Slice(out, func(i, j int) bool { return out[i] < out[j] })
	return out
}

func (k EntryKind) String() string {
	switch k {
	case EntryVector:
		return "vector"
	case EntryCall:
		return "call"
	case EntryTable:
		return "table"
	case EntryPointer:
		return "pointer"
	case EntryUser:
		return "user"
	case EntryOrphan:
		return "orphan"
	}
	return "?"
}

// WriteReport writes a human-readable analysis report.
func (r *Result) WriteReport(w io.Writer) {
	code, data, unk := r.Stats()
	fmt.Fprintf(w, "; sega2asm analysis report\n")
	fmt.Fprintf(w, "; code: %d bytes  data: %d bytes  unknown: %d bytes\n", code, data, unk)
	fmt.Fprintf(w, "; functions: %d  tables: %d  unresolved indirect: %d  conflicts: %d\n\n",
		len(r.Entries), len(r.Tables), len(r.Indirect), len(r.Conflicts))

	fmt.Fprintf(w, "[regions]\n")
	for _, rg := range r.Regions() {
		fmt.Fprintf(w, "$%06X-$%06X %-7s %d\n", rg.Start, rg.End, rg.Kind, rg.End-rg.Start)
	}
	fmt.Fprintf(w, "\n[tables]\n")
	for _, t := range r.Tables {
		fmt.Fprintf(w, "$%06X %-8s count=%d base=$%06X from=$%06X\n", t.Addr, t.Kind, t.Count, t.Base, t.From)
	}
	fmt.Fprintf(w, "\n[indirect]\n")
	for _, a := range r.Indirect {
		fmt.Fprintf(w, "$%06X %s\n", a, r.Insns[a].Text)
	}
	fmt.Fprintf(w, "\n[conflicts]\n")
	for _, c := range r.Conflicts {
		fmt.Fprintln(w, c)
	}
	fmt.Fprintf(w, "\n[rejected pointers]\n")
	var rej []uint32
	for a := range r.Rejected {
		rej = append(rej, a)
	}
	sort.Slice(rej, func(i, j int) bool { return rej[i] < rej[j] })
	for _, a := range rej {
		fmt.Fprintf(w, "$%06X %s\n", a, r.Rejected[a])
	}
	fmt.Fprintf(w, "\n[xrefs]\n")
	var xs []uint32
	for a := range r.Xrefs {
		if int(a) < len(r.Kind) && r.Kind[a] != CodeHead && r.Kind[a] != CodeTail {
			xs = append(xs, a)
		}
	}
	sort.Slice(xs, func(i, j int) bool { return xs[i] < xs[j] })
	for _, a := range xs {
		fmt.Fprintf(w, "$%06X", a)
		for _, x := range r.Xrefs[a] {
			fmt.Fprintf(w, " %s@$%06X", refKindName(x.Kind, x.Size), x.From)
		}
		fmt.Fprintln(w)
	}
	fmt.Fprintf(w, "\n[entries]\n")
	for _, a := range r.SortedEntries() {
		fmt.Fprintf(w, "$%06X %s\n", a, r.Entries[a])
	}
}

// OptionsFromConfig converts the YAML analysis block into tracer options.
func OptionsFromConfig(c types.AnalysisConfig) Options {
	o := Options{CodeEnd: uint32(c.CodeEnd), Orphans: c.Orphans == nil || *c.Orphans}
	for _, e := range c.Entries {
		o.Entries = append(o.Entries, uint32(e))
	}
	for _, e := range c.NoReturn {
		o.NoReturn = append(o.NoReturn, uint32(e))
	}
	for _, d := range c.Data {
		o.Data = append(o.Data, Range{Start: uint32(d.Start), End: uint32(d.End)})
	}
	for _, t := range c.Tables {
		o.Tables = append(o.Tables, Table{Addr: uint32(t.Addr), Kind: TableKind(t.Type), Count: t.Count, Base: uint32(t.Base)})
	}
	return o
}

func refKindName(k m68k.RefKind, size int) string {
	switch k {
	case m68k.RefCode:
		return "code"
	case m68k.RefData:
		return fmt.Sprintf("data%d", size)
	case m68k.RefImm:
		return "imm"
	case m68k.RefIndexed:
		return fmt.Sprintf("idx%d", size)
	case m68k.RefEffAddr:
		return "lea"
	}
	return "?"
}
