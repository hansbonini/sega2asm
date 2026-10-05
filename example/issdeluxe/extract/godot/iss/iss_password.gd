class_name ISSPassword
extends RefCounted
## The competitions' passwords: g_password ($1388) holds a checksum byte, a
## key byte and the mode's fields as a bit stream (most significant bit
## first) from bit 16 (g_password_bit); every byte after the key is XORed
## with it. A password is shown and entered as 6-bit characters, so its
## length in bits (g_password_length) is a multiple of 6 and tells which
## mode it restores. The fields of each mode are the ones its
## password_encode_* writes and its mode_resume_* reads back.

const S := preload("res://iss/iss_sym.gd")

## Per game mode: the length in bits, then [bits, RAM word, count] (count
## words from the address on; "bytes" a byte pair per entry: 1 + 7 bits).
const FIELDS := {
	4: [0x60, [[3, S.g_game_level, 1], [3, 0x1266, 1], [4, 0x1270, 1], [6, 0x127C, 6], [2, 0x129C, 15]]],
	5: [0x66, [[3, S.g_game_level, 1], [4, 0x1266, 1], [3, 0x1270, 1], [6, 0x127C, 8], [3, 0x129C, 7]]],
	6: [0x30, [[3, S.g_game_level, 1], [2, 0x1270, 1], [6, 0x127C, 3], [2, 0x129C, 3]]],
	7: [0x48, [[3, S.g_game_level, 1], [3, 0x126C, 1], [3, 0x1270, 1], [6, 0x127C, 5], [2, 0x129C, 6]]],
	8: [0xB4, [[3, S.g_game_level, 1], [4, 0x1270, 1], [6, 0x127C, 16], [4, 0x129C, 15]]],
	9: [0x108, [[3, S.g_game_level, 1], [1, 0x126C, 1], [3, 0x126E, 1], [6, 0x1270, 1], [6, 0x127C, 3],
		[6, 0x129C, 36]]],
	0xA: [0x2A, [[3, S.g_game_level, 1], [6, 0x127C, 3]]],
	0xC: [0x78, [[3, S.g_game_level, 1], ["bytes", 0x129C, 12]]],
}


## password_write_bits: the low n bits of v at g_password_bit, most
## significant first.
static func write_bits(n: int, v: int) -> void:
	for i in range(n - 1, -1, -1):
		var bit := ISSRam.w(S.g_password_bit)
		var a := S.g_password + (bit >> 3)
		var shift := 7 - (bit & 7)
		var byte := ISSRam.b(a) & ~(1 << shift)
		ISSRam.set_b(a, byte | (((v >> i) & 1) << shift))
		ISSRam.set_w(S.g_password_bit, bit + 1)


## password_read_bits: n bits at g_password_bit, most significant first.
static func read_bits(n: int) -> int:
	var v := 0
	for i in n:
		var bit := ISSRam.w(S.g_password_bit)
		v = (v << 1) | ((ISSRam.b(S.g_password + (bit >> 3)) >> (7 - (bit & 7))) & 1)
		ISSRam.set_w(S.g_password_bit, bit + 1)
	return v


## The checksum: $F5 plus the bytes from the key on (length / 8 - 1 of
## them); with a part byte at the end the routine adds its shift count, not
## the byte.
static func _sum() -> int:
	var s := 0xF5
	var n := ISSRam.w(S.g_password_length)
	for i in (n >> 3) - 1:
		s += ISSRam.b(S.g_password + 1 + i)
	if n & 7 != 0:
		s += 8 - (n & 7)
	return s & 0xFF


## password_seal: a random key at $1389 XORed into the 46 bytes after it,
## then the checksum at $1388.
static func seal() -> void:
	var key := ISSModes._rand() & 0xFF
	ISSRam.set_b(S.g_password + 1, key)
	for i in 46:
		ISSRam.set_b(S.g_password + 2 + i, ISSRam.b(S.g_password + 2 + i) ^ key)
	ISSRam.set_b(S.g_password, _sum())


## password_check: false when the checksum is wrong; else the key taken
## out again.
static func check() -> bool:
	if ISSRam.b(S.g_password) != _sum():
		return false
	var key := ISSRam.b(S.g_password + 1)
	for i in 46:
		ISSRam.set_b(S.g_password + 2 + i, ISSRam.b(S.g_password + 2 + i) ^ key)
	return true


## password_encode_*: the game mode's state as its password (unsealed).
static func encode(mode: int) -> void:
	if not FIELDS.has(mode):
		return
	var f: Array = FIELDS[mode]
	ISSRam.set_w(S.g_password_length, int(f[0]))
	ISSRam.set_w(S.g_password_bit, 0x10)
	for field: Array in f[1]:
		if field[0] is String:
			for i in int(field[2]):
				write_bits(1, ISSRam.b(int(field[1]) + 2 * i))
				write_bits(7, ISSRam.b(int(field[1]) + 2 * i + 1))
			continue
		for i in int(field[2]):
			write_bits(int(field[0]), ISSRam.w(int(field[1]) + 2 * i))


static func _read_fields(mode: int) -> void:
	ISSRam.set_w(S.g_password_bit, 0x10)
	for field: Array in FIELDS[mode][1]:
		if field[0] is String:
			for i in int(field[2]):
				ISSRam.set_b(int(field[1]) + 2 * i, read_bits(1))
				ISSRam.set_b(int(field[1]) + 2 * i + 1, read_bits(7))
			continue
		for i in int(field[2]):
			ISSRam.set_w(int(field[1]) + 2 * i, read_bits(int(field[0])))


## The game mode a password of n bits restores (-1 none).
static func mode_of_length(n: int) -> int:
	for mode: int in FIELDS:
		if int(FIELDS[mode][0]) == n:
			return mode
	return -1


static func _w(a: int, v: int) -> void:
	ISSRam.set_w(a, v)


## mode_resume_*: the competition as the password left it ($127A set: the
## next table skips the password), and the screen it goes on from.
static func resume(mode: int) -> int:
	# The settings every competition starts with.
	_w(S.g_game_mode, mode)
	_w(0x1276, 1)
	_w(0x1268, 1)
	_w(0x1272, 0xFFFF)
	if mode != 0xC:
		_w(0x126A, 0)
		_w(0x127A, 1)
	var status := 0x28
	var next := 0x3A
	match mode:
		4:
			_w(S.g_knockout, 0)
			_w(0x1264, 6)
			status = 0x78
			next = 0x1D
		5:
			_w(S.g_knockout, 1)
			_w(0x1264, 8)
			status = 0xA0
			next = 0x22
		6:
			_w(S.g_knockout, 0)
			_w(0x1264, 1)
			_w(0x1266, 1)
			status = 0x3C
			next = 0x29
		7:
			_w(S.g_knockout, 0)
			_w(0x1264, 1)
			_w(0x1266, 1)
			status = 0x50
			next = 0x2B
		8:
			_w(S.g_knockout, 1)
			_w(0x1266, 1)
			next = 0x2D
		9:
			_w(S.g_knockout, 1)
			_w(0x1264, 1)
			next = 0x2F
		0xA:
			_w(S.g_knockout, 1)
			_w(0x1264, 1)
			next = 6
		0xC:
			_w(S.g_knockout, 0)
			_w(0x1264, 1)
			_w(0x1266, 1)
			next = 0x24
	ISSRam.clear(S.g_player_status, status)
	if mode in [6, 7, 9, 0xA]:
		_w(0x153E, 1)
		_w(S.g_pads_home, 1)
		_w(S.g_pads_away, 0)
	_read_fields(mode)
	if mode == 6:
		_w(0x126C, ISSRam.w(0x127C) / 3)
	return next
