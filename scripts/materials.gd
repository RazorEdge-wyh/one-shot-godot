extends RefCounted
## 材质工厂。全部是程序化材质 / 着色器，不需要任何贴图文件。

const B := preload("res://scripts/ballistics.gd")

const GRID_SHADER := preload("res://shaders/grid.gdshader")
const TRAIL_SHADER := preload("res://shaders/trail.gdshader")
const HALO_SHADER := preload("res://shaders/halo.gdshader")

static var _cache := {}


static func grid(tint: Color, grid_size: float, energy: float, base := Color(0.030, 0.038, 0.062)) -> ShaderMaterial:
	var key := "grid_%s_%s_%s" % [tint, grid_size, energy]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = GRID_SHADER
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("line_color", Color(0.16, 0.62, 0.85))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("grid_size", grid_size)
	m.set_shader_parameter("emission_energy", energy)
	_cache[key] = m
	return m


static func trail() -> ShaderMaterial:
	if _cache.has("trail"):
		return _cache["trail"]
	var m := ShaderMaterial.new()
	m.shader = TRAIL_SHADER
	_cache["trail"] = m
	return m


static func halo(color: Color, strength := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = HALO_SHADER
	m.set_shader_parameter("halo_color", color)
	m.set_shader_parameter("strength", strength)
	return m


## 实心发光材质（目标核心、子弹、灯带）
static func glow(color: Color, energy := 2.2, albedo := Color(0.02, 0.02, 0.03)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = 0.0
	m.roughness = 0.35
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


## 方块材质：同样用网格着色器，但色调更冷、更暗，和外壳区分开
static func block(color := Color(0.055, 0.075, 0.11), energy := 0.42) -> ShaderMaterial:
	var key := "block_%s_%s" % [color, energy]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = GRID_SHADER
	m.set_shader_parameter("base_color", color)
	m.set_shader_parameter("line_color", Color(0.20, 0.72, 0.95))
	m.set_shader_parameter("tint", Color(1.0, 1.0, 1.0))
	m.set_shader_parameter("grid_size", 1.0)
	m.set_shader_parameter("emission_energy", energy)
	m.set_shader_parameter("panel_variation", 0.22)
	_cache[key] = m
	return m
