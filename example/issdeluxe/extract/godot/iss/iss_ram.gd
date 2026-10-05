class_name ISSRam
extends RefCounted
## The game's work RAM ($FF0000-$FFFFFF) for the front end: the screens are
## ports of the game's own code, which keeps its state in RAM at fixed
## addresses (the globals block at a6 = $FF0000, the menu objects, the
## unpack buffer and the text nametable in it). Addresses here are offsets
## from $FF0000, the a6-relative offsets of the listing; the named ones are
## the symbols file's (g_menu_item = $1766 ...). Words and longs are big
## endian.

static var m := PackedByteArray()


static func ensure() -> void:
	if m.is_empty():
		m.resize(0x10000)


static func b(a: int) -> int:
	return m[a & 0xFFFF]


static func sb(a: int) -> int:
	var v: int = m[a & 0xFFFF]
	return v - 256 if v >= 128 else v


static func w(a: int) -> int:
	a &= 0xFFFF
	return (m[a] << 8) | m[a + 1]


static func sw(a: int) -> int:
	var v := w(a)
	return v - 65536 if v >= 32768 else v


static func l(a: int) -> int:
	return (w(a) << 16) | w(a + 2)


static func sl(a: int) -> int:
	var v := l(a)
	return v - 0x100000000 if v >= 0x80000000 else v


static func set_b(a: int, v: int) -> void:
	m[a & 0xFFFF] = v & 0xFF


static func set_w(a: int, v: int) -> void:
	a &= 0xFFFF
	m[a] = (v >> 8) & 0xFF
	m[a + 1] = v & 0xFF


static func set_l(a: int, v: int) -> void:
	set_w(a, (v >> 16) & 0xFFFF)
	set_w(a + 2, v & 0xFFFF)


static func add_w(a: int, v: int) -> void:
	set_w(a, w(a) + v)


static func or_w(a: int, v: int) -> void:
	set_w(a, w(a) | v)


static func and_w(a: int, v: int) -> void:
	set_w(a, w(a) & v)


static func clear(a: int, n: int) -> void:
	for i in n:
		m[(a + i) & 0xFFFF] = 0


static func copy_in(a: int, data: PackedByteArray) -> void:
	for i in data.size():
		m[(a + i) & 0xFFFF] = data[i]


static func copy(dst: int, src: int, n: int) -> void:
	var tmp := m.slice(src & 0xFFFF, (src & 0xFFFF) + n)
	copy_in(dst, tmp)


static func slice(a: int, n: int) -> PackedByteArray:
	a &= 0xFFFF
	return m.slice(a, a + n)
