extends Node3D
## ONE SHOT · 一弹到底 —— 主控制器
##
## 玩法：整个关卡只有一发子弹。子弹每次撞墙/撞到颜色不对的目标都会"变色"
##      （青 → 品红 → 琥珀 → 青），只有颜色一致的目标会被击碎且子弹直接穿过。
##      目标清空即过关；子弹能量耗尽还没打完就要重来。
##
## 关键实现：瞄准预览、实弹飞行、离线求解器全部调用 ballistics.gd 里的同一份模拟，
##          所以画出来的虚线就是子弹真正会走的路线。

const B := preload("res://scripts/ballistics.gd")
const L := preload("res://scripts/levels.gd")
const ArenaScript := preload("res://scripts/arena.gd")
const HudScript := preload("res://scripts/hud.gd")
const AudioScript := preload("res://scripts/audio.gd")
const M := preload("res://scripts/materials.gd")

enum State { TITLE, AIM, FLY, CLEAR, FAIL, FINISH }

const PREVIEW_SEGS := 4          ## 预览到第几次反弹（4 段 = 3 次反弹）
const DASH_STEP := 0.62
const SENS := 0.055              ## 鼠标灵敏度（度/像素）
const SENS_FINE := 0.016
const FOCUS_SECONDS := 3.0       ## 子弹时间总时长
const FOCUS_SCALE := 0.26

var state: int = State.TITLE
var level_index := 0
var level: Dictionary = {}
var geom: B.Geom
var aim_yaw := 0.0
var aim_pitch := 0.0
var aim_dir := Vector3(0, 0, 1)
var base_yaw := 0.0
var base_pitch := 0.0

var arena: Node3D
var hud: CanvasLayer
var sfx: Node
var cam: Camera3D
var env_node: WorldEnvironment

# 飞行状态
var flight: Dictionary = {}
var flight_time := 0.0
var flight_seg := 0
var seg_times := PackedFloat32Array()
var events_by_seg := {}
var bullet_pos := Vector3.ZERO
var bullet_dir := Vector3(0, 0, 1)
var bullet_color := 0
var focus_left := FOCUS_SECONDS
var slowmo := false
var destroyed_count := 0
var bounce_count := 0
var shots_taken := 0
var total_time := 0.0
var run_time := 0.0

# 视图节点
var bullet_root: Node3D
var bullet_mesh: MeshInstance3D
var bullet_light: OmniLight3D
var trail_node: MeshInstance3D
var trail_im: ImmediateMesh
var trail_pts := PackedVector3Array()
var trail_cols := PackedColorArray()
var preview_nodes: Array[MultiMeshInstance3D] = []
var preview_mms: Array[MultiMesh] = []
var muzzle_flash: OmniLight3D
var cam_target_smooth := Vector3.ZERO
var shake := 0.0
var time_acc := 0.0


func _ready() -> void:
	randomize()
	_build_world()
	_build_view_nodes()
	hud = HudScript.new()
	add_child(hud)
	sfx = AudioScript.new()
	add_child(sfx)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_load_level(0)
	_show_title()


func _build_world() -> void:
	env_node = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.012, 0.016, 0.028)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.30, 0.42, 0.58)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 3.0
	e.glow_enabled = true
	e.glow_intensity = 0.85
	e.glow_bloom = 0.12
	e.glow_hdr_threshold = 0.85
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	e.fog_enabled = true
	e.fog_light_color = Color(0.05, 0.09, 0.16)
	e.fog_density = 0.012
	e.ssao_enabled = true
	e.ssao_radius = 1.2
	e.ssao_intensity = 1.4
	env_node.environment = e
	add_child(env_node)

	cam = Camera3D.new()
	cam.fov = 68.0
	cam.near = 0.08
	cam.far = 400.0
	cam.current = true
	add_child(cam)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.62, 0.78, 1.0)
	sun.light_energy = 0.42
	sun.rotation_degrees = Vector3(-58, 34, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)

	arena = ArenaScript.new()
	add_child(arena)


func _build_view_nodes() -> void:
	# 子弹
	bullet_root = Node3D.new()
	bullet_root.visible = false
	add_child(bullet_root)
	bullet_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = B.BULLET_RADIUS
	sm.height = B.BULLET_RADIUS * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	bullet_mesh.mesh = sm
	bullet_root.add_child(bullet_mesh)
	bullet_light = OmniLight3D.new()
	bullet_light.light_energy = 3.2
	bullet_light.omni_range = 12.0
	bullet_light.shadow_enabled = false
	bullet_root.add_child(bullet_light)

	muzzle_flash = OmniLight3D.new()
	muzzle_flash.light_energy = 0.0
	muzzle_flash.omni_range = 14.0
	muzzle_flash.light_color = Color("8fe8ff")
	add_child(muzzle_flash)

	# 轨迹线
	trail_node = MeshInstance3D.new()
	trail_im = ImmediateMesh.new()
	trail_node.mesh = trail_im
	trail_node.material_override = M.trail()
	trail_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trail_node)

	# 预览虚线：每种颜色一个 MultiMesh
	var dash_mesh := SphereMesh.new()
	dash_mesh.radius = 0.055
	dash_mesh.height = 0.11
	dash_mesh.radial_segments = 8
	dash_mesh.rings = 4
	for i in B.COLOR_COUNT:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = B.COLOR_VALUES[i]
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.disable_receive_shadows = true
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = dash_mesh
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		preview_nodes.append(mi)
		preview_mms.append(mm)


# ------------------------------------------------------------------ 关卡
func _load_level(i: int) -> void:
	level_index = i
	level = L.get_level(i)
	geom = B.compile(level)
	base_yaw = float(level.get("base_yaw", 0.0))
	base_pitch = float(level.get("base_pitch", 6.0))
	aim_yaw = base_yaw
	aim_pitch = base_pitch
	arena.build(level)
	focus_left = FOCUS_SECONDS
	destroyed_count = 0
	flight = {}
	bullet_root.visible = false
	trail_im.clear_surfaces()
	_clear_preview()
	var colors := []
	for t in level.get("targets", []):
		colors.append(int(t.get("color", 0)))
	hud.setup(level, colors)
	hud.hide_overlay()
	_set_state(State.AIM)
	_refresh_aim()
	var pos: Vector3 = level["cannon"]
	cam_target_smooth = pos
	cam.position = _aim_cam_pos() + Vector3(0.001, 0, 0)
	bullet_pos = pos
	bullet_dir = aim_dir


func _show_title() -> void:
	_set_state(State.TITLE)
	hud.set_reticle(false)
	hud.show_overlay("ONE SHOT", "一弹到底 —— 整个关卡只有一发子弹。\n每次撞墙子弹就会换色，只有颜色相同的目标才会被击碎。\n把场上所有目标清空，就算过关。", "点击 / 空格  开始", Color("8fe8ff"))


func _set_state(s: int) -> void:
	state = s
	hud.set_play_visible(s != State.TITLE)
	match s:
		State.TITLE:
			_clear_preview()
			hud.set_reticle(false)
		State.AIM:
			hud.set_reticle(true)
			_update_preview()
			hud.set_color_state(0, 0)
		State.FLY:
			_clear_preview()
			hud.set_reticle(false)
		State.CLEAR, State.FAIL, State.FINISH:
			_clear_preview()
			hud.set_reticle(false)


# ------------------------------------------------------------------ 瞄准
func _refresh_aim() -> void:
	aim_dir = B.aim_dir(aim_yaw, aim_pitch)
	if arena.cannon_pivot != null:
		arena.cannon_pivot.basis = Basis.looking_at(aim_dir, Vector3.UP)
	if state == State.AIM:
		_update_preview()


func _aim_cam_pos() -> Vector3:
	var k_yaw := base_yaw + (aim_yaw - base_yaw) * 0.30
	# 只用水平朝向摆机位：抬枪时镜头不要跟着栽下去
	var d := B.aim_dir(k_yaw, 0.0)
	var pos: Vector3 = level["cannon"]
	var size: Vector3 = level.get("size", Vector3(18, 9, 20))
	var right := d.cross(Vector3.UP).normalized()
	var height := clampf(size.y * 0.38, 2.4, 4.2)
	var want := pos - d * 4.6 + Vector3.UP * height + right * 3.4
	want = _clamp_inside(want, 0.5)
	# 机位如果被方块挡住就往炮台方向拉近
	return _pull_camera(pos + Vector3.UP * 0.9, want)


func _point_in_blocks(p: Vector3) -> bool:
	# 前 6 个是竞技场外壳，跳过
	for i in range(6, geom.box_c.size()):
		var h: Vector3 = geom.box_h[i]
		var lp: Vector3 = geom.box_b[i].inverse() * (p - geom.box_c[i])
		if absf(lp.x) < h.x + 0.3 and absf(lp.y) < h.y + 0.3 and absf(lp.z) < h.z + 0.3:
			return true
	return false


func _pull_camera(target: Vector3, want: Vector3) -> Vector3:
	var d := want - target
	var steps := 20
	var last_ok := 0.0
	for i in steps + 1:
		var t := float(i) / float(steps)
		if _point_in_blocks(target + d * t):
			break
		last_ok = t
	return target + d * maxf(last_ok, 0.15)


func _clamp_inside(p: Vector3, margin: float) -> Vector3:
	var size: Vector3 = level.get("size", Vector3(18, 9, 20))
	return Vector3(
		clampf(p.x, -size.x * 0.5 + margin, size.x * 0.5 - margin),
		clampf(p.y, margin, size.y - margin),
		clampf(p.z, -size.z * 0.5 + margin, size.z * 0.5 - margin))


# ------------------------------------------------------------------ 预览虚线
func _clear_preview() -> void:
	for mm in preview_mms:
		mm.visible_instance_count = 0
		mm.instance_count = 0


func _update_preview() -> void:
	var res := B.simulate(geom, level["cannon"], aim_dir, PackedByteArray(), true)
	var pts: PackedVector3Array = res["pts"]
	var cols: PackedInt32Array = res["seg_color"]
	var buckets: Array = [[], [], []]
	var nseg: int = mini(cols.size(), PREVIEW_SEGS)
	for s in nseg:
		var a := pts[s]
		var b := pts[s + 1]
		var seg_len := a.distance_to(b)
		if seg_len < 1e-4:
			continue
		var steps := maxi(1, int(seg_len / DASH_STEP))
		for k in steps + 1:
			var f := float(k) / float(steps)
			var p := a.lerp(b, f)
			var along := (float(s) + f) / float(maxi(nseg, 1))
			var scale := lerpf(1.15, 0.5, along)
			if s >= PREVIEW_SEGS - 1:
				scale *= lerpf(1.0, 0.25, f)
			buckets[cols[s]].append(Transform3D(Basis().scaled(Vector3(scale, scale, scale)), p))
	for i in B.COLOR_COUNT:
		var arr: Array = buckets[i]
		var mm := preview_mms[i]
		mm.instance_count = arr.size()
		mm.visible_instance_count = arr.size()
		for j in arr.size():
			mm.set_instance_transform(j, arr[j])


# ------------------------------------------------------------------ 发射
func _fire() -> void:
	if state != State.AIM:
		return
	shots_taken += 1
	flight = B.simulate(geom, level["cannon"], aim_dir, PackedByteArray(), true)
	var pts: PackedVector3Array = flight["pts"]
	var lens: PackedFloat32Array = flight["seg_len"]
	var spds: PackedFloat32Array = flight["seg_speed"]
	seg_times = PackedFloat32Array()
	var acc := 0.0
	for i in lens.size():
		acc += lens[i] / maxf(spds[i], 0.01)
		seg_times.append(acc)
	events_by_seg = {}
	for ev in flight["events"]:
		var s: int = ev.get("seg", -1)
		if s < 0:
			continue
		if not events_by_seg.has(s):
			events_by_seg[s] = []
		events_by_seg[s].append(ev)

	flight_time = 0.0
	flight_seg = 0
	bounce_count = 0
	bullet_color = 0
	bullet_pos = pts[0] if pts.size() > 0 else level["cannon"]
	bullet_dir = aim_dir
	trail_pts = PackedVector3Array([bullet_pos])
	trail_cols = PackedColorArray([B.COLOR_VALUES[0]])
	trail_im.clear_surfaces()
	bullet_root.visible = true
	bullet_mesh.material_override = M.glow(B.COLOR_VALUES[0], 3.4, Color(0.05, 0.06, 0.08))
	bullet_light.light_color = B.COLOR_VALUES[0]
	muzzle_flash.global_position = level["cannon"]
	muzzle_flash.light_color = B.COLOR_VALUES[0]
	muzzle_flash.light_energy = 6.0
	sfx.play("shot", -2.0)
	_set_state(State.FLY)
	hud.set_color_state(0, 0)


func _on_segment_end(k: int) -> void:
	# 该段结束时触发事件：反弹 / 击碎
	if events_by_seg.has(k):
		for ev in events_by_seg[k]:
			if ev["type"] == "break":
				_on_break(ev)
			else:
				_on_bounce(ev)
	var cols: PackedInt32Array = flight["seg_color"]
	if k + 1 < cols.size():
		bullet_color = cols[k + 1]
		bullet_mesh.material_override = M.glow(B.COLOR_VALUES[bullet_color], 3.4, Color(0.05, 0.06, 0.08))
		bullet_light.light_color = B.COLOR_VALUES[bullet_color]
	var bounces := bounce_count
	hud.set_color_state(bullet_color, bounces)


func _on_bounce(ev: Dictionary) -> void:
	bounce_count += 1
	var pos: Vector3 = ev["pos"]
	var blocked: bool = ev.get("blocked", false)
	sfx.play_at("block" if blocked else "ricochet", pos, -3.0 if blocked else -5.0)
	_burst(pos, B.COLOR_VALUES[int(ev["color"])], 10, 0.11)
	_flash(pos, B.COLOR_VALUES[int(ev["color"])], 2.4)
	shake = maxf(shake, 0.06)


func _on_break(ev: Dictionary) -> void:
	var pos: Vector3 = ev["pos"]
	var idx: int = ev["target"]
	var color: Color = B.COLOR_VALUES[int(ev["color"])]
	sfx.play_at("break", pos, -1.0)
	_burst(pos, color, 34, 0.16)
	_flash(pos, color, 7.0)
	shake = maxf(shake, 0.16)
	destroyed_count += 1
	hud.mark_destroyed(idx)
	if idx >= 0 and idx < arena.target_roots.size():
		var node: Node3D = arena.target_roots[idx]
		var tw := create_tween()
		tw.tween_property(node, "scale", Vector3(1.8, 1.8, 1.8), 0.12)
		tw.tween_property(node, "scale", Vector3.ZERO, 0.16)
		tw.tween_callback(func(): node.visible = false)


func _burst(pos: Vector3, color: Color, amount: int, size: float) -> void:
	var p := CPUParticles3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	p.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh.material = mat
	p.amount = amount
	p.lifetime = 0.55
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 7.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.damping_min = 3.0
	p.damping_max = 6.0
	p.position = pos
	arena.add_child(p)
	p.emitting = true
	if p.has_signal("finished"):
		p.finished.connect(p.queue_free)


func _flash(pos: Vector3, color: Color, energy: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = 9.0
	l.position = pos
	arena.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.22)
	tw.tween_callback(l.queue_free)


# ------------------------------------------------------------------ 主循环
func _process(delta: float) -> void:
	time_acc += delta
	run_time += delta
	hud.process_hud(delta)
	arena.animate_targets(delta, time_acc)
	muzzle_flash.light_energy = maxf(0.0, muzzle_flash.light_energy - delta * 26.0)

	match state:
		State.TITLE:
			_title_camera(delta)
		State.AIM:
			_update_aim_keys(delta)
			_update_camera(delta)
		State.FLY:
			_update_flight(delta)
			_update_camera(delta)
		_:
			_update_camera(delta)

	if state == State.AIM or state == State.FLY:
		hud.set_focus(focus_left / FOCUS_SECONDS)


func _title_camera(delta: float) -> void:
	var size: Vector3 = level.get("size", Vector3(18, 9, 20))
	var t := time_acc * 0.18
	var r := maxf(size.x, size.z) * 0.72
	var p := Vector3(sin(t) * r, size.y * 0.62, cos(t) * r)
	cam.position = cam.position.lerp(p, 1.0 - exp(-2.0 * delta))
	cam_target_smooth = cam_target_smooth.lerp(Vector3(0, size.y * 0.35, 0), 1.0 - exp(-2.0 * delta))
	cam.look_at(cam_target_smooth, Vector3.UP)


func _update_aim_keys(delta: float) -> void:
	var sp := 22.0 * delta
	if Input.is_key_pressed(KEY_LEFT):
		aim_yaw -= sp
	if Input.is_key_pressed(KEY_RIGHT):
		aim_yaw += sp
	if Input.is_key_pressed(KEY_UP):
		aim_pitch += sp
	if Input.is_key_pressed(KEY_DOWN):
		aim_pitch -= sp
	_clamp_aim()


func _clamp_aim() -> void:
	aim_yaw = clampf(aim_yaw, base_yaw - 85.0, base_yaw + 85.0)
	aim_pitch = clampf(aim_pitch, -32.0, 82.0)


func _update_flight(delta: float) -> void:
	var pts: PackedVector3Array = flight["pts"]
	var nseg: int = pts.size() - 1
	if nseg <= 0:
		_finish_flight()
		return

	# 子弹时间：只放慢子弹本身，不去动 Engine.time_scale，避免全局副作用
	var scale := 1.0
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and focus_left > 0.0:
		scale = FOCUS_SCALE
		focus_left = maxf(0.0, focus_left - delta)
		slowmo = true
	else:
		slowmo = false

	flight_time += delta * scale
	var total: float = seg_times[seg_times.size() - 1] if seg_times.size() > 0 else 0.0
	if flight_time >= total:
		while flight_seg < nseg:
			_on_segment_end(flight_seg)
			flight_seg += 1
		bullet_pos = pts[pts.size() - 1]
		_finish_flight()
		return

	while flight_seg < nseg and flight_time >= seg_times[flight_seg]:
		_on_segment_end(flight_seg)
		flight_seg += 1

	var t0: float = 0.0 if flight_seg == 0 else seg_times[flight_seg - 1]
	var t1: float = seg_times[flight_seg]
	var f: float = 0.0 if t1 <= t0 else clampf((flight_time - t0) / (t1 - t0), 0.0, 1.0)
	bullet_pos = pts[flight_seg].lerp(pts[flight_seg + 1], f)
	bullet_dir = (pts[flight_seg + 1] - pts[flight_seg]).normalized()
	bullet_root.position = bullet_pos

	# 轨迹线：一直重画到当前点
	if trail_pts.size() == 0 or trail_pts[trail_pts.size() - 1].distance_to(bullet_pos) > 0.12:
		trail_pts.append(bullet_pos)
		trail_cols.append(B.COLOR_VALUES[bullet_color])
		_rebuild_trail()


func _rebuild_trail() -> void:
	trail_im.clear_surfaces()
	var n := trail_pts.size()
	if n < 2:
		return
	# 用面向摄像机的三角带画轨迹：GL 的 1 像素线太细，看不出颜色
	trail_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, null)
	var cam_pos := cam.global_position
	for i in n - 1:
		var a := trail_pts[i]
		var b := trail_pts[i + 1]
		var seg := b - a
		if seg.length() < 1e-5:
			continue
		var dir := seg.normalized()
		var to_cam := cam_pos - a
		var side := dir.cross(to_cam)
		if side.length() < 1e-5:
			continue
		side = side.normalized() * 0.075
		var ca: Color = trail_cols[i]
		var cb: Color = trail_cols[i + 1]
		var a0 := a - side
		var a1 := a + side
		var b0 := b - side
		var b1 := b + side
		trail_im.surface_set_color(ca)
		trail_im.surface_add_vertex(a0)
		trail_im.surface_set_color(ca)
		trail_im.surface_add_vertex(a1)
		trail_im.surface_set_color(cb)
		trail_im.surface_add_vertex(b1)
		trail_im.surface_set_color(ca)
		trail_im.surface_add_vertex(a0)
		trail_im.surface_set_color(cb)
		trail_im.surface_add_vertex(b1)
		trail_im.surface_set_color(cb)
		trail_im.surface_add_vertex(b0)
	trail_im.surface_end()


func _finish_flight() -> void:
	bullet_root.visible = false
	var end_reason: String = flight.get("end", "")
	if end_reason == "cleared":
		_on_level_clear()
	else:
		_on_level_fail()


func _on_level_clear() -> void:
	var bounces: int = flight.get("bounces", 0)
	sfx.play("win", -4.0)
	if level_index >= L.count() - 1:
		_set_state(State.FINISH)
		hud.show_overlay("全部清场", "六关全通，总共开了 %d 枪，用了 %.0f 秒。\n感谢试玩 —— 这就是「一弹到底」。" % [shots_taken, total_time + run_time],
				"点击 / 空格  重头再来", Color("ffc63a"))
	else:
		_set_state(State.CLEAR)
		hud.show_overlay("清 · 场", "用了一发子弹，%d 次反弹。剩余目标 0。" % bounces,
				"点击 / 空格  进入下一关", Color("8fe8ff"))


func _on_level_fail() -> void:
	var left: int = _targets_left()
	sfx.play("fail", -3.0)
	sfx.play("lose", -8.0)
	_set_state(State.FAIL)
	hud.show_overlay("能量耗尽", "子弹停下来了，场上还剩 %d 个目标。\n提示：%s" % [left, str(level.get("tip", ""))],
			"R / 点击  重来一次", Color("ff6b8a"))


func _targets_left() -> int:
	var n := 0
	for t in level.get("targets", []):
		n += 1
	return n - destroyed_count


func _update_camera(delta: float) -> void:
	var want_pos: Vector3
	var want_target: Vector3
	if state == State.FLY or state == State.CLEAR or state == State.FAIL:
		want_pos = bullet_pos - bullet_dir * 6.2 + Vector3.UP * 2.3
		want_target = bullet_pos + bullet_dir * 5.0
		want_pos = _pull_camera(bullet_pos, want_pos)
	elif state == State.AIM:
		want_pos = _aim_cam_pos()
		want_target = level["cannon"] + aim_dir * 9.0 + Vector3.UP * 1.0
	else:
		want_pos = cam.position
		want_target = cam_target_smooth
	want_pos = _clamp_inside(want_pos, 0.4)
	var k := 1.0 - exp(-9.0 * delta)
	cam.position = cam.position.lerp(want_pos, k)
	cam_target_smooth = cam_target_smooth.lerp(want_target, k)
	shake = maxf(0.0, shake - delta * 0.6)
	var off := Vector3.ZERO
	if shake > 0.001:
		off = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 0.25
	cam.look_at(cam_target_smooth + off, Vector3.UP)


# ------------------------------------------------------------------ 输入
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and state == State.AIM:
		var s := SENS_FINE if Input.is_key_pressed(KEY_CTRL) else SENS
		aim_yaw += event.relative.x * s
		aim_pitch -= event.relative.y * s
		_clamp_aim()
		_refresh_aim()
		return

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_primary()
			MOUSE_BUTTON_RIGHT:
				pass
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_primary()
			KEY_R:
				_retry()
			KEY_ESCAPE:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				else:
					Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _primary() -> void:
	# 鼠标被 ESC 放出来了：先点一下抓回来，不要误发射
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and state != State.TITLE:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return
	match state:
		State.TITLE:
			sfx.play("confirm", -6.0)
			hud.hide_overlay()
			_load_level(0)
		State.AIM:
			_fire()
		State.CLEAR:
			sfx.play("ui", -8.0)
			total_time += run_time
			run_time = 0.0
			_load_level(level_index + 1)
		State.FAIL:
			_retry()
		State.FINISH:
			total_time = 0.0
			run_time = 0.0
			shots_taken = 0
			_show_title()


func _retry() -> void:
	match state:
		State.AIM, State.FLY, State.FAIL, State.CLEAR:
			Engine.time_scale = 1.0
			slowmo = false
			sfx.play("ui", -8.0)
			_load_level(level_index)
		_:
			pass
