package m68k

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"

	"sega2asm/types"
)

// The round-trip tests feed every 16-bit opcode word (followed by a fixed set
// of extension words) through the disassembler, re-assemble the emitted text
// with clownassembler (asm68k-compatible) and require the assembled bytes to
// match the original bytes exactly. This is what guarantees that a split
// disassembly rebuilds into a bit-identical ROM.
//
// The assembler is located through $CLOWNASSEMBLER or PATH; the test is
// skipped when it is not available.

const rtSlot = 16 // bytes reserved per instruction (68000 max is 10)

var locRe = regexp.MustCompile(`loc_([0-9A-F]{6})`)

func findAssembler(t *testing.T) string {
	t.Helper()
	if p := os.Getenv("CLOWNASSEMBLER"); p != "" {
		return p
	}
	if p, err := exec.LookPath("clownassembler"); err == nil {
		return p
	}
	t.Skip("clownassembler not found (set $CLOWNASSEMBLER)")
	return ""
}

type rtCase struct {
	op   uint16
	addr uint32
	res  Result
	src  []byte
}

// roundTrip disassembles all opcode words using the given extension words and
// returns a description of every mismatch.
func roundTrip(t *testing.T, asm string, ext []uint16) []string {
	t.Helper()
	buf := make([]byte, 0x10000*rtSlot)
	for op := 0; op < 0x10000; op++ {
		base := op * rtSlot
		buf[base] = byte(op >> 8)
		buf[base+1] = byte(op)
		for i, e := range ext {
			buf[base+2+i*2] = byte(e >> 8)
			buf[base+3+i*2] = byte(e)
		}
	}

	var cases []rtCase
	for op := 0; op < 0x10000; op++ {
		base := op * rtSlot
		d := New(buf[base:base+2+len(ext)*2], uint32(base), types.LabelMap{})
		res := d.Next()
		if !res.IsValid {
			continue
		}
		cases = append(cases, rtCase{op: uint16(op), addr: uint32(base), res: res, src: buf[base : base+len(res.Bytes)]})
	}

	dir := t.TempDir()
	var fails []string
	// Assemble in chunks; a chunk that fails is re-assembled one instruction
	// at a time so every failure is attributed to its opcode.
	const chunk = 512
	for i := 0; i < len(cases); i += chunk {
		j := i + chunk
		if j > len(cases) {
			j = len(cases)
		}
		if f := assembleCases(asm, dir, cases[i:j]); f != nil {
			for k := i; k < j; k++ {
				fails = append(fails, assembleCases(asm, dir, cases[k:k+1])...)
			}
		}
	}
	return fails
}

// assembleCases assembles the given cases and returns mismatches (nil = OK).
func assembleCases(asm, dir string, cases []rtCase) []string {
	var sb strings.Builder
	sb.WriteString(Macros)
	labels := map[string]bool{}
	for _, c := range cases {
		for _, m := range locRe.FindAllStringSubmatch(c.res.Text, -1) {
			labels[m[1]] = true
		}
	}
	for k := range labels {
		sb.WriteString(fmt.Sprintf("loc_%s\tequ\t$%s\n", k, k))
	}
	for _, c := range cases {
		sb.WriteString(fmt.Sprintf("\torg\t$%X\n%s\n", c.addr, c.res.Text))
	}
	src := filepath.Join(dir, "rt.asm")
	out := filepath.Join(dir, "rt.bin")
	os.Remove(out)
	if err := os.WriteFile(src, []byte(sb.String()), 0644); err != nil {
		return []string{err.Error()}
	}
	msg, err := exec.Command(asm, "-i", src, "-o", out, "-w", "-p").CombinedOutput()
	desc := func(c rtCase) string {
		return fmt.Sprintf("op=$%04X %-36q", c.op, strings.TrimSpace(c.res.Text))
	}
	if err != nil {
		if len(cases) == 1 {
			first := strings.SplitN(strings.TrimSpace(string(msg)), "\n", 2)[0]
			return []string{desc(cases[0]) + " asm error: " + first}
		}
		return []string{"chunk failed"}
	}
	bin, err := os.ReadFile(out)
	if err != nil {
		return []string{"no output"}
	}
	var fails []string
	for _, c := range cases {
		end := int(c.addr) + len(c.src)
		var got []byte
		if end <= len(bin) {
			got = bin[c.addr:end]
		}
		if !bytes.Equal(got, c.src) {
			fails = append(fails, fmt.Sprintf("%s want % X got % X", desc(c), c.src, got))
			continue
		}
		// The assembler must not emit more bytes than the source instruction.
		if end+2 <= len(bin) && end < int(c.addr)+rtSlot && (bin[end] != 0 || bin[end+1] != 0) {
			fails = append(fails, fmt.Sprintf("%s assembled longer than %d bytes", desc(c), len(c.src)))
		}
	}
	return fails
}

func runRoundTrip(t *testing.T, ext []uint16) {
	asm := findAssembler(t)
	fails := roundTrip(t, asm, ext)
	for i, f := range fails {
		if i >= 200 {
			t.Errorf("... and %d more", len(fails)-i)
			break
		}
		t.Error(f)
	}
}

func TestRoundTripSmallExt(t *testing.T) {
	runRoundTrip(t, []uint16{0x0004, 0x0006, 0x0008, 0x000A})
}

func TestRoundTripNegativeExt(t *testing.T) {
	runRoundTrip(t, []uint16{0xFFF0, 0x8002, 0x7FFE, 0x1234})
}

func TestRoundTripAddrRegIndexExt(t *testing.T) {
	runRoundTrip(t, []uint16{0xB87C, 0x00FF, 0xFF00, 0x0000})
}

func TestRoundTripHighBitsExt(t *testing.T) {
	// Non-canonical extension words (e.g. garbage in bits 8-10 of a brief
	// extension word or in the high byte of a byte immediate) must be emitted
	// as dc.w, never as an instruction that re-assembles differently.
	runRoundTrip(t, []uint16{0x0F12, 0x7654, 0xFEDC, 0x0301})
}

func TestOpcodeCoverage(t *testing.T) {
	n := 0
	buf := []byte{0, 0, 0, 4, 0, 6, 0, 8, 0, 10}
	for op := 0; op < 0x10000; op++ {
		buf[0], buf[1] = byte(op>>8), byte(op)
		if New(buf, 0, nil).Next().IsValid {
			n++
		}
	}
	// Every legal 68000 opcode word (with canonical extension words).
	if n != 45800 {
		t.Errorf("decoded %d opcode words, want 45800", n)
	}
}

func TestGoldenDecode(t *testing.T) {
	tests := []struct {
		hex  string
		addr uint32
		want string
	}{
		{"46FC2700", 0, "move.w\t#$2700,sr"},
		{"00680004 0006", 0, "ori.w\t#$0004,$6(a0)"},
		{"0C6E0040 0554", 0, "cmpi.w\t#$0040,$554(a6)"},
		{"0850 0003", 0, "bchg\t#3,(a0)"},
		{"0890 0003", 0, "bclr\t#3,(a0)"},
		{"4841", 0, "swap\td1"},
		{"4882", 0, "ext.w\td2"},
		{"48C3", 0, "ext.l\td3"},
		{"48E7FFFE", 0, "movem.l\td0-d7/a0-a6,-(a7)"},
		{"4CDF7FFF", 0, "movem.l\t(a7)+,d0-d7/a0-a6"},
		{"4CDF0C03", 0, "movem.l\t(a7)+,d0-d1/a2-a3"},
		{"4EFB0006", 0x100, "jmp\t$000108(pc,d0.w)"},
		{"41FA0010", 0x100, "lea\t$000112(pc),a0"},
		{"6100FFFE", 0x100, "bsr.w\t$000100"},
		{"51C8FFFC", 0x100, "dbf\td0,$0000FE"},
		{"30388000", 0, "move.w\t($FFFF8000).w,d0"},
		{"4EB90014 4318", 0, "jsr\t($144318).l"},
		{"D07C0004", 0, "add_ea.w\t#$0004,d0"},
		{"C03C000F", 0, "and_ea.b\t#$0F,d0"},
		{"B4BC0001 0000", 0, "cmp_ea.l\t#$00010000,d2"},
		{"8A7CC000", 0, "or_ea.w\t#$C000,d5"},
		{"9A7C0020", 0, "sub_ea.w\t#$0020,d5"},
		{"D03C12FF", 0, "dc.w\t$D03C,$12FF\t; add_ea.b #$FF,d0"},
		{"4AFC", 0, "illegal"},
		{"4E7A0801", 0, "dc.w\t$4E7A"},
		{"23FC5345 474100A1 4000", 0, "move.l\t#'SEGA',(TMSS_REG).l"},
		{"0108 0004", 0, "movep.w\t$4(a0),d0"},
		{"C189", 0, "exg\td0,a1"},
		{"E1D0", 0, "asl.w\t(a0)"},
		{"E548", 0, "lsl.w\t#2,d0"},
	}
	for _, tc := range tests {
		var b []byte
		h := strings.ReplaceAll(tc.hex, " ", "")
		for i := 0; i+1 < len(h); i += 2 {
			v, _ := strconv.ParseUint(h[i:i+2], 16, 8)
			b = append(b, byte(v))
		}
		got := strings.TrimPrefix(New(b, tc.addr, nil).Next().Text, "\t")
		if got != tc.want {
			t.Errorf("% X: got %q want %q", b, got, tc.want)
		}
	}
}
