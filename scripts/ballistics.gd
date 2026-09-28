extends RefCounted
## 弹道核心 —— 纯数学模拟，完全不依赖 Godot 物理引擎。
##
## 为什么自己写：瞄准预览、实弹飞行、离线求解器三处共用同一份代码，
## 所以"预览显示会中"和"实际飞行结果"逐位一致，玩家不会被手感骗到；
## 同时射线求交天生不会发生高速穿透（tunneling）。

# ---------------------------------------------------------------- 规则常量
const COLOR_COUNT := 3
const COLOR_VALUES: Array[Color] = [Color("35e0ff"), Color("ff3ea5"), Color("ffc63a")]
const COLOR_NAMES: Array[String] = ["青", "品红", "琥珀"]

const BULLET_RADIUS := 0.13     ## 子弹半径（求交时把方块按此膨胀，子弹不会陷进墙里）
const SPEED_START := 20.0       ## 初速 m/s
const SPEED_DECAY := 0.79       ## 每次反弹后的速度倍率（约 6 次反弹后能量耗尽）
const SPEED_MIN := 4.8          ## 低于此速度子弹"能量耗尽"
const MAX_BOUNCES := 10         ## 反弹次数上限
const MAX_TIME := 20.0          ## 飞行时间上限（秒）
const EPS := 0.004              ## 反弹后沿接触法线推开的安全距离
const HIT_T_MIN := 0.0001       ## 小于此距离的命中视为"自己刚站的那个面"


# ---------------------------------------------------------------- 几何缓存
## 把关卡字典编译成扁平数组，内层循环零分配，离线求解器才能跑得快。
class Geom:
	extends RefCounted
	var box_c := PackedVector3Array()
	var box_h := PackedVector3Array()
	var box_b: Array[Basis] = []
	var sph_c := PackedVector3Array()
	var sph_r := PackedFloat32Array()
	var sph_color := PackedInt32Array()
	# trace() 的输出，避免每次求交都分配对象
	var last_normal := Vector3.ZERO
	var last_kind := -1          ## 0 = 方块(墙)，1 = 目标球
	var last_index := -1
	var start_color := 0


static func compile(level: Dictionary) -> Geom:
	var g := Geom.new()
	for b in shell_boxes(level.get("size", Vector3(18, 10, 18))):
		_add_box(g, b["c"], b["s"])

	for b in level.get("blocks", []):
		var r: Vector3 = b.get("r", Vector3.ZERO)
		var basis := Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z)))
		_add_box(g, b["c"], b["s"], basis)

	var def_r: float = level.get("target_radius", 0.7)
	for tg in level.get("targets", []):
		g.sph_c.append(tg["p"])
		g.sph_r.append(tg.get("r", def_r))
		g.sph_color.append(int(tg.get("color", 0)))

	g.start_color = int(level.get("start_color", 0))
	return g


## 六面外壳（地面 / 天花板 / 四面墙），厚 1m，都位于可玩区域之外。
## 数学碰撞和画面模型共用这一份定义，保证"看到的就是撞到的"。
static func shell_boxes(size: Vector3) -> Array:
	var t := 1.0
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var hy := size.y
	return [
		{"c": Vector3(0, -t * 0.5, 0), "s": Vector3(size.x, t, size.z), "kind": "floor"},
		{"c": Vector3(0, hy + t * 0.5, 0), "s": Vector3(size.x, t, size.z), "kind": "ceiling"},
		{"c": Vector3(-hx - t * 0.5, hy * 0.5, 0), "s": Vector3(t, hy, size.z), "kind": "wall"},
		{"c": Vector3(hx + t * 0.5, hy * 0.5, 0), "s": Vector3(t, hy, size.z), "kind": "wall"},
		{"c": Vector3(0, hy * 0.5, -hz - t * 0.5), "s": Vector3(size.x, hy, t), "kind": "wall"},
		{"c": Vector3(0, hy * 0.5, hz + t * 0.5), "s": Vector3(size.x, hy, t), "kind": "wall"},
	]


static func _add_box(g: Geom, center: Vector3, size: Vector3, basis := Basis()) -> void:
	g.box_c.append(center)
	# 按子弹半径膨胀（Minkowski 近似），使子弹表面刚好贴住墙面
	g.box_h.append(size * 0.5 + Vector3(BULLET_RADIUS, BULLET_RADIUS, BULLET_RADIUS))
	g.box_b.append(basis)


static func alive_mask(g: Geom) -> PackedByteArray:
	var a := PackedByteArray()
	a.resize(g.sph_c.size())
	a.fill(1)
	return a


# ---------------------------------------------------------------- 射线求交
static func _ray_sphere(ro: Vector3, rd: Vector3, c: Vector3, r: float) -> float:
	var oc := ro - c
	var b := oc.dot(rd)
	var cc := oc.dot(oc) - r * r
	var disc := b * b - cc
	if disc < 0.0:
		return -1.0
	var sq := sqrt(disc)
	var t := -b - sq
	if t < 0.0:
		t = -b + sq
	return t if t >= 0.0 else -1.0


static func _ray_box(ro: Vector3, rd: Vector3, c: Vector3, h: Vector3, basis: Basis) -> float:
	var inv := basis.inverse()
	var o := inv * (ro - c)
	var d := inv * rd
	var tmin := -INF
	var tmax := INF
	for i in 3:
		var oi: float = o[i]
		var di: float = d[i]
		var hi: float = h[i]
		if absf(di) < 1e-8:
			if oi < -hi or oi > hi:
				return -1.0
		else:
			var t1 := (-hi - oi) / di
			var t2 := (hi - oi) / di
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			if t1 > tmin:
				tmin = t1
			if t2 < tmax:
				tmax = t2
			if tmin > tmax:
				return -1.0
	if tmax < 0.0:
		return -1.0
	if tmin < 0.0:
		return -1.0   # 起点在盒子内部：忽略，避免卡死
	return tmin


static func _box_normal(ro: Vector3, rd: Vector3, c: Vector3, h: Vector3, basis: Basis, t: float) -> Vector3:
	var inv := basis.inverse()
	var p := inv * ((ro + rd * t) - c)
	var n := Vector3.ZERO
	var best := INF
	for i in 3:
		var dist: float = h[i] - absf(p[i])
		if dist < best:
			best = dist
			n = Vector3.ZERO
			n[i] = 1.0 if p[i] >= 0.0 else -1.0
	return (basis * n).normalized()


## 把点挤出所有方块。墙角处一次命中可能同时贴住两个面，
## 只用其中一个法线反弹会让子弹卡进另一面墙里，所以反弹后统一做一次"脱嵌"。
static func _depenetrate(g: Geom, p: Vector3, margin := 0.002) -> Vector3:
	for _iter in 6:
		var moved := false
		for i in g.box_c.size():
			var h: Vector3 = g.box_h[i]
			var lp: Vector3 = g.box_b[i].inverse() * (p - g.box_c[i])
			var dx := h.x + margin - absf(lp.x)
			var dy := h.y + margin - absf(lp.y)
			var dz := h.z + margin - absf(lp.z)
			if dx > 0.0 and dy > 0.0 and dz > 0.0:
				var axis := 0
				var pen := dx
				if dy < pen:
					axis = 1
					pen = dy
				if dz < pen:
					axis = 2
					pen = dz
				var n := Vector3.ZERO
				n[axis] = 1.0 if lp[axis] >= 0.0 else -1.0
				p += (g.box_b[i] * n) * pen
				moved = true
		if not moved:
			break
	return p


## 命中点处所有"贴着"的方块表面法线。墙角一次命中会同时贴住两个面，
## 必须两个面都反射（台球撞库边的标准做法），否则子弹会沿错误的法线穿出竞技场。
static func _contact_normals(g: Geom, p: Vector3, tol: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in g.box_c.size():
		var h: Vector3 = g.box_h[i]
		var lp: Vector3 = g.box_b[i].inverse() * (p - g.box_c[i])
		var axis := -1
		var best := tol
		for a in 3:
			var d := h[a] - absf(lp[a])
			if d > -tol and d < best:
				var b1 := (a + 1) % 3
				var b2 := (a + 2) % 3
				if absf(lp[b1]) <= h[b1] + tol and absf(lp[b2]) <= h[b2] + tol:
					best = d
					axis = a
		if axis >= 0:
			var n := Vector3.ZERO
			n[axis] = 1.0 if lp[axis] >= 0.0 else -1.0
			out.append((g.box_b[i] * n).normalized())
	return out


## 求最近命中。命中信息写在 g.last_* 上。
static func trace(g: Geom, ro: Vector3, rd: Vector3, alive: PackedByteArray, tmax: float = 4000.0) -> float:
	var best := tmax
	g.last_kind = -1
	g.last_index = -1
	var bc := g.box_c
	for i in bc.size():
		var t := _ray_box(ro, rd, bc[i], g.box_h[i], g.box_b[i])
		if t > HIT_T_MIN and t < best:
			best = t
			g.last_kind = 0
			g.last_index = i
	var sc := g.sph_c
	for i in sc.size():
		if alive[i] == 0:
			continue
		var t := _ray_sphere(ro, rd, sc[i], g.sph_r[i] + BULLET_RADIUS)
		if t > HIT_T_MIN and t < best:
			best = t
			g.last_kind = 1
			g.last_index = i
	if g.last_index < 0:
		return -1.0
	if g.last_kind == 0:
		g.last_normal = _box_normal(ro, rd, g.box_c[g.last_index], g.box_h[g.last_index], g.box_b[g.last_index], best)
	else:
		g.last_normal = ((ro + rd * best) - g.sph_c[g.last_index]).normalized()
	return best


# ---------------------------------------------------------------- 模拟
## 单发子弹的完整弹道。返回的路径就是实弹飞行时逐帧走的同一条路径。
##
## 规则：
##   · 撞墙 / 撞到"颜色不对"的目标  -> 反射 + 子弹换色（颜色循环 +1）+ 损失能量
##   · 撞到"颜色相同"的目标          -> 击碎并**直接穿过**（不换色、不掉速）
##   · 所有目标清空即胜利
static func simulate(g: Geom, origin: Vector3, dir: Vector3, alive_in: PackedByteArray = PackedByteArray(),
		want_path := true, start_color := -1) -> Dictionary:
	var alive := alive_in
	if alive.size() != g.sph_c.size():
		alive = alive_mask(g)

	var pts := PackedVector3Array()
	var seg_color := PackedInt32Array()
	var seg_len := PackedFloat32Array()
	var seg_speed := PackedFloat32Array()
	var events: Array = []
	var destroyed := PackedInt32Array()

	var pos := origin
	var d := dir.normalized()
	var color := g.start_color if start_color < 0 else start_color
	var speed := SPEED_START
	var bounces := 0
	var flight_time := 0.0
	var end_reason := "unknown"
	if want_path:
		pts.append(pos)

	while true:
		var t := trace(g, pos, d, alive)
		if t < 0.0:
			# 理论上封闭竞技场不会发生；真发生了就当作子弹自毁，绝不飞到场外
			end_reason = "escaped"
			if want_path:
				pts.append(pos + d * 0.2)
				seg_color.append(color)
				seg_len.append(0.2)
				seg_speed.append(speed)
			break

		var hit_pos := pos + d * t
		var n := g.last_normal
		var kind := g.last_kind
		var index := g.last_index
		var seg_time := t / speed
		flight_time += seg_time
		if want_path:
			pts.append(hit_pos)
			seg_color.append(color)
			seg_len.append(t)
			seg_speed.append(speed)

		if kind == 1 and alive[index] == 1 and color == g.sph_color[index]:
			# 同色：击碎并穿过
			alive[index] = 0
			destroyed.append(index)
			events.append({"type": "break", "pos": hit_pos, "color": color, "target": index,
					"bounces": bounces, "seg": seg_color.size() - 1 if want_path else -1})
			pos = _depenetrate(g, hit_pos + d * EPS)
			if want_path:
				pts[pts.size() - 1] = pos
			var remain := false
			for a in alive:
				if a == 1:
					remain = true
					break
			if not remain:
				end_reason = "cleared"
				break
			continue

		# 其它情况：反射 + 换色 + 掉速
		bounces += 1
		events.append({
			"type": "bounce", "pos": hit_pos, "normal": n, "color": color,
			"bounces": bounces, "blocked": kind == 1,
			"seg": seg_color.size() - 1 if want_path else -1
		})
		# 墙角同时贴住两个面：两个法线都要反射，否则会沿着"还朝着另一面墙"的方向飞出去
		var contacts := _contact_normals(g, hit_pos, 0.03)
		if contacts.is_empty():
			contacts.append(n)
		d = d.normalized()
		var push := Vector3.ZERO
		for cn in contacts:
			if d.dot(cn) < -1e-6:
				d = (d - 2.0 * d.dot(cn) * cn).normalized()
			push += cn
		color = (color + 1) % COLOR_COUNT
		speed *= SPEED_DECAY
		pos = hit_pos + (push.normalized() if push.length() > 0.0 else n) * EPS
		pos = _depenetrate(g, pos)
		if want_path:
			pts[pts.size() - 1] = pos

		if bounces >= MAX_BOUNCES:
			end_reason = "max_bounce"
			break
		if speed < SPEED_MIN:
			end_reason = "energy"
			break
		if flight_time > MAX_TIME:
			end_reason = "time"
			break

	return {
		"pts": pts,
		"seg_color": seg_color,
		"seg_len": seg_len,
		"seg_speed": seg_speed,
		"events": events,
		"destroyed": destroyed,
		"bounces": bounces,
		"time": flight_time,
		"end": end_reason,
		"alive": alive,
	}


## 只要结果不要路径的快速版本（离线求解器用）。
static func evaluate(g: Geom, origin: Vector3, dir: Vector3) -> PackedInt32Array:
	var alive := alive_mask(g)
	var dummy := simulate(g, origin, dir, alive, false)
	return dummy["destroyed"]


## 由 yaw/pitch（度）得到炮口朝向。约定：pitch 为正 = 抬头上扬。
static func aim_dir(yaw_deg: float, pitch_deg: float) -> Vector3:
	var b := Basis.from_euler(Vector3(deg_to_rad(-pitch_deg), deg_to_rad(yaw_deg), 0.0), EULER_ORDER_YXZ)
	return (b * Vector3(0, 0, 1)).normalized()


## 路径总时长（用于实弹按真实速度飞行）。
static func path_duration(result: Dictionary) -> float:
	var total := 0.0
	var lens: PackedFloat32Array = result["seg_len"]
	var spds: PackedFloat32Array = result["seg_speed"]
	for i in lens.size():
		total += lens[i] / maxf(spds[i], 0.001)
	return total
