class_name ISSPlayerLook
extends RefCounted
## A player's own frames, put together as player_draw does: the frame's
## body tiles (res00) in tiles 0-19 of his VRAM slot, then tile 20 = his
## head (the team's head tiles, res06 entry 5 ANDed with the team's head
## mask, (number - 1) * $80 in for the head offsets up to $40, a common
## tile at +$9A0 above that, the turned head $60 for $20 facing left) or
## the team's kit tile (res06 entry 3 / 4, 7 tiles a team), tile 21 = his
## hair style (res06 entry 9, $260 bytes a style); the frame's sprite
## pieces are drawn from that slot, the first on top. The result is a
## CRAM-index image (line * 16 + colour) like the exported frames, cached
## per frame, facing and look.

const ANIMS := "res://assets/iss/players/animations.json"
const KITS := "res://assets/iss/players/kits.json"

static var _anims: Dictionary = {}
static var _kits: Array = []
static var _cache := {}
static var _heads := {}
static var _body := {}


static func _ensure() -> void:
	if _anims.is_empty():
		ISSRom.ensure_loaded()
		_anims = JSON.parse_string(FileAccess.get_file_as_string(ANIMS))
		_kits = JSON.parse_string(FileAccess.get_file_as_string(KITS))["teams"]


## The team's head tiles with its mask (home mask with the first kit, away
## mask with the second).
static func heads(team: int, second: bool) -> PackedByteArray:
	var key := team * 2 + (1 if second else 0)
	if _heads.has(key):
		return _heads[key]
	var h := ISSRom.res(6, 5).duplicate()
	var mask := int(_kits[team]["head_mask_away" if second else "head_mask_home"])
	for i in range(0, h.size() - 1, 2):
		var v := ((h[i] << 8) | h[i + 1]) & mask
		h[i] = v >> 8
		h[i + 1] = v & 0xFF
	_heads[key] = h
	return h


static func _body_tiles(e: int) -> PackedByteArray:
	if not _body.has(e):
		_body[e] = ISSRom.res(0, e)
	return _body[e]


## The texture of frame addr ("$xxxxxx") facing left or right for a player
## of team (kit 0 first, 1 second: its tiles and head mask), shirt number
## (1-20) and hair style; [texture, origin].
static func frame(addr: String, left: bool, team: int, second: bool, number: int, hair: int) -> Array:
	_ensure()
	var key := "%s%d_%d_%d_%d_%d" % [addr, 1 if left else 0, team, 1 if second else 0, number, hair]
	if _cache.has(key):
		return _cache[key]
	var f: Dictionary = _anims["frames"][addr]
	var r: Dictionary = f["left" if left else "right"]
	var slot := PackedByteArray()
	slot.resize(32 * 32)
	var body := _body_tiles(int(f["body_entry"]))
	var bo := int(f["body_offset"])
	for i in mini(int(f["body_tiles"]) * 32, body.size() - bo):
		slot[i] = body[bo + i]
	var ho := int(f["head_offset"])
	if ho >= 0:
		var off := ho
		if off > 0x40:
			off += 0x9A0
		else:
			if off == 0x20 and left:
				off = 0x60
			off += (clampi(number, 1, 20) - 1) * 0x80
		var hd := heads(team, second)
		for i in 32:
			if off + i < hd.size():
				slot[20 * 32 + i] = hd[off + i]
	var ko := int(f["kit_offset"])
	if ko >= 0:
		var kt := ISSRom.res(6, 4 if second else 3)
		var base := team * 0xE0 + ko
		for i in 32:
			if base + i < kt.size():
				slot[20 * 32 + i] = kt[base + i]
	var hr := int(f["hair_offset"])
	if hr >= 0:
		var hs := ISSRom.res(6, 9)
		var base := hair * 0x260 + hr
		for i in 32:
			if base + i < hs.size():
				slot[21 * 32 + i] = hs[base + i]
	var pieces: Array = r["pieces"]
	var ox := int(r["origin_x"])
	var oy := int(r["origin_y"])
	var img_w := 1
	var img_h := 1
	for p: Dictionary in pieces:
		img_w = maxi(img_w, int(p["x"]) + ox + int(p["w"]) * 8)
		img_h = maxi(img_h, int(p["y"]) + oy + int(p["h"]) * 8)
	var px := PackedByteArray()
	px.resize(img_w * img_h)
	for pi in range(pieces.size() - 1, -1, -1):
		var p: Dictionary = pieces[pi]
		var pw := int(p["w"])
		var ph := int(p["h"])
		var hf: bool = p["hflip"]
		var vf: bool = p["vflip"]
		var line := int(p["line"]) * 16
		var x0 := int(p["x"]) + ox
		var y0 := int(p["y"]) + oy
		for cx in pw:
			for cy in ph:
				var t := int(p["tile"]) + cx * ph + cy
				if t < 0 or t >= 32:
					continue
				var tx := pw - 1 - cx if hf else cx
				var ty := ph - 1 - cy if vf else cy
				for y in 8:
					for x in 8:
						var b := slot[t * 32 + y * 4 + (x >> 1)]
						var v := (b & 15) if x & 1 else (b >> 4)
						if v == 0:
							continue
						var dx := tx * 8 + (7 - x if hf else x) + x0
						var dy := ty * 8 + (7 - y if vf else y) + y0
						if dx >= 0 and dy >= 0 and dx < img_w and dy < img_h:
							px[dy * img_w + dx] = line + v
	var img := Image.create_from_data(img_w, img_h, false, Image.FORMAT_L8, px)
	var out := [ImageTexture.create_from_image(img), Vector2(-ox, -oy)]
	_cache[key] = out
	return out
