extends SceneTree
## 开发用截图工具：跑起主场景，摆好姿势后把画面存成 PNG，方便检查渲染效果。
##
## 用法（不要加 --headless，headless 不渲染）：
##   godot --path . --script res://tools/shot.gd -- <关卡号> <输出前缀> [yaw] [pitch]
## 例如：
##   godot --path . --script res://tools/shot.gd -- 0 C:/tmp/s 3 -5

var main: Node


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var level := int(args[0]) if args.size() > 0 else 0
	var prefix := String(args[1]) if args.size() > 1 else "user://shot"
	var has_aim := args.size() > 3
	var yaw := float(args[2]) if has_aim else 0.0
	var pitch := float(args[3]) if has_aim else 0.0

	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)   # 免得鼠标抖动改掉预设角度
	await _sleep(0.5)
	await _shot(prefix + "_%d_00_title.png" % level)
	main._primary()                       # 从标题进入关卡
	await _sleep(0.2)
	if level > 0:
		main._load_level(level)
	await _sleep(0.4)
	if has_aim:
		main.aim_yaw = yaw
		main.aim_pitch = pitch
		main._refresh_aim()
	await _shot(prefix + "_%d_01_aim.png" % level)
	if has_aim:
		main.aim_yaw = yaw
		main.aim_pitch = pitch
		main._refresh_aim()
	main._fire()
	await _sleep(0.45)
	await _shot(prefix + "_%d_02_fly.png" % level)
	await _sleep(0.7)
	await _shot(prefix + "_%d_03_fly2.png" % level)
	# 一直等到子弹停下来
	var waited := 0.0
	while main.state == 2 and waited < 20.0:
		await _sleep(0.2)
		waited += 0.2
	await _sleep(0.6)
	await _shot(prefix + "_%d_04_end.png" % level)
	print("done state=", main.state, " destroyed=", main.destroyed_count, "/", main.level["targets"].size(),
			" bounces=", main.bounce_count, " waited=", waited)
	print("  aim=(%.3f, %.3f) dir=%s" % [main.aim_yaw, main.aim_pitch, str(main.aim_dir)])
	print("  sim: end=", main.flight.get("end"), " destroyed=", main.flight.get("destroyed"),
			" bounces=", main.flight.get("bounces"), " segs=", main.flight.get("seg_len"))
	quit()


func _sleep(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var err := img.save_png(path)
	print("shot ", path, " err=", err)
