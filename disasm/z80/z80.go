// Package z80 implements a Z80 disassembler.
// Based on https://github.com/Clownacy/clownz80
// Output is compatible with standard Z80 assembler syntax.
package z80

import "fmt"

// Result holds one disassembled Z80 instruction.
type Result struct {
	Addr    uint32
	Bytes   []byte
	Text    string
	IsValid bool
}

// Disassembler disassembles Z80 code from a byte slice.
type Disassembler struct {
	data   []byte
	base   uint32
	labels map[uint32]string
	pos    int
}

// New creates a Z80 Disassembler.
func New(data []byte, baseAddr uint32, labels map[uint32]string) *Disassembler {
	if labels == nil {
		labels = make(map[uint32]string)
	}
	return &Disassembler{data: data, base: baseAddr, labels: labels}
}

func (d *Disassembler) PC() uint32    { return d.base + uint32(d.pos) }
func (d *Disassembler) Remaining() int { return len(d.data) - d.pos }

// Next disassembles the instruction at the current position.
func (d *Disassembler) Next() Result {
	if d.pos >= len(d.data) {
		return Result{Addr: d.PC(), IsValid: false}
	}
	startPos := d.pos
	startPC := d.PC()
	text, ok := d.decode()
	if !ok {
		d.pos = startPos + 1
		text = fmt.Sprintf("\tdefb\t$%02X", d.data[startPos])
	}
	return Result{
		Addr:    startPC,
		Bytes:   append([]byte(nil), d.data[startPos:d.pos]...),
		Text:    text,
		IsValid: ok,
	}
}

func (d *Disassembler) rb() byte {
	if d.pos >= len(d.data) {
		return 0
	}
	b := d.data[d.pos]
	d.pos++
	return b
}

func (d *Disassembler) rw() uint16 {
	lo := uint16(d.rb())
	hi := uint16(d.rb())
	return hi<<8 | lo
}

func (d *Disassembler) rel() uint32 {
	offset := int8(d.rb())
	return uint32(int32(d.PC()) + int32(offset))
}

func (d *Disassembler) label(addr uint32) string {
	if name, ok := d.labels[addr]; ok {
		return name
	}
	return fmt.Sprintf("$%04X", addr)
}

// ---------------------------------------------------------------------------
// Main decode
// ---------------------------------------------------------------------------

func (d *Disassembler) decode() (string, bool) {
	op := d.rb()
	switch op {
	// --- 0x00-0x3F ---
	case 0x00: return "\tnop", true
	case 0x01: return fmt.Sprintf("\tld\tbc,$%04X", d.rw()), true
	case 0x02: return "\tld\t(bc),a", true
	case 0x03: return "\tinc\tbc", true
	case 0x04: return "\tinc\tb", true
	case 0x05: return "\tdec\tb", true
	case 0x06: return fmt.Sprintf("\tld\tb,$%02X", d.rb()), true
	case 0x07: return "\trlca", true
	case 0x08: return "\tex\taf,af'", true
	case 0x09: return "\tadd\thl,bc", true
	case 0x0A: return "\tld\ta,(bc)", true
	case 0x0B: return "\tdec\tbc", true
	case 0x0C: return "\tinc\tc", true
	case 0x0D: return "\tdec\tc", true
	case 0x0E: return fmt.Sprintf("\tld\tc,$%02X", d.rb()), true
	case 0x0F: return "\trrca", true
	case 0x10: return fmt.Sprintf("\tdjnz\t%s", d.label(d.rel())), true
	case 0x11: return fmt.Sprintf("\tld\tde,$%04X", d.rw()), true
	case 0x12: return "\tld\t(de),a", true
	case 0x13: return "\tinc\tde", true
	case 0x14: return "\tinc\td", true
	case 0x15: return "\tdec\td", true
	case 0x16: return fmt.Sprintf("\tld\td,$%02X", d.rb()), true
	case 0x17: return "\trla", true
	case 0x18: return fmt.Sprintf("\tjr\t%s", d.label(d.rel())), true
	case 0x19: return "\tadd\thl,de", true
	case 0x1A: return "\tld\ta,(de)", true
	case 0x1B: return "\tdec\tde", true
	case 0x1C: return "\tinc\te", true
	case 0x1D: return "\tdec\te", true
	case 0x1E: return fmt.Sprintf("\tld\te,$%02X", d.rb()), true
	case 0x1F: return "\trra", true
	case 0x20: return fmt.Sprintf("\tjr\tnz,%s", d.label(d.rel())), true
	case 0x21: return fmt.Sprintf("\tld\thl,$%04X", d.rw()), true
	case 0x22: return fmt.Sprintf("\tld\t($%04X),hl", d.rw()), true
	case 0x23: return "\tinc\thl", true
	case 0x24: return "\tinc\th", true
	case 0x25: return "\tdec\th", true
	case 0x26: return fmt.Sprintf("\tld\th,$%02X", d.rb()), true
	case 0x27: return "\tdaa", true
	case 0x28: return fmt.Sprintf("\tjr\tz,%s", d.label(d.rel())), true
	case 0x29: return "\tadd\thl,hl", true
	case 0x2A: return fmt.Sprintf("\tld\thl,($%04X)", d.rw()), true
	case 0x2B: return "\tdec\thl", true
	case 0x2C: return "\tinc\tl", true
	case 0x2D: return "\tdec\tl", true
	case 0x2E: return fmt.Sprintf("\tld\tl,$%02X", d.rb()), true
	case 0x2F: return "\tcpl", true
	case 0x30: return fmt.Sprintf("\tjr\tnc,%s", d.label(d.rel())), true
	case 0x31: return fmt.Sprintf("\tld\tsp,$%04X", d.rw()), true
	case 0x32: return fmt.Sprintf("\tld\t($%04X),a", d.rw()), true
	case 0x33: return "\tinc\tsp", true
	case 0x34: return "\tinc\t(hl)", true
	case 0x35: return "\tdec\t(hl)", true
	case 0x36: return fmt.Sprintf("\tld\t(hl),$%02X", d.rb()), true
	case 0x37: return "\tscf", true
	case 0x38: return fmt.Sprintf("\tjr\tc,%s", d.label(d.rel())), true
	case 0x39: return "\tadd\thl,sp", true
	case 0x3A: return fmt.Sprintf("\tld\ta,($%04X)", d.rw()), true
	case 0x3B: return "\tdec\tsp", true
	case 0x3C: return "\tinc\ta", true
	case 0x3D: return "\tdec\ta", true
	case 0x3E: return fmt.Sprintf("\tld\ta,$%02X", d.rb()), true
	case 0x3F: return "\tccf", true

	// --- 0x40-0x7F LD r,r (except 0x76 HALT) ---
	case 0x76: return "\thalt", true

	// --- 0x80-0xBF ALU ---
	// --- 0xC0-0xFF misc ---
	case 0xC0: return "\tret\tnz", true
	case 0xC1: return "\tpop\tbc", true
	case 0xC2: return fmt.Sprintf("\tjp\tnz,%s", d.label(uint32(d.rw()))), true
	case 0xC3: return fmt.Sprintf("\tjp\t%s", d.label(uint32(d.rw()))), true
	case 0xC4: return fmt.Sprintf("\tcall\tnz,%s", d.label(uint32(d.rw()))), true
	case 0xC5: return "\tpush\tbc", true
	case 0xC6: return fmt.Sprintf("\tadd\ta,$%02X", d.rb()), true
	case 0xC7: return "\trst\t$00", true
	case 0xC8: return "\tret\tz", true
	case 0xC9: return "\tret", true
	case 0xCA: return fmt.Sprintf("\tjp\tz,%s", d.label(uint32(d.rw()))), true
	case 0xCB: return d.decodeCB()
	case 0xCC: return fmt.Sprintf("\tcall\tz,%s", d.label(uint32(d.rw()))), true
	case 0xCD: return fmt.Sprintf("\tcall\t%s", d.label(uint32(d.rw()))), true
	case 0xCE: return fmt.Sprintf("\tadc\ta,$%02X", d.rb()), true
	case 0xCF: return "\trst\t$08", true
	case 0xD0: return "\tret\tnc", true
	case 0xD1: return "\tpop\tde", true
	case 0xD2: return fmt.Sprintf("\tjp\tnc,%s", d.label(uint32(d.rw()))), true
	case 0xD3: return fmt.Sprintf("\tout\t($%02X),a", d.rb()), true
	case 0xD4: return fmt.Sprintf("\tcall\tnc,%s", d.label(uint32(d.rw()))), true
	case 0xD5: return "\tpush\tde", true
	case 0xD6: return fmt.Sprintf("\tsub\t$%02X", d.rb()), true
	case 0xD7: return "\trst\t$10", true
	case 0xD8: return "\tret\tc", true
	case 0xD9: return "\texx", true
	case 0xDA: return fmt.Sprintf("\tjp\tc,%s", d.label(uint32(d.rw()))), true
	case 0xDB: return fmt.Sprintf("\tin\ta,($%02X)", d.rb()), true
	case 0xDC: return fmt.Sprintf("\tcall\tc,%s", d.label(uint32(d.rw()))), true
	case 0xDD: return d.decodeDD()
	case 0xDE: return fmt.Sprintf("\tsbc\ta,$%02X", d.rb()), true
	case 0xDF: return "\trst\t$18", true
	case 0xE0: return "\tret\tpo", true
	case 0xE1: return "\tpop\thl", true
	case 0xE2: return fmt.Sprintf("\tjp\tpo,%s", d.label(uint32(d.rw()))), true
	case 0xE3: return "\tex\t(sp),hl", true
	case 0xE4: return fmt.Sprintf("\tcall\tpo,%s", d.label(uint32(d.rw()))), true
	case 0xE5: return "\tpush\thl", true
	case 0xE6: return fmt.Sprintf("\tand\t$%02X", d.rb()), true
	case 0xE7: return "\trst\t$20", true
	case 0xE8: return "\tret\tpe", true
	case 0xE9: return "\tjp\t(hl)", true
	case 0xEA: return fmt.Sprintf("\tjp\tpe,%s", d.label(uint32(d.rw()))), true
	case 0xEB: return "\tex\tde,hl", true
	case 0xEC: return fmt.Sprintf("\tcall\tpe,%s", d.label(uint32(d.rw()))), true
	case 0xED: return d.decodeED()
	case 0xEE: return fmt.Sprintf("\txor\t$%02X", d.rb()), true
	case 0xEF: return "\trst\t$28", true
	case 0xF0: return "\tret\tp", true
	case 0xF1: return "\tpop\taf", true
	case 0xF2: return fmt.Sprintf("\tjp\tp,%s", d.label(uint32(d.rw()))), true
	case 0xF3: return "\tdi", true
	case 0xF4: return fmt.Sprintf("\tcall\tp,%s", d.label(uint32(d.rw()))), true
	case 0xF5: return "\tpush\taf", true
	case 0xF6: return fmt.Sprintf("\tor\t$%02X", d.rb()), true
	case 0xF7: return "\trst\t$30", true
	case 0xF8: return "\tret\tm", true
	case 0xF9: return "\tld\tsp,hl", true
	case 0xFA: return fmt.Sprintf("\tjp\tm,%s", d.label(uint32(d.rw()))), true
	case 0xFB: return "\tei", true
	case 0xFC: return fmt.Sprintf("\tcall\tm,%s", d.label(uint32(d.rw()))), true
	case 0xFD: return d.decodeFD()
	case 0xFE: return fmt.Sprintf("\tcp\t$%02X", d.rb()), true
	case 0xFF: return "\trst\t$38", true
	}

	// 0x40-0x7F LD table
	if op >= 0x40 && op <= 0x7F {
		dst := regName((op >> 3) & 7)
		src := regName(op & 7)
		return fmt.Sprintf("\tld\t%s,%s", dst, src), true
	}
	// 0x80-0xBF ALU table
	if op >= 0x80 && op <= 0xBF {
		return aluOp(op>>3&7, regName(op&7))
	}
	return "", false
}

func (d *Disassembler) decodeCB() (string, bool) {
	op := d.rb()
	bit := (op >> 3) & 7
	reg := regName(op & 7)
	switch op >> 6 {
	case 0:
		ops := []string{"rlc","rrc","rl","rr","sla","sra","sll","srl"}
		return fmt.Sprintf("\t%s\t%s", ops[bit], reg), true
	case 1:
		return fmt.Sprintf("\tbit\t%d,%s", bit, reg), true
	case 2:
		return fmt.Sprintf("\tres\t%d,%s", bit, reg), true
	case 3:
		return fmt.Sprintf("\tset\t%d,%s", bit, reg), true
	}
	return "", false
}

func (d *Disassembler) decodeDD() (string, bool) {
	op := d.rb()
	switch op {
	case 0x09: return "\tadd\tix,bc", true
	case 0x19: return "\tadd\tix,de", true
	case 0x21: return fmt.Sprintf("\tld\tix,$%04X", d.rw()), true
	case 0x22: return fmt.Sprintf("\tld\t($%04X),ix", d.rw()), true
	case 0x23: return "\tinc\tix", true
	case 0x29: return "\tadd\tix,ix", true
	case 0x2A: return fmt.Sprintf("\tld\tix,($%04X)", d.rw()), true
	case 0x2B: return "\tdec\tix", true
	case 0x34: return fmt.Sprintf("\tinc\t(ix+$%02X)", d.rb()), true
	case 0x35: return fmt.Sprintf("\tdec\t(ix+$%02X)", d.rb()), true
	case 0x36: disp := d.rb(); n := d.rb(); return fmt.Sprintf("\tld\t(ix+$%02X),$%02X", disp, n), true
	case 0x39: return "\tadd\tix,sp", true
	case 0xE1: return "\tpop\tix", true
	case 0xE3: return "\tex\t(sp),ix", true
	case 0xE5: return "\tpush\tix", true
	case 0xE9: return "\tjp\t(ix)", true
	case 0xF9: return "\tld\tsp,ix", true
	}
	if op >= 0x46 && op <= 0x7E {
		disp := d.rb()
		return fmt.Sprintf("\tld\t%s,(ix+$%02X)", regName((op>>3)&7), disp), true
	}
	return fmt.Sprintf("\tdd $%02X", op), false
}

func (d *Disassembler) decodeFD() (string, bool) {
	op := d.rb()
	switch op {
	case 0x09: return "\tadd\tiy,bc", true
	case 0x19: return "\tadd\tiy,de", true
	case 0x21: return fmt.Sprintf("\tld\tiy,$%04X", d.rw()), true
	case 0x22: return fmt.Sprintf("\tld\t($%04X),iy", d.rw()), true
	case 0x23: return "\tinc\tiy", true
	case 0x29: return "\tadd\tiy,iy", true
	case 0x2A: return fmt.Sprintf("\tld\tiy,($%04X)", d.rw()), true
	case 0x2B: return "\tdec\tiy", true
	case 0x39: return "\tadd\tiy,sp", true
	case 0xE1: return "\tpop\tiy", true
	case 0xE3: return "\tex\t(sp),iy", true
	case 0xE5: return "\tpush\tiy", true
	case 0xE9: return "\tjp\t(iy)", true
	case 0xF9: return "\tld\tsp,iy", true
	}
	return fmt.Sprintf("\tfd $%02X", op), false
}

func (d *Disassembler) decodeED() (string, bool) {
	op := d.rb()
	switch op {
	case 0x44: return "\tneg", true
	case 0x45: return "\tretn", true
	case 0x46: return "\tim\t0", true
	case 0x47: return "\tld\ti,a", true
	case 0x4D: return "\treti", true
	case 0x4F: return "\tld\tr,a", true
	case 0x56: return "\tim\t1", true
	case 0x57: return "\tld\ta,i", true
	case 0x5E: return "\tim\t2", true
	case 0x5F: return "\tld\ta,r", true
	case 0x67: return "\trrd", true
	case 0x6F: return "\trld", true
	case 0xA0: return "\tldi", true
	case 0xA1: return "\tcpi", true
	case 0xA2: return "\tini", true
	case 0xA3: return "\touti", true
	case 0xA8: return "\tldd", true
	case 0xA9: return "\tcpd", true
	case 0xAA: return "\tind", true
	case 0xAB: return "\toutd", true
	case 0xB0: return "\tldir", true
	case 0xB1: return "\tcpir", true
	case 0xB2: return "\tinir", true
	case 0xB3: return "\totir", true
	case 0xB8: return "\tlddr", true
	case 0xB9: return "\tcpdr", true
	case 0xBA: return "\tindr", true
	case 0xBB: return "\totdr", true
	}
	if op&0xC7 == 0x43 {
		rp := []string{"bc","de","hl","sp"}[(op>>4)&3]
		addr := d.rw()
		if op&0x08 != 0 {
			return fmt.Sprintf("\tld\t%s,($%04X)", rp, addr), true
		}
		return fmt.Sprintf("\tld\t($%04X),%s", addr, rp), true
	}
	return fmt.Sprintf("\tdefb\t$ED,$%02X", op), false
}

func regName(r byte) string {
	return []string{"b","c","d","e","h","l","(hl)","a"}[r&7]
}

func aluOp(kind byte, reg string) (string, bool) {
	ops := []string{"add a,","adc a,","sub ","sbc a,","and ","xor ","or ","cp "}
	return fmt.Sprintf("\t%s%s", ops[kind&7], reg), true
}

// DisassembleBlock disassembles Z80 code in data[start:end].
func DisassembleBlock(data []byte, baseAddr, start, end uint32, labels map[uint32]string) []Result {
	seg := data[start:end]
	d := New(seg, baseAddr+start, labels)
	var results []Result
	for d.Remaining() > 0 {
		results = append(results, d.Next())
	}
	return results
}
