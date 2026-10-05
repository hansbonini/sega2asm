class_name ISSHud
extends Node2D
## The ISS Deluxe match HUD (window plane) rebuilt from assets/iss/hud:
## team flags and names, score, clock and the radar. Put it on a CanvasLayer;
## it draws in window-plane pixels (256 x 256, the HUD rows of a 256 x 224
## screen are rows 0-3 and 20-26). The middle of the screen opens as a
## window band centred on line 95 (hblank_hud_split, $964) for the banners,
## the pause menu (ISSMatch drives `pause`) and, in a replay, the top rows
## show the REPLAY logo and the controls' icons (`replay`).

const DIR := "res://assets/iss/hud/"

@export var home_team: int = 0
@export var away_team: int = 1
@export var home_score: int = 0
@export var away_score: int = 0
## Clock in seconds (the game counts down).
@export var clock_seconds: float = 300.0
@export var second_half := false
@export_range(0, 7) var stadium: int = 0
## tm_strategy of each side (-1 = none): its label shows in window row 22.
var home_strategy := -1:
	set(v):
		home_strategy = v
		_show_strategy("home_strategy", v)
var away_strategy := -1:
	set(v):
		away_strategy = v
		_show_strategy("away_strategy", v)

## $182A / $18B2: the side asked for the match menu (hud_draw_clock_1 shows
## overlay tiles $90-$91 under its score).
var menu_request := [false, false]

## The pause menu (matchflow_func_018BD8 / _018A7A): {"kind": "three_button"
## or "six_button", "cursor": item, "band": the band's half-height in lines
## ($964)}; empty = none. Its box and texts come from hud.json's "pause".
var pause := {}
## The replay's HUD (state_match_8): {"manual": a button has been pressed,
## "back": playing backwards, "slow": slow motion, "blink": frame counter};
## empty = no replay. set_replay() also hides the score rows, as
## match_init_hud clears them.
var replay := {}

## The window band's centre line and the lines the banner band opens to
## ($964 grows a line a frame to $14 while a banner is up).
const BAND_CENTRE := 95
const BANNER_BAND := 20
## The 2-row font of the overlay tiles: a capital's top tile is $74 + its
## letter, a small letter's $94 +, a digit's $62 +, '.' $61, blank $73; the
## bottom tiles are $50 further on. The cursor is $5E over $5F.
const FONT_UPPER := 0x74
const FONT_LOWER := 0x94
const FONT_DIGIT := 0x62
const FONT_DOT := 0x61
const FONT_BLANK := 0x73
const FONT_BOTTOM := 0x50
const CURSOR_TILE := 0x5E
const REQUEST_TILE := 0x90
const REPLAY_FIRST := 0x11B
const REPLAY_COUNT := 43

var _doc: Dictionary
var _mat := ShaderMaterial.new()
var _sheet: Texture2D
var _replay_sheet: Texture2D
var _window: Texture2D
var _digits: Texture2D
var _time_up: Texture2D
var _radar_dots: Array = [] # [pitch position, kind] set by set_radar()

## Radar dot colours: palette line 2 colours $D, $A, 9, 8, 1 and outline $F.
const DOT_COLOURS := {"home": 13, "away": 10, "controlled_home": 9, "controlled_away": 8, "ball": 1}

var _bounds := Rect2()
var _radar := RadarLayer.new()
var _banner := BannerLayer.new()
var _team_sprites := {} # "home_flag" etc. -> Sprite2D


## The radar dots are drawn unshaded, with colours from the HUD palette.
class RadarLayer:
	extends Node2D
	var hud: ISSHud
	var line2: Array[Color] = []

	func _draw() -> void:
		if line2.is_empty():
			return
		var origin := hud._cell("radar")
		var m: Dictionary = hud._doc["radar"]["mapping"][hud.stadium]
		var xs: Array = m["x"]
		var ys: Array = m["y"]
		for dot in hud._radar_dots:
			var p: Vector2 = dot[0]
			var ix := clampi(int((p.x - hud._bounds.position.x) / 16), 0, xs.size() - 1)
			var iy := clampi(int((p.y - hud._bounds.position.y) / 16), 0, ys.size() - 1)
			var at := origin + Vector2(int(xs[ix]), int(ys[iy]))
			var col: Color = line2[ISSHud.DOT_COLOURS[dot[1]]]
			if dot[1] != "home" and dot[1] != "away":
				draw_rect(Rect2(at - Vector2(1, 1), Vector2(4, 4)), line2[15])
			draw_rect(Rect2(at, Vector2(2, 2)), col)


## Banner text (banner_draw): 16x32 letters written at HUD map row 23 and
## uploaded to window rows 9-14, which the band in the middle of the screen
## shows as it opens a line a frame each way (restart_*: $964 to $14).
class BannerLayer:
	extends Node2D
	const ROW := 10
	var font: Texture2D
	var text := ""
	var column := 5
	## The band's half-height in lines; nothing shows at 0.
	var band := 0

	func _draw() -> void:
		var y0 := maxi(ROW * 8, ISSHud.BAND_CENTRE - band)
		var y1 := mini(ROW * 8 + 32, ISSHud.BAND_CENTRE + band)
		if y1 <= y0:
			return
		for i in text.length():
			var g := text.unicode_at(i) - 0x40 # '@' = space, then A-Z
			if text[i] == " ":
				g = 0
			if g < 0 or g > 26:
				continue
			draw_texture_rect_region(font, Rect2((column + 2 * i) * 8, y0, 16, y1 - y0),
				Rect2(g * 16, y0 - ROW * 8, 16, y1 - y0))


func _ready() -> void:
	_doc = JSON.parse_string(FileAccess.get_file_as_string(DIR + "hud.json"))
	_mat.shader = load("res://md/md_indexed.gdshader")
	_mat.set_shader_parameter("palette", load(DIR + "hud.pal.png"))
	material = _mat
	_window = load(DIR + "window.png")
	_digits = load(DIR + "digits.png")
	_time_up = load(DIR + "time_up.png")
	# The overlay tiles and the replay's, on palette line 2 (the sheets hold
	# bare colour indices).
	_sheet = _line2((load(DIR + "overlay_tiles.png") as Texture2D).get_image())
	if ResourceLoader.exists(DIR + "replay_tiles.png"):
		_replay_sheet = _line2((load(DIR + "replay_tiles.png") as Texture2D).get_image())
	var pal := (load(DIR + "hud.pal.png") as Texture2D).get_image()
	for i in 16:
		_radar.line2.append(pal.get_pixel(i, 2))
	_radar.hud = self
	for item in ["home_flag", "home_name", "away_flag", "away_name", "home_strategy", "away_strategy"]:
		var sp := Sprite2D.new()
		sp.centered = false
		sp.use_parent_material = true
		sp.position = _cell(item)
		add_child(sp)
		_team_sprites[item] = sp
	add_child(_radar)
	_banner.font = load(DIR + "banner_font.png")
	_banner.use_parent_material = true
	_banner.visible = false
	add_child(_banner)
	set_teams(home_team, away_team)
	set_stadium(stadium)
	_show_strategy("home_strategy", home_strategy)
	_show_strategy("away_strategy", away_strategy)


## An index sheet moved to palette line 2 (colour 0 stays transparent).
static func _line2(img: Image) -> ImageTexture:
	var out := img.duplicate() as Image
	out.convert(Image.FORMAT_L8)
	for y in out.get_height():
		for x in out.get_width():
			var v := out.get_pixel(x, y).r8 & 15
			if v != 0:
				out.set_pixel(x, y, Color8(v + 0x20, v + 0x20, v + 0x20))
	return ImageTexture.create_from_image(out)


func set_teams(home: int, away: int) -> void:
	home_team = home
	away_team = away
	for side in [["home", home], ["away", away]]:
		var team: int = side[1]
		var ok := team >= 0 and team < 42
		var flag: Sprite2D = _team_sprites[side[0] + "_flag"]
		var name_plate: Sprite2D = _team_sprites[side[0] + "_name"]
		flag.texture = load(DIR + "flags/flag_%02d.png" % team) if ok else null
		name_plate.texture = load(DIR + "names/name_%02d.png" % team) if ok else null


func _show_strategy(item: String, strategy: int) -> void:
	if not _team_sprites.has(item):
		return
	var sp: Sprite2D = _team_sprites[item]
	sp.texture = load(DIR + "strategies/strategy_%d.png" % strategy) if strategy >= 0 else null


func set_stadium(index: int) -> void:
	stadium = index
	var doc = JSON.parse_string(FileAccess.get_file_as_string("res://assets/iss/stadiums/stadiums.json"))
	var b: Dictionary = doc["stadiums"][stadium]["pitch_bounds"]
	_bounds = Rect2(b["left"], b["top"], b["right"] - b["left"], b["bottom"] - b["top"])


func _process(_delta: float) -> void:
	queue_redraw()
	_radar.queue_redraw()
	_banner.queue_redraw()


## The banner's band opens a line a frame each way while a banner is up and
## closes the same way after it.
func _physics_process(_delta: float) -> void:
	band_step()


func band_step() -> void:
	if _banner.visible:
		_banner.band = mini(BANNER_BAND, _banner.band + 1)
	else:
		_banner.band = maxi(0, _banner.band - 1)


## Shows a banner: message is a key of hud.json banner_messages ("throw_in",
## "goal_kick", "half_time", ...) or any text in capitals.
func show_banner(message: String) -> void:
	var m: Dictionary = _doc["banner_messages"].get(message, {"text": message, "column": 5})
	_banner.text = m["text"]
	_banner.column = int(m["column"])
	_banner.visible = true
	_banner.queue_redraw()


func hide_banner() -> void:
	_banner.visible = false


## The replay's HUD state (see `replay`); empty ends it.
func set_replay(state: Dictionary) -> void:
	replay = state
	for item in ["home_flag", "home_name", "away_flag", "away_name"]:
		_team_sprites[item].visible = state.is_empty()


## The pause menu's layout (hud.json "pause"): items, box and band.
func pause_layout(kind: String) -> Dictionary:
	return _doc.get("pause", {}).get(kind, {})


## Radar contents: an array of [Vector2 pitch position, kind], kind one of
## "home", "away", "controlled_home", "controlled_away", "ball".
func set_radar(dots: Array) -> void:
	_radar_dots = dots


func _cell(item: String) -> Vector2:
	var c: Array = _doc["items"][item]["cells"]
	return Vector2(int(c[0]) * 8, int(c[1]) * 8)


func _digit(d: int, at: Vector2) -> void:
	draw_texture_rect_region(_digits, Rect2(at, Vector2(8, 16)), Rect2(d * 8, 0, 8, 16))


func _number(n: int, at: Vector2, blank_tens: bool) -> void:
	if n >= 10 or not blank_tens:
		_digit((n / 10) % 10, at)
	_digit(n % 10, at + Vector2(8, 0))


## Overlay tile t (the replay's tiles while a replay runs) at window cell
## (col, row), only its lines inside [top, bottom), flipped if asked.
func _cell_tile(t: int, col: int, row: int, top := 0, bottom := 256, flip := false) -> void:
	var y := row * 8
	var y0 := maxi(y, top)
	var y1 := mini(y + 8, bottom)
	if y1 <= y0:
		return
	var tex := _sheet
	var i := t
	if not replay.is_empty() and _replay_sheet != null and t >= REPLAY_FIRST and t < REPLAY_FIRST + REPLAY_COUNT:
		tex = _replay_sheet
		i = t - REPLAY_FIRST
	var src := Rect2((i % 16) * 8, (i / 16) * 8 + (y0 - y), 8, y1 - y0)
	var dst := Rect2(col * 8, y0, 8, y1 - y0)
	if flip:
		dst = Rect2(col * 8 + 8, y0, -8, y1 - y0)
	draw_texture_rect_region(tex, dst, src)


## Text in the 2-row font with its top row at window row `row`.
func _text2(s: String, col: int, row: int, top: int, bottom: int) -> void:
	for i in s.length():
		var c := s.unicode_at(i)
		var t := FONT_BLANK
		if c >= 65 and c <= 90:
			t = FONT_UPPER + c - 65
		elif c >= 97 and c <= 122:
			t = FONT_LOWER + c - 97
		elif c >= 48 and c <= 57:
			t = FONT_DIGIT + c - 48
		elif c == 46:
			t = FONT_DOT
		_cell_tile(t, col + i, row, top, bottom)
		_cell_tile(t + FONT_BOTTOM, col + i, row + 1, top, bottom)


## The cells of a hud.json "replay" table: [HUD map offset, word] pairs,
## the map's row 0 being window row 1.
func _cells(key: String) -> void:
	for pair in _doc["replay"][key]:
		var off := int(pair[0])
		var w := int(pair[1])
		_cell_tile(w & 0x7FF, (off % 64) / 2, off / 64 + 1, 0, 256, w & 0x800 != 0)


func _draw() -> void:
	# The window plane only shows the score rows and the radar (the banner
	# strip below the radar is visible while a banner is up).
	if replay.is_empty():
		draw_texture_rect_region(_window, Rect2(0, 0, 256, 32), Rect2(0, 0, 256, 32))
		_number(home_score, _cell("home_score"), true)
		_number(away_score, _cell("away_score"), true)
		for side in 2:
			if menu_request[side]:
				var c: Array = _doc["items"]["home_score" if side == 0 else "away_score"]["cells"]
				_cell_tile(REQUEST_TILE, int(c[0]), int(c[1]) + 2)
				_cell_tile(REQUEST_TILE + 1, int(c[0]) + 1, int(c[1]) + 2)
		# The half's number (hud_draw_clock: $6C, then $64) before the clock.
		var half_tile := 0x64 if second_half else 0x6C
		var hc: Array = _doc["items"]["half"]["cells"]
		_cell_tile(half_tile, int(hc[0]), int(hc[1]))
		_cell_tile(half_tile + FONT_BOTTOM, int(hc[0]), int(hc[1]) + 1)
		var clock := _cell("clock")
		if clock_seconds <= 0.0:
			draw_texture(_time_up, clock)
		else:
			var s := int(ceil(clock_seconds))
			_digit(s / 60 % 10, clock)
			_number(s % 60, clock + Vector2(16, 0), false)
	else:
		# match_init_hud clears map rows 0-2 for a replay; row 0 stays.
		draw_texture_rect_region(_window, Rect2(0, 0, 256, 8), Rect2(0, 0, 256, 8))
		if replay.get("manual", false) and _doc.has("replay"):
			# state_match_8: the logo blinks 16 frames on, 16 off; A and C lit
			# for the direction played, B while slow, and the START legend.
			if int(replay.get("blink", 0)) & 16 == 0:
				_cells("logo")
			var back: bool = replay.get("back", false)
			_cells("a_lit" if back else "a_dim")
			_cells("b_lit" if replay.get("slow", false) else "b_dim")
			_cells("c_dim" if back else "c_lit")
			_cells("start")
	var r := Rect2(_cell("radar"), Vector2(80, 56))
	draw_texture_rect_region(_window, r, r)
	if _banner.band > 0:
		# The banner's rows are blank tiles right across; the letters come
		# over them (BannerLayer).
		for row in range(BannerLayer.ROW - 1, BannerLayer.ROW + 5):
			for col in 32:
				_cell_tile(FONT_BLANK, col, row, BAND_CENTRE - _banner.band, BAND_CENTRE + _banner.band)
	_draw_pause()


## The pause menu: a box of blank tiles with the items in the 2-row font,
## the cursor on the chosen one, through the band opening from the centre.
func _draw_pause() -> void:
	if pause.is_empty() or int(pause.get("band", 0)) <= 0:
		return
	var p := pause_layout(str(pause["kind"]))
	if p.is_empty():
		return
	var band := int(pause["band"])
	var top := BAND_CENTRE - band
	var bottom := BAND_CENTRE + band
	var rows: Array = p["box_rows"]
	var cols: Array = p["box_cols"]
	var shift := int(p["window_row"]) - int(rows[0])
	for row in range(int(rows[0]), int(rows[1]) + 1):
		for col in range(int(cols[0]), int(cols[1]) + 1):
			_cell_tile(FONT_BLANK, col, row + shift, top, bottom)
	var items: Array = p["items"]
	for i in items.size():
		var row := int(p["first_item_row"]) + 2 * i + shift
		_text2(str(items[i]), int(p["text_col"]), row, top, bottom)
		if i == int(pause.get("cursor", 0)):
			_cell_tile(CURSOR_TILE, int(p["cursor_col"]), row, top, bottom)
			_cell_tile(CURSOR_TILE + 1, int(p["cursor_col"]), row + 1, top, bottom)
