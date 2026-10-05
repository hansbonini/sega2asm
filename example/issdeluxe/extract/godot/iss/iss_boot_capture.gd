extends SceneTree
## Run the boot screens (main_init) and save a screenshot every STEP frames
## from frame START, to compare with the ROM's own (tools/boot_capture.py):
##   godot --path out/godot -s res://iss/iss_boot_capture.gd -- <step> <count> <prefix> [start]
## In the environment: SCREENS=4,3 runs those boot screens only (4 SEGA, 3
## Konami, 2 Factor 5, 0 intro, 1 title); TITLE_SPLIT=1000 shows the title's
## first palette on every line (0 the second), as the harness renders a
## frame; PRESS=frame:pad:button:frames presses a button; TRACE=a:b prints
## the module's counters for frames a..b; VRAM_AT=n dumps VRAM and RAM at
## frame n.
var menu: ISSMenu
var n := 0
var step := 10
var count := 10
var prefix := ""
var start := 0
var presses := []

func _initialize() -> void:
	Engine.max_physics_steps_per_frame = 1
	var args := OS.get_cmdline_user_args()
	step = int(args[0])
	count = int(args[1])
	prefix = args[2]
	start = int(args[3]) if args.size() > 3 else 0
	ISSMenu.power_on()
	for e in OS.get_environment("SCREENS").split(",", false):
		ISSBoot.screens_override.append(int(e))
	if OS.get_environment("TITLE_SPLIT") != "":
		ISSBoot.title_split = int(OS.get_environment("TITLE_SPLIT"))
	menu = ISSMenu.new()
	root.add_child(menu)
	menu.enter(ISSMenu.STATE_INIT)
	for e in OS.get_environment("PRESS").split(",", false):
		var f := e.split(":")
		presses.append([int(f[0]), int(f[1]), f[2], int(f[3])])
	menu.next_state.connect(func(s: int) -> void: print("next_state %X at %d" % [s, n]))

func _physics_process(_d: float) -> bool:
	n += 1
	for e in presses:
		if n == e[0]:
			Input.action_press(ISSInput.action(e[1], e[2]))
		elif n == e[0] + e[3]:
			Input.action_release(ISSInput.action(e[1], e[2]))
	var tr := OS.get_environment("TRACE")
	if tr != "":
		var t := tr.split(":")
		if n >= int(t[0]) and n <= int(t[1]):
			print("%d scr %d frame %d wait %d amp %X ph %X f30 %X f34 %X pressed %X" % [n, ISSRam.w(0x1C), ISSRam.w(0x16),
				ISSRam.w(0x18), ISSRam.w(0x1002), ISSRam.w(0x1004), ISSRam.b(0xF30), ISSRam.b(0xF34), ISSRam.b(0xF32)])
	if OS.get_environment("VRAM_AT") != "" and n == int(OS.get_environment("VRAM_AT")):
		var f := FileAccess.open(prefix + ".vram", FileAccess.WRITE)
		f.store_buffer(menu.vdp.vram)
		f.close()
		var g := FileAccess.open(prefix + ".pram", FileAccess.WRITE)
		g.store_buffer(ISSRam.m)
		g.close()
	if n >= start and (n - start) % step == 0:
		_shot((n - start) / step)
	return false


func _shot(i: int) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().get_region(Rect2i(0, 0, 256, 224)).save_png("%s_%03d.png" % [prefix, i])
	if i + 1 >= count:
		print("end n=%d state=%X" % [n, ISSRam.l(0x18)])
		quit()
