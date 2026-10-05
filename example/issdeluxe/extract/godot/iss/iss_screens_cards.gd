class_name ISSScreensCards
extends ISSScreens
## The competitions' title cards (screens $34-$38): the short league, the
## short tournament, the International Cup, the World Series (season 1, or
## with $126C its second season's label) and the Championship. Each plays
## its song and cycles colours 1-11 of palette lines 0 and 1 every eight
## frames; C goes on to the competition, B back to the main menu.

func register(h: Dictionary) -> void:
	h[0x34] = screen_card_short_league
	h[0x35] = screen_card_short_tournament
	h[0x36] = screen_card_international
	h[0x37] = screen_card_world_series
	h[0x38] = screen_card_championship


## Every eight frames colours 1-11 of lines 0 and 1 ($758 / $778) turn
## round by one; the palette goes to CRAM unless a fade is running.
func _cycle() -> void:
	if w(S.g_frame_counter) & 7 != 0:
		return
	for base in [0x758, 0x778]:
		var first := w(base)
		for i in 11:
			set_w(base + 2 * i, w(base + 2 * i + 2))
		set_w(base + 22, first)
	if w(S.g_fade_step) == 0x18:
		m.cram_dma(0, S.g_palette_target, 0x40)


## C to screen next, B (when back >= 0) to screen back.
func _card(next: int, back: int) -> void:
	if back >= 0 and pressed(PAD_B):
		goto_screen(back)
	if pressed(PAD_C):
		goto_screen(next)
	_cycle()


func screen_card_short_league() -> void:
	m.menu_music(0x0D)
	spawn(screen_card_short_league_1)


func screen_card_short_league_1(o: ISSMenu.Obj) -> void:
	o.update = screen_card_short_league_2
	o.set_w(T, 0)
	screen_card_short_league_2(o)


func screen_card_short_league_2(_o: ISSMenu.Obj) -> void:
	_card(0x1B, 0)


func screen_card_short_tournament() -> void:
	m.menu_music(0x0D)
	spawn(screen_card_short_tournament_1)


func screen_card_short_tournament_1(o: ISSMenu.Obj) -> void:
	o.update = screen_card_short_tournament_2
	o.set_w(T, 0)
	screen_card_short_tournament_2(o)


func screen_card_short_tournament_2(_o: ISSMenu.Obj) -> void:
	_card(0x20, 0)


func screen_card_international() -> void:
	m.menu_music(0x0C)
	spawn(screen_card_international_1)


func screen_card_international_1(o: ISSMenu.Obj) -> void:
	o.update = screen_card_international_2
	o.set_w(T, 0)
	screen_card_international_2(o)


func screen_card_international_2(_o: ISSMenu.Obj) -> void:
	_card(3, 0)


## The World Series: in its second season ($126C) the label's 6 x 8 cells
## at $740 of the nametable go over the first season's at $70C.
func screen_card_world_series() -> void:
	m.menu_music(9)
	if w(0x126C) != 0:
		var tn := l(S.g_text_nametable) & 0xFFFF
		for r in 8:
			ISSRam.copy(tn + 0x70C + r * 0x80, tn + 0x740 + r * 0x80, 12)
	spawn(screen_card_world_series_1)


func screen_card_world_series_1(o: ISSMenu.Obj) -> void:
	o.update = screen_card_world_series_2
	o.set_w(T, 0)
	screen_card_world_series_2(o)


## Season 1: C to the teams, B back; the second season goes straight to
## today's game ($2F) and has no way back.
func screen_card_world_series_2(_o: ISSMenu.Obj) -> void:
	if w(0x126C) == 0:
		_card(3, 0)
	else:
		_card(0x2F, -1)


func screen_card_championship() -> void:
	m.menu_music(4)
	spawn(screen_card_championship_1)


func screen_card_championship_1(o: ISSMenu.Obj) -> void:
	o.update = screen_card_championship_2
	o.set_w(T, 0)
	screen_card_championship_2(o)


func screen_card_championship_2(_o: ISSMenu.Obj) -> void:
	_card(0x3B, -1)
