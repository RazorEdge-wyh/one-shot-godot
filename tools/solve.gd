extends SceneTree
## 关卡工具（headless）：
##   扫面可解性 / 找出解法 / 打印弹道用于摆目标
##
## 用法：
##   godot --headless --path . --script res://tools/solve.gd -- scan
##   godot --headless --path . --script res://tools/solve.gd -- scan 3
##   godot --headless --path . --script res://tools/solve.gd -- path 0 12.5 20
##   godot --headless --path . --script res://tools/solve.gd -- auto 0 12.5 20 0,2,4

const B := preload("res://scripts/ballistics.gd")
const L := preload("res://scripts/levels.gd")

var args: PackedStringArray = []


func _initialize() -> void:
	args = OS.get_cmdline_user_args()
	if args.is_empty():
		args = PackedStringArray(["scan"])
	match args[0]:
		"scan":
			var only := int(args[1]) if args.size() > 1 else -1
			_scan(only)
		"path":
			_path(int(args[1]), float(args[2]), float(args[3]))
		"auto":
			_auto(int(args[1]), float(args[2]), float(args[3]), args[4] if args.size() > 4 else "")
		"cand":
			_cand(int(args[1]) if args.size() > 1 else -1)
		"fine":
			_fine(int(args[1]), float(args[2]), float(args[3]))
		"autogen":
			_autogen(int(args[1]), float(args[2]), float(args[3]), int(args[4]) if args.size() > 4 else 4,
					int(args[5]) if args.size() > 5 else 99)
		_:
			print("unknown mode")
	quit()


## 扫描所有发射角度，挑出几何形状漂亮的弹道（用于"先有弹道、再摆目标"的关卡设计法）
func _cand(only: int) -> void:
	var levels := L.all()
	for i in levels.size():
		if only >= 0 and i != only:
			continue
		var lv: Dictionary = levels[i]
		var arena := lv.duplicate(true)
		arena["targets"] = []          # 只看竞技场骨架：先有弹道，再摆目标
		var g := B.compile(arena)
		var origin: Vector3 = lv["cannon"]
		var by := float(lv.get("base_yaw", 0.0))
		var out: Array = []
		var hist := {}
		for yaw in range(int(by - 45.0), int(by + 45.0) + 1):
			for pitch in range(-10, 61):
				var res := B.simulate(g, origin, B.aim_dir(yaw, pitch), PackedByteArray(), true)
				var b: int = res["bounces"]
				hist[b] = int(hist.get(b, 0)) + 1
				var lens: PackedFloat32Array = res["seg_len"]
				var cols: PackedInt32Array = res["seg_color"]
				if lens.size() < 5:
					continue
				# 只看前几段：够长、够多，才方便在上面摆目标
				var ok := true
				for j in mini(5, lens.size()):
					if lens[j] < 1.7:
						ok = false
						break
				if not ok:
					continue
				var pp: PackedVector3Array = res["pts"]
				# 排除"对着两面平行墙来回弹"的退化弹道：相邻两段方向必须有明显夹角
				var varied := true
				var dirs: Array[Vector3] = []
				for j in mini(6, pp.size() - 1):
					dirs.append((pp[j + 1] - pp[j]).normalized())
				for j in range(1, dirs.size()):
					if absf(dirs[j].angle_to(dirs[j - 1])) < deg_to_rad(20.0):
						varied = false
						break
				if not varied:
					continue
				var score := 0.0
				for j in mini(6, lens.size()):
					score += minf(lens[j], 8.0)
				# 弹道在垂直方向也要有变化，否则全是贴地飞
				var ymin := 999.0
				var ymax := -999.0
				for j in mini(7, pp.size()):
					ymin = minf(ymin, pp[j].y)
					ymax = maxf(ymax, pp[j].y)
				score += (ymax - ymin) * 1.5
				out.append({"score": score, "yaw": yaw, "pitch": pitch, "res": res})
		out.sort_custom(func(a, b2): return a["score"] > b2["score"])
		print("\n=== [%d] %s  候选弹道 %d 条  (hist=%s) ===" % [i, lv["name"], out.size(), str(hist)])
		for k in mini(6, out.size()):
			var c: Dictionary = out[k]
			var res: Dictionary = c["res"]
			var pts: PackedVector3Array = res["pts"]
			var cols: PackedInt32Array = res["seg_color"]
			var s := ""
			for j in pts.size():
				s += "(%.1f,%.1f,%.1f)" % [pts[j].x, pts[j].y, pts[j].z]
				if j < cols.size():
					s += "%s" % B.COLOR_NAMES[cols[j]].substr(0, 1)
			print("  #%d aim=(%d,%d) b=%d 分数%.1f %s" % [k, c["yaw"], c["pitch"], res["bounces"], c["score"], s])


## 细扫：量一下解法的"宽容度"（玩家能偏多少度还能过关）
func _fine(idx: int, yaw: float, pitch: float) -> void:
	var lv: Dictionary = L.get_level(idx)
	var g := B.compile(lv)
	var origin: Vector3 = lv["cannon"]
	var nt := g.sph_c.size()
	var step := 0.1
	var ok := 0
	var total := 0
	var ymin := 999.0
	var ymax := -999.0
	var pmin := 999.0
	var pmax := -999.0
	var y := yaw - 4.0
	while y <= yaw + 4.0:
		var p := pitch - 4.0
		while p <= pitch + 4.0:
			total += 1
			var res := B.simulate(g, origin, B.aim_dir(y, p), PackedByteArray(), false)
			if res["destroyed"].size() == nt:
				ok += 1
				ymin = minf(ymin, y)
				ymax = maxf(ymax, y)
				pmin = minf(pmin, p)
				pmax = maxf(pmax, p)
			p += step
		y += step
	print("[%d] %s  0.1° 细扫: 可解 %d/%d  角度范围 yaw %.1f~%.1f (%.1f°)  pitch %.1f~%.1f (%.1f°)"
			% [idx, lv["name"], ok, total, ymin, ymax, ymax - ymin, pmin, pmax, pmax - pmin])


## 在指定弹道上自动摆目标：贪心尝试每一段，放上去后仍然一发清场就保留
func _autogen(idx: int, yaw: float, pitch: float, max_targets: int, max_seg := 99) -> void:
	var lv: Dictionary = L.get_level(idx)
	var g0 := B.compile(lv)
	var base := B.simulate(g0, lv["cannon"], B.aim_dir(yaw, pitch), PackedByteArray(), true)
	var pts: PackedVector3Array = base["pts"]
	var cols: PackedInt32Array = base["seg_color"]
	print("### level %d base path: bounces=%d" % [idx, base["bounces"]])
	var placed: Array = []
	var order: Array = []
	for si in range(1, mini(pts.size(), max_seg + 1)):
		order.append(si)
	order.reverse()   # 从最后一段往前放，避免目标互相遮挡
	for si in order:
		if placed.size() >= max_targets:
			break
		var p: Vector3 = pts[si - 1].lerp(pts[si], 0.5)
		var col: int = cols[si - 1]
		var cand: Array = placed.duplicate()
		cand.append({"p": p, "r": 0.7, "color": col, "seg": si})
		# 用新目标重算，确认同一发角度依然清场
		var test_lv := lv.duplicate(true)
		test_lv["targets"] = cand
		var g := B.compile(test_lv)
		var res := B.simulate(g, lv["cannon"], B.aim_dir(yaw, pitch), PackedByteArray(), false)
		if res["destroyed"].size() == cand.size():
			placed = cand
			print("   + 段%d 颜色%s -> (%.2f, %.2f, %.2f)  OK" % [si, B.COLOR_NAMES[col], p.x, p.y, p.z])
		else:
			print("   - 段%d 颜色%s -> (%.2f, %.2f, %.2f)  冲突" % [si, B.COLOR_NAMES[col], p.x, p.y, p.z])
	print("\n# ---- 关卡 %d 目标（解法 aim=(%.1f, %.1f)）----" % [idx, yaw, pitch])
	for t in placed:
		print("{\"p\": Vector3(%.2f, %.2f, %.2f), \"r\": 0.7, \"color\": %d}," % [t["p"].x, t["p"].y, t["p"].z, t["color"]])


func _scan(only: int) -> void:
	var levels := L.all()
	var total_ok := 0
	for i in levels.size():
		if only >= 0 and i != only:
			continue
		var lv: Dictionary = levels[i]
		var g := B.compile(lv)
		var origin: Vector3 = lv["cannon"]
		var base_yaw: float = lv.get("base_yaw", 0.0)
		var nt := g.sph_c.size()
		print("\n=== [%d] %s   目标 %d ===" % [i, lv["name"], nt])
		var t0 := Time.get_ticks_msec()
		var best := 0
		var best_aim := Vector2.ZERO
		var solutions: Array = []
		var yaw := base_yaw - 80.0
		while yaw <= base_yaw + 80.0:
			var pitch := -10.0
			while pitch <= 75.0:
				var d := B.aim_dir(yaw, pitch)
				var res := B.simulate(g, origin, d, PackedByteArray(), false)
				var n: int = res["destroyed"].size()
				if n > best:
					best = n
					best_aim = Vector2(yaw, pitch)
				if n == nt:
					solutions.append(Vector2(yaw, pitch))
				pitch += 1.0
			yaw += 1.0
		var ms := Time.get_ticks_msec() - t0
		print("  最佳命中 %d/%d  aim=(%.1f, %.1f)   1°网格可解点 %d   耗时 %dms" % [best, nt, best_aim.x, best_aim.y, solutions.size(), ms])
		if solutions.size() > 0:
			total_ok += 1
			# 报告解法的"宽容度"：连续可解点的跨度
			var span := _longest_run(solutions)
			print("  ✅ 可解。示例 aim=(%.1f, %.1f)，最大连续可解跨度 %.1f°" % [solutions[0].x, solutions[0].y, span])
		else:
			print("  ❌ 无解（1° 网格内）")
	print("\n可解关卡 %d / %d" % [total_ok, levels.size() if only < 0 else 1])


func _longest_run(solutions: Array) -> float:
	# 粗略统计：按 yaw 分组，求同 yaw 下 pitch 连续段的最大长度
	var by_yaw := {}
	for s in solutions:
		var k := int(round(s.x))
		if not by_yaw.has(k):
			by_yaw[k] = []
		by_yaw[k].append(s.y)
	var best := 0.0
	for k in by_yaw:
		var arr: Array = by_yaw[k]
		arr.sort()
		var run := 1.0
		for j in range(1, arr.size()):
			var prev: float = arr[j - 1]
			var cur: float = arr[j]
			if absf(cur - prev - 1.0) < 0.01:
				run += 1.0
			else:
				best = maxf(best, run)
				run = 1.0
		best = maxf(best, run)
	return best


func _path(idx: int, yaw: float, pitch: float) -> void:
	var lv: Dictionary = L.get_level(idx)
	var g := B.compile(lv)
	var res := B.simulate(g, lv["cannon"], B.aim_dir(yaw, pitch))
	print("=== %s  aim=(%.2f, %.2f)  反弹 %d  结果 %s  时长 %.2fs ===" % [lv["name"], yaw, pitch, res["bounces"], res["end"], res["time"]])
	var pts: PackedVector3Array = res["pts"]
	var cols: PackedInt32Array = res["seg_color"]
	var lens: PackedFloat32Array = res["seg_len"]
	for i in pts.size():
		var tag := ""
		if i > 0:
			tag = "  <-第%d段 颜色=%s 长度=%.2f" % [i, B.COLOR_NAMES[cols[i - 1]], lens[i - 1]]
		print("  P%-2d (%.2f, %.2f, %.2f)%s" % [i, pts[i].x, pts[i].y, pts[i].z, tag])
	for e in res["events"]:
		if e["type"] == "break":
			print("  💥 击碎目标 %d (颜色 %s) 于 (%.2f, %.2f, %.2f) 第 %d 次反弹后" % [e["target"], B.COLOR_NAMES[e["color"]], e["pos"].x, e["pos"].y, e["pos"].z, e["bounces"]])


func _auto(idx: int, yaw: float, pitch: float, spec: String) -> void:
	# 沿指定弹道按段号自动摆目标：spec = "1,3,5" 表示在第 1/3/5 段的中点摆同色目标
	var lv: Dictionary = L.get_level(idx)
	var g := B.compile(lv)
	var res := B.simulate(g, lv["cannon"], B.aim_dir(yaw, pitch))
	var pts: PackedVector3Array = res["pts"]
	var cols: PackedInt32Array = res["seg_color"]
	print("# auto targets for %s aim=(%.2f, %.2f)" % [lv["name"], yaw, pitch])
	var out := []
	for s in spec.split(",", false):
		var si := int(s)
		if si <= 0 or si >= pts.size():
			continue
		var p := pts[si - 1].lerp(pts[si], 1.0 - 0.02)
		out.append("{\"p\": Vector3(%.2f, %.2f, %.2f), \"r\": 0.7, \"color\": %d}," % [p.x, p.y, p.z, cols[si - 1]])
		print(out[out.size() - 1])
