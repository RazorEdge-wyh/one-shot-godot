extends Node3D
## 把关卡数据画出来。几何和 ballistics.gd 编译出的数学碰撞体一一对应，
## 所以"看到的墙"就是"子弹会弹的墙"。

const B := preload("res://scripts/ballistics.gd")
const M := preload("res://scripts/materials.gd")

## 摆在平台上的装饰模型（Kenney Space Kit，CC0）
const PROPS := ["console.obj", "consoleScreen.obj", "barrel.obj", "barrelLarge.obj",
	"satelliteDish.obj", "rocksSmall.obj", "laserSabel.obj", "metalFence.obj"]

var level: Dictionary
var target_roots: Array[Node3D] = []
var cannon_pivot: Node3D
var _prop_meshes := {}
var _prop_mesh_mat: StandardMaterial3D


func build(lv: Dictionary) -> void:
	level = lv
	for c in get_children():
		c.queue_free()
	target_roots.clear()
	cannon_pivot = null
	_build_shell()
	_build_blocks()
	_build_targets()
	_build_cannon()
	_build_strips()


func _box(center: Vector3, size: Vector3, mat: Material, basis := Basis()) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = Transform3D(basis, center)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _build_shell() -> void:
	var size: Vector3 = level["size"]
	var floor_mat := M.grid(Color(0.85, 1.0, 1.15), 2.0, 0.45, Color(0.026, 0.034, 0.055))
	var wall_mat := M.grid(Color(0.7, 0.85, 1.0), 2.0, 0.30, Color(0.030, 0.038, 0.060))
	var ceil_mat := M.grid(Color(0.55, 0.7, 0.9), 2.5, 0.22, Color(0.022, 0.028, 0.045))
	for b in B.shell_boxes(size):
		var mat: Material = wall_mat
		if b["kind"] == "floor":
			mat = floor_mat
		elif b["kind"] == "ceiling":
			mat = ceil_mat
		_box(b["c"], b["s"], mat)


func _build_blocks() -> void:
	var mat := M.block(Color(0.075, 0.085, 0.12), 0.5)
	for b in level.get("blocks", []):
		var r: Vector3 = b.get("r", Vector3.ZERO)
		var basis := Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z)))
		_box(b["c"], b["s"], mat, basis)
		_maybe_decorate(b, basis)


## 在"平放"的大方块上摆一个小道具，让场景不那么空
func _maybe_decorate(b: Dictionary, basis: Basis) -> void:
	var s: Vector3 = b["s"]
	if s.y > minf(s.x, s.z) * 0.4:
		return
	if minf(s.x, s.z) < 4.0:
		return
	var f: String = PROPS[target_roots.size() % PROPS.size()]
	var local := Vector3(s.x * 0.5 - 1.0, 0.0, s.z * 0.5 - 1.0)
	var pos: Vector3 = b["c"] + basis * local
	pos.y = b["c"].y + s.y * 0.5
	_add_prop(f, pos, 1.0, randf_range(0.0, 360.0))


func _prop_material() -> StandardMaterial3D:
	if _prop_mesh_mat == null:
		_prop_mesh_mat = StandardMaterial3D.new()
		_prop_mesh_mat.albedo_color = Color(0.10, 0.115, 0.155)
		_prop_mesh_mat.metallic = 0.65
		_prop_mesh_mat.roughness = 0.42
		_prop_mesh_mat.emission_enabled = true
		_prop_mesh_mat.emission = Color(0.10, 0.36, 0.52)
		_prop_mesh_mat.emission_energy_multiplier = 0.22
	return _prop_mesh_mat


func _add_prop(file: String, pos: Vector3, want_size: float, yaw_deg: float) -> void:
	if not _prop_meshes.has(file):
		var path := "res://assets/models/" + file
		if not ResourceLoader.exists(path):
			_prop_meshes[file] = null
		else:
			_prop_meshes[file] = load(path)
	var mesh: Mesh = _prop_meshes[file]
	if mesh == null:
		return
	var aabb := mesh.get_aabb()
	var ext := aabb.size
	var biggest := maxf(ext.x, maxf(ext.y, ext.z))
	if biggest <= 0.0:
		return
	var k := want_size / biggest
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _prop_material()
	mi.scale = Vector3(k, k, k)
	# 底面贴到平台上
	mi.position = pos - Vector3(0, aabb.position.y * k, 0)
	mi.rotation.y = deg_to_rad(yaw_deg)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_targets() -> void:
	var def_r: float = level.get("target_radius", 0.7)
	for i in level.get("targets", []).size():
		var t: Dictionary = level["targets"][i]
		var color: Color = B.COLOR_VALUES[int(t["color"])]
		var r: float = t.get("r", def_r)
		var root := Node3D.new()
		root.position = t["p"]
		root.set_meta("color_index", int(t["color"]))
		add_child(root)

		var core := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 24
		sm.rings = 12
		core.mesh = sm
		core.material_override = M.glow(color, 2.6, color * 0.25)
		root.add_child(core)

		var halo := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = r * 1.28
		hm.height = r * 2.56
		hm.radial_segments = 24
		hm.rings = 12
		halo.mesh = hm
		halo.material_override = M.halo(color, 1.15)
		root.add_child(halo)

		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 2.2
		light.omni_range = 7.0
		light.shadow_enabled = false
		root.add_child(light)

		target_roots.append(root)


func _build_cannon() -> void:
	var pos: Vector3 = level["cannon"]
	# 支柱
	var col := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.34
	cm.bottom_radius = 0.5
	cm.height = pos.y
	cm.radial_segments = 16
	col.mesh = cm
	col.material_override = M.block(Color(0.09, 0.10, 0.14), 0.25)
	col.position = Vector3(pos.x, pos.y * 0.5, pos.z)
	add_child(col)

	cannon_pivot = Node3D.new()
	cannon_pivot.position = pos
	add_child(cannon_pivot)

	# 底座
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.52
	bm.bottom_radius = 0.58
	bm.height = 0.42
	bm.radial_segments = 20
	base.mesh = bm
	base.material_override = M.block(Color(0.11, 0.12, 0.17), 0.4)
	cannon_pivot.add_child(base)

	# 炮管：沿 -Z 伸出，炮口正好在 cannon 位置上（子弹就从这里出现）
	var barrel := MeshInstance3D.new()
	var brm := CylinderMesh.new()
	brm.top_radius = 0.17
	brm.bottom_radius = 0.22
	brm.height = 1.5
	brm.radial_segments = 16
	barrel.mesh = brm
	barrel.rotation = Vector3(deg_to_rad(-90.0), 0, 0)
	barrel.position = Vector3(0, 0.05, 0.75)
	barrel.material_override = M.block(Color(0.13, 0.145, 0.20), 0.35)
	cannon_pivot.add_child(barrel)

	# 炮口环
	var muzzle := MeshInstance3D.new()
	var mm := TorusMesh.new()
	mm.inner_radius = 0.14
	mm.outer_radius = 0.24
	mm.rings = 16
	mm.ring_segments = 12
	muzzle.mesh = mm
	muzzle.position = Vector3(0, 0.05, -0.02)
	muzzle.material_override = M.glow(Color("35e0ff"), 3.0)
	cannon_pivot.add_child(muzzle)


## 墙脚 / 墙顶的发光灯带，纯装饰
func _build_strips() -> void:
	var size: Vector3 = level["size"]
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var mat := M.glow(Color(0.10, 0.55, 0.85), 1.6)
	var t := 0.05
	for y in [0.06, size.y - 0.06]:
		_box(Vector3(0, y, -hz + t * 0.5), Vector3(size.x, t, t), mat)
		_box(Vector3(0, y, hz - t * 0.5), Vector3(size.x, t, t), mat)
		_box(Vector3(-hx + t * 0.5, y, 0), Vector3(t, t, size.z), mat)
		_box(Vector3(hx - t * 0.5, y, 0), Vector3(t, t, size.z), mat)
	for x in [-hx + t * 0.5, hx - t * 0.5]:
		for z in [-hz + t * 0.5, hz - t * 0.5]:
			_box(Vector3(x, size.y * 0.5, z), Vector3(t, size.y, t), mat)


func targets_of_color(color_index: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for r in target_roots:
		if int(r.get_meta("color_index", -1)) == color_index:
			out.append(r)
	return out


## 每帧轻微旋转 + 呼吸，让目标看起来是"活的"
func animate_targets(delta: float, t: float) -> void:
	for i in target_roots.size():
		var r := target_roots[i]
		if not is_instance_valid(r) or not r.visible:
			continue
		r.rotate_y(delta * 0.8)
		var k := 1.0 + 0.05 * sin(t * 2.4 + i * 1.7)
		r.scale = Vector3(k, k, k)
