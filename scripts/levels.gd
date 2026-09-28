extends RefCounted
## 关卡数据。全部是纯数据：几何由 ballistics.gd 编译成数学碰撞体，由 arena.gd 画成模型。
##
## 坐标系：地面 y=0，竞技场以原点为中心（x/z），炮台在 -z 一侧朝 +z 发射。
## blocks:  {c: 中心, s: 尺寸, r: 可选欧拉角(度)}
## targets: {p: 球心, color: 0青 / 1品红 / 2琥珀}；半径默认取关卡的 target_radius
##
## 关卡用“先找弹道、再摆目标”的方法做出来（见 tools/solve.gd）：
## 每个目标都摆在一条真实弹道的某一段中点、并取那一段的子弹颜色，
## 所以每关都必定能用一发子弹清场 —— 这一点由 tools/solve.gd 的 scan 模式扫描验证。

const CYAN := 0
const MAGENTA := 1
const AMBER := 2


static func count() -> int:
	return all().size()


static func get_level(i: int) -> Dictionary:
	var lv := all()
	return lv[clampi(i, 0, lv.size() - 1)]


static func all() -> Array:
	return [
		# ---------------------------------------------------------- 第 1 关
		{
			"name": "01 · 反射入门",
			"tip": "撞墙会换色：青 → 品红 → 琥珀 → 青。只有颜色相同的目标会被击碎，而且子弹会直接穿过去。",
			"size": Vector3(18, 9, 20),
			"cannon": Vector3(0, 1.7, -8.0),
			"base_yaw": 0.0,
			"base_pitch": 6.0,
			"target_radius": 0.78,
			"blocks": [],
			"targets": [
				{"p": Vector3(0.62, 0.92, 0.93), "color": CYAN},
				{"p": Vector3(1.94, 1.00, 0.00), "color": MAGENTA},
				{"p": Vector3(3.32, 2.73, 0.00), "color": AMBER},
			],
		},

		# ---------------------------------------------------------- 第 2 关
		{
			"name": "02 · 绕柱",
			"tip": "柱子挡在正中间。撞柱子也算反弹，同样会换色。",
			"size": Vector3(20, 9, 22),
			"cannon": Vector3(-2.0, 1.7, -9.0),
			"base_yaw": 6.0,
			"base_pitch": 9.0,
			"target_radius": 0.72,
			"blocks": [
				{"c": Vector3(0, 4.5, 1.5), "s": Vector3(2.6, 9.0, 2.6)},
			],
			"targets": [
				{"p": Vector3(-1.28, 2.68, -4.47), "color": CYAN},
				{"p": Vector3(0.30, 4.83, -5.40), "color": MAGENTA},
				{"p": Vector3(2.22, 7.44, -4.21), "color": AMBER},
				{"p": Vector3(3.94, 7.96, 6.66), "color": CYAN},
			],
		},

		# ---------------------------------------------------------- 第 3 关
		{
			"name": "03 · 斜墙",
			"tip": "斜着放的墙会把子弹拐到意想不到的方向。看着预览线，斜面的反弹同样换色。",
			"size": Vector3(20, 10, 22),
			"cannon": Vector3(0, 1.7, -9.0),
			"base_yaw": 0.0,
			"base_pitch": 8.0,
			"target_radius": 0.72,
			"blocks": [
				{"c": Vector3(-2.0, 4.5, 3.0), "s": Vector3(9.0, 9.0, 0.6), "r": Vector3(0, 32, 0)},
				{"c": Vector3(7.5, 5.0, 8.0), "s": Vector3(6.0, 10.0, 0.6), "r": Vector3(0, -38, 0)},
			],
			"targets": [
				{"p": Vector3(0.17, 2.86, -3.99), "color": CYAN},
				{"p": Vector3(-4.76, 5.35, -1.70), "color": MAGENTA},
				{"p": Vector3(-3.79, 8.27, -7.64), "color": AMBER},
				{"p": Vector3(6.07, 8.87, -8.85), "color": CYAN},
			],
		},

		# ---------------------------------------------------------- 第 4 关
		{
			"name": "04 · 窄门",
			"tip": "墙上只有一个偏心的缝。要穿过去，还要算好回来时的颜色。",
			"size": Vector3(22, 9, 22),
			"cannon": Vector3(0, 1.7, -9.5),
			"base_yaw": 0.0,
			"base_pitch": 6.0,
			"target_radius": 0.70,
			"blocks": [
				{"c": Vector3(-7.6, 4.5, 3.0), "s": Vector3(6.8, 9.0, 1.0)},
				{"c": Vector3(5.6, 4.5, 3.0), "s": Vector3(10.8, 9.0, 1.0)},
			],
			"targets": [
				{"p": Vector3(-1.42, 7.45, 4.21), "color": MAGENTA},
				{"p": Vector3(-1.99, 7.97, -6.66), "color": AMBER},
				{"p": Vector3(-2.78, 4.76, 0.00), "color": CYAN},
				{"p": Vector3(-3.63, 1.29, 5.42), "color": MAGENTA},
			],
		},

		# ---------------------------------------------------------- 第 5 关
		{
			"name": "05 · 高低台",
			"tip": "两块平台挡住上下两条路。贴着平台的边缘反弹，能去到很刁的角度。",
			"size": Vector3(22, 11, 24),
			"cannon": Vector3(0, 1.7, -10.5),
			"base_yaw": 0.0,
			"base_pitch": 9.0,
			"target_radius": 0.70,
			"blocks": [
				{"c": Vector3(-5.0, 3.0, 2.0), "s": Vector3(8.0, 0.7, 8.0)},
				{"c": Vector3(5.5, 6.5, 4.0), "s": Vector3(8.0, 0.7, 8.0)},
				{"c": Vector3(0.0, 4.5, 9.5), "s": Vector3(4.0, 9.0, 1.0)},
			],
			"targets": [
				{"p": Vector3(1.35, 3.86, -3.56), "color": CYAN},
				{"p": Vector3(3.52, 4.69, 7.62), "color": MAGENTA},
				{"p": Vector3(5.36, 1.75, 6.67), "color": AMBER},
				{"p": Vector3(7.67, 2.21, -5.20), "color": CYAN},
			],
		},

		# ---------------------------------------------------------- 第 6 关
		{
			"name": "06 · 终局",
			"tip": "五发目标，一发子弹。先在脑子里把颜色顺序排好，再扣扳机。",
			"size": Vector3(24, 11, 26),
			"cannon": Vector3(0, 1.7, -11.5),
			"base_yaw": 0.0,
			"base_pitch": 10.0,
			"target_radius": 0.68,
			"blocks": [
				{"c": Vector3(-6.5, 4.0, 0.0), "s": Vector3(2.4, 8.0, 2.4)},
				{"c": Vector3(6.5, 4.0, 0.0), "s": Vector3(2.4, 8.0, 2.4)},
				{"c": Vector3(0.0, 2.5, 6.0), "s": Vector3(9.0, 0.7, 9.0), "r": Vector3(0, 18, 0)},
				{"c": Vector3(-4.0, 8.0, 9.5), "s": Vector3(7.0, 0.7, 5.0), "r": Vector3(0, 0, -22)},
			],
			"targets": [
				{"p": Vector3(-2.58, 3.45, -5.96), "color": CYAN},
				{"p": Vector3(-3.47, 6.36, 3.23), "color": MAGENTA},
				{"p": Vector3(0.70, 9.19, 1.56), "color": AMBER},
				{"p": Vector3(5.31, 9.42, -8.31), "color": CYAN},
				{"p": Vector3(9.65, 6.47, -8.11), "color": MAGENTA},
			],
		},
	]
