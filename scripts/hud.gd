extends CanvasLayer
## 全部用代码搭 UI。标题用 Kenney Future（CC0 字体），正文用系统中文字体，
## 二者用 fallback 串起来，所以拉丁字母是科幻字、中文也能正常显示。

const B := preload("res://scripts/ballistics.gd")
const COL_TITLE := Color("bfe9ff")
const COL_DIM := Color(0.78, 0.88, 0.95, 0.92)

var font_title: Font
var font_body: Font

var play_root: Control
var lbl_level: Label
var lbl_tip: Label
var lbl_status: Label
var lbl_controls: Label
var lbl_focus: Label
var lbl_color_name: Label
var color_pips: Array[Panel] = []
var target_pips: Array[Panel] = []
var focus_fill: Panel
var overlay: Control
var ov_title: Label
var ov_sub: Label
var ov_hint: Label
var reticle: Panel
var _tip_timer := 0.0


func _ready() -> void:
	layer = 10
	font_title = _make_font(true)
	font_body = _make_font(false)
	_build()


func _make_font(prefer_display: bool) -> Font:
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "PingFang SC", "sans-serif"])
	sys.allow_system_fallback = true
	sys.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	if prefer_display and ResourceLoader.exists("res://assets/fonts/KenneyFuture.ttf"):
		var kf: Font = load("res://assets/fonts/KenneyFuture.ttf")
		kf.fallbacks = [sys]
		return kf
	return sys


func _label(text: String, size: int, font: Font, color := Color(1, 1, 1, 1)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 2)
	return l


func _pip(color: Color, size := 20) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(size, size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(size * 0.5))
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.65)
	sb.shadow_color = Color(color.r, color.g, color.b, 0.5)
	sb.shadow_size = 8
	p.add_theme_stylebox_override("panel", sb)
	return p


func _panel_bg(color: Color, radius := 14, pad := 12) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	sb.border_width_bottom = 1
	sb.border_color = Color(0.4, 0.8, 1.0, 0.18)
	pc.add_theme_stylebox_override("panel", sb)
	return pc


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	play_root = Control.new()
	play_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	play_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(play_root)

	# ---------------- 左上：关卡名 + 提示 ----------------
	var tl := VBoxContainer.new()
	tl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tl.position = Vector2(30, 20)
	tl.add_theme_constant_override("separation", 4)
	play_root.add_child(tl)
	lbl_level = _label("", 38, font_title, COL_TITLE)
	tl.add_child(lbl_level)
	lbl_tip = _label("", 17, font_body, COL_DIM)
	lbl_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_tip.custom_minimum_size = Vector2(570, 0)
	tl.add_child(lbl_tip)
	lbl_status = _label("", 17, font_body, Color(1.0, 0.82, 0.35, 0.95))
	tl.add_child(lbl_status)

	# ---------------- 右上：目标清单 ----------------
	var tr := VBoxContainer.new()
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.position = Vector2(-300, 22)
	tr.custom_minimum_size = Vector2(270, 0)
	tr.add_theme_constant_override("separation", 2)
	play_root.add_child(tr)
	var tl2 := _label("剩余目标", 15, font_body, Color(0.7, 0.8, 0.9, 0.75))
	tl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tl2.custom_minimum_size = Vector2(270, 0)
	tr.add_child(tl2)
	var th := HBoxContainer.new()
	th.alignment = BoxContainer.ALIGNMENT_END
	th.add_theme_constant_override("separation", 6)
	tr.add_child(th)
	for i in 8:
		var p := _pip(Color(0.3, 0.3, 0.35))
		p.visible = false
		th.add_child(p)
		target_pips.append(p)

	# ---------------- 下方中间：颜色循环 ----------------
	var bc := HBoxContainer.new()
	bc.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bc.position = Vector2(-215, -132)
	bc.custom_minimum_size = Vector2(430, 74)
	bc.add_theme_constant_override("separation", 16)
	bc.alignment = BoxContainer.ALIGNMENT_CENTER
	var bg := _panel_bg(Color(0.02, 0.04, 0.07, 0.55), 16, 14)
	play_root.add_child(bg)
	bg.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bg.position = Vector2(-230, -146)
	bg.custom_minimum_size = Vector2(460, 96)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(bc)
	bc.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bc.position = Vector2(0, 0)
	bc.custom_minimum_size = Vector2(420, 68)
	color_pips.clear()
	for i in B.COLOR_COUNT:
		var holder := VBoxContainer.new()
		holder.alignment = BoxContainer.ALIGNMENT_CENTER
		holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var p := _pip(B.COLOR_VALUES[i], 34)
		p.modulate = Color(1, 1, 1, 0.28)
		holder.add_child(p)
		color_pips.append(p)
		bc.add_child(holder)
	var col_txt := VBoxContainer.new()
	col_txt.add_theme_constant_override("separation", 0)
	col_txt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bc.add_child(col_txt)
	lbl_color_name = _label("", 25, font_title, Color(1, 1, 1, 0.95))
	col_txt.add_child(lbl_color_name)
	var sub := _label("当前子弹颜色", 13, font_body, Color(0.7, 0.8, 0.9, 0.6))
	col_txt.add_child(sub)

	# ---------------- 左下：操作说明 ----------------
	lbl_controls = _label("鼠标移动 = 瞄准    左键 / 空格 = 发射    按住右键 = 子弹时间    R = 重来    ESC = 释放鼠标", 14, font_body, Color(0.75, 0.85, 0.92, 0.6))
	lbl_controls.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	lbl_controls.position = Vector2(30, -40)
	play_root.add_child(lbl_controls)

	# ---------------- 右下：子弹时间能量 ----------------
	var br := VBoxContainer.new()
	br.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	br.position = Vector2(-270, -56)
	br.custom_minimum_size = Vector2(240, 0)
	play_root.add_child(br)
	lbl_focus = _label("子弹时间", 14, font_body, Color(0.75, 0.85, 0.92, 0.75))
	lbl_focus.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_focus.custom_minimum_size = Vector2(240, 0)
	br.add_child(lbl_focus)
	var bar_bg := Panel.new()
	bar_bg.custom_minimum_size = Vector2(240, 10)
	var sbg := StyleBoxFlat.new()
	sbg.bg_color = Color(1, 1, 1, 0.12)
	sbg.set_corner_radius_all(5)
	bar_bg.add_theme_stylebox_override("panel", sbg)
	br.add_child(bar_bg)
	focus_fill = Panel.new()
	focus_fill.size = Vector2(240, 10)
	var sbf := StyleBoxFlat.new()
	sbf.bg_color = Color("ffc63a")
	sbf.set_corner_radius_all(5)
	focus_fill.add_theme_stylebox_override("panel", sbf)
	bar_bg.add_child(focus_fill)

	# ---------------- 准星 ----------------
	reticle = _pip(Color(1, 1, 1, 0.85), 7)
	reticle.set_anchors_preset(Control.PRESET_CENTER)
	reticle.position = Vector2(-3.5, -3.5)
	play_root.add_child(reticle)

	# ---------------- 中央遮罩（标题 / 结算） ----------------
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.74)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-440, -180)
	box.custom_minimum_size = Vector2(880, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	overlay.add_child(box)
	ov_title = _label("", 66, font_title, Color("8fe8ff"))
	ov_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov_title.custom_minimum_size = Vector2(880, 0)
	box.add_child(ov_title)
	ov_sub = _label("", 21, font_body, Color(0.85, 0.92, 1.0, 0.92))
	ov_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ov_sub.custom_minimum_size = Vector2(880, 0)
	box.add_child(ov_sub)
	ov_hint = _label("", 24, font_title, Color("ffc63a"))
	ov_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov_hint.custom_minimum_size = Vector2(880, 0)
	box.add_child(ov_hint)


# ------------------------------------------------------------------ 对外接口
func set_play_visible(v: bool) -> void:
	play_root.visible = v


func setup(lv: Dictionary, target_colors: Array) -> void:
	lbl_level.text = str(lv.get("name", ""))
	lbl_tip.text = str(lv.get("tip", ""))
	lbl_tip.modulate = Color(1, 1, 1, 1)
	_tip_timer = 12.0
	for i in target_pips.size():
		var p := target_pips[i]
		if i < target_colors.size():
			p.visible = true
			_set_pip_color(p, B.COLOR_VALUES[int(target_colors[i])], true)
		else:
			p.visible = false
	set_status("")
	set_color_state(0, 0)


func _set_pip_color(p: Panel, c: Color, alive: bool) -> void:
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
	sb.bg_color = c if alive else Color(0.16, 0.17, 0.2, 0.9)
	sb.border_color = Color(1, 1, 1, 0.65) if alive else Color(1, 1, 1, 0.15)
	sb.shadow_color = Color(c.r, c.g, c.b, 0.55) if alive else Color(0, 0, 0, 0)


func mark_destroyed(index: int) -> void:
	if index >= 0 and index < target_pips.size():
		_set_pip_color(target_pips[index], Color.WHITE, false)
		target_pips[index].scale = Vector2(1.7, 1.7)


func set_color_state(color_index: int, bounces: int) -> void:
	for i in color_pips.size():
		color_pips[i].modulate = Color(1, 1, 1, 1.0 if i == color_index else 0.25)
		color_pips[i].scale = Vector2(1.25, 1.25) if i == color_index else Vector2.ONE
	lbl_color_name.text = "%s  ·  第 %d 次反弹" % [B.COLOR_NAMES[color_index], bounces]


func set_focus(f: float) -> void:
	focus_fill.size.x = 240.0 * clampf(f, 0.0, 1.0)
	lbl_focus.modulate = Color(1, 1, 1, 1.0 if f > 0.999 else 0.8)


func set_status(t: String) -> void:
	lbl_status.text = t


func set_reticle(v: bool) -> void:
	reticle.visible = v


func show_overlay(title: String, sub: String, hint: String, color := Color("8fe8ff")) -> void:
	overlay.visible = true
	ov_title.text = title
	ov_title.add_theme_color_override("font_color", color)
	ov_sub.text = sub
	ov_hint.text = hint


func hide_overlay() -> void:
	overlay.visible = false


func process_hud(delta: float) -> void:
	if _tip_timer > 0.0:
		_tip_timer -= delta
		if _tip_timer < 3.0:
			lbl_tip.modulate = Color(1, 1, 1, maxf(_tip_timer / 3.0, 0.0))
	for p in target_pips:
		p.scale = p.scale.lerp(Vector2.ONE, delta * 8.0)
	for p in color_pips:
		var want := Vector2(1.25, 1.25) if p.modulate.a > 0.9 else Vector2.ONE
		p.scale = p.scale.lerp(want, delta * 10.0)
