extends Node
## 音效播放（素材：Kenney 免费音效包，CC0）。带一个混响总线，反弹声才有太空舱的回声。

const FILES := {
	"shot": ["shot_1.ogg", "shot_2.ogg", "shot_3.ogg"],
	"ricochet": ["ricochet_1.ogg", "ricochet_2.ogg", "ricochet_3.ogg", "ricochet_4.ogg"],
	"block": ["block_1.ogg", "block_2.ogg"],
	"break": ["break_1.ogg", "break_2.ogg", "break_3.ogg", "break_4.ogg"],
	"fail": ["fail.ogg"],
	"win": ["jingle_win.ogg"],
	"lose": ["jingle_fail.ogg"],
	"ui": ["ui_click.ogg"],
	"hover": ["ui_hover.ogg"],
	"confirm": ["ui_confirm.ogg"],
	"pep": ["pep_1.ogg", "pep_2.ogg"],
}

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _pos_pool: Array[AudioStreamPlayer3D] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_setup_buses()
	for key in FILES:
		var arr: Array = []
		for f in FILES[key]:
			var path: String = "res://assets/sounds/" + str(f)
			if ResourceLoader.exists(path):
				arr.append(load(path))
		if arr.size() > 0:
			_streams[key] = arr
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	for i in 6:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "SFX"
		p3.unit_size = 6.0
		p3.max_distance = 60.0
		add_child(p3)
		_pos_pool.append(p3)


func _setup_buses() -> void:
	if AudioServer.get_bus_index("SFX") != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, "SFX")
	AudioServer.set_bus_send(idx, "Master")
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.72
	rev.damping = 0.55
	rev.wet = 0.32
	rev.dry = 0.92
	rev.spread = 0.7
	AudioServer.add_bus_effect(idx, rev)


func _pick(key: String) -> AudioStream:
	if not _streams.has(key):
		return null
	var arr: Array = _streams[key]
	return arr[_rng.randi_range(0, arr.size() - 1)]


func play(key: String, volume_db := 0.0, pitch := 1.0, pitch_var := 0.06) -> void:
	var s := _pick(key)
	if s == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = s
			p.volume_db = volume_db
			p.pitch_scale = pitch * _rng.randf_range(1.0 - pitch_var, 1.0 + pitch_var)
			p.play()
			return
	# 全忙就抢第一个
	_pool[0].stream = s
	_pool[0].volume_db = volume_db
	_pool[0].play()


func play_at(key: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var s := _pick(key)
	if s == null:
		return
	for p in _pos_pool:
		if not p.playing:
			p.stream = s
			p.global_position = pos
			p.volume_db = volume_db
			p.pitch_scale = pitch * _rng.randf_range(0.94, 1.08)
			p.play()
			return
	_pos_pool[0].stream = s
	_pos_pool[0].global_position = pos
	_pos_pool[0].volume_db = volume_db
	_pos_pool[0].play()
