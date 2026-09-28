extends SceneTree
## 端到端验收：用求解器给出的标准解法，在真实游戏里把 6 关逐一打完，确认每关都能过。
##
##   godot --path . --script res://tools/verify.gd

const SOLUTIONS := [
	Vector2(3.0, -5.0),
	Vector2(8.0, 12.0),
	Vector2(2.0, 12.0),
	Vector2(-3.0, 12.0),
	Vector2(10.0, 17.0),
	Vector2(-25.0, 16.0),
]

var main: Node


func _initialize() -> void:
	_run()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	await _sleep(0.6)
	main._primary()
	await _sleep(0.3)

	var passed := 0
	for i in SOLUTIONS.size():
		if i > 0:
			main._load_level(i)
			await _sleep(0.35)
		main.aim_yaw = SOLUTIONS[i].x
		main.aim_pitch = SOLUTIONS[i].y
		main._refresh_aim()
		main._fire()
		var waited := 0.0
		while main.state == 2 and waited < 20.0:
			await _sleep(0.1)
			waited += 0.1
		await _sleep(0.3)
		var total: int = main.level["targets"].size()
		var got: int = main.destroyed_count
		var good := got == total
		if good:
			passed += 1
		print("关卡 %d %s : 击碎 %d/%d  反弹 %d  状态 %s  %s" % [
			i + 1, main.level["name"], got, total, main.bounce_count,
			["TITLE", "AIM", "FLY", "CLEAR", "FAIL", "FINISH"][main.state],
			"✅" if good else "❌"])
	print("通过 %d / %d" % [passed, SOLUTIONS.size()])
	quit(0 if passed == SOLUTIONS.size() else 1)


func _sleep(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await process_frame
