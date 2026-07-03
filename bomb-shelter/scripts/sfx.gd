class_name Sfx
extends Node
## Procedural sound effects — the WAVs are synthesized in code at startup so
## the project stays asset-free. Other nodes trigger sounds via
## get_tree().call_group(&"sfx", ...), same pattern as camera trauma.

const RATE := 22050
const MAX_VOICES := 12

var _explosion: AudioStreamWAV
var _splat: AudioStreamWAV


func _ready() -> void:
	add_to_group(&"sfx")
	_explosion = _make_explosion()
	_splat = _make_splat()


## size_mult ~0.5 (bomblet) .. ~4 (big bomb at max blast scale).
func play_explosion(pos: Vector2, size_mult: float) -> void:
	var vol := clampf(-10.0 + size_mult * 5.0, -14.0, 2.0)
	var pitch := randf_range(0.9, 1.1) / clampf(size_mult, 0.55, 1.7)
	_play(_explosion, vol, pitch)


func play_splat(_pos: Vector2) -> void:
	_play(_splat, -2.0, randf_range(0.85, 1.25))


func _play(stream: AudioStreamWAV, vol_db: float, pitch: float) -> void:
	if get_child_count() >= MAX_VOICES:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol_db
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# ---------------------------------------------------------------- synthesis ---

## Boom: brown-noise burst + sub-bass sine sweep + sparse crackle tail.
func _make_explosion() -> AudioStreamWAV:
	var n := int(RATE * 0.9)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260703
	var brown := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		brown = clampf((brown + rng.randf_range(-1.0, 1.0) * 0.35) * 0.985, -1.0, 1.0)
		var freq := lerpf(95.0, 28.0, minf(t * 2.0, 1.0))
		phase += TAU * freq / RATE
		var s := brown * 1.15 * exp(-t * 5.5) + sin(phase) * 0.9 * exp(-t * 3.5)
		if rng.randf() < 0.002 * exp(-t * 2.0):
			s += rng.randf_range(-0.8, 0.8)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	return _wav(data)


## Splat: low-pass-swept noise with a double-hit envelope + descending gloop.
func _make_splat() -> AudioStreamWAV:
	var n := int(RATE * 0.4)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 16.0)
		if t > 0.07:
			env += 0.55 * exp(-(t - 0.07) * 30.0)
		var cutoff := lerpf(0.85, 0.12, minf(t * 6.0, 1.0))
		lp += (rng.randf_range(-1.0, 1.0) - lp) * cutoff
		var freq := lerpf(320.0, 70.0, minf(t * 5.0, 1.0))
		phase += TAU * freq / RATE
		var gloop := sin(phase) * 0.6 * exp(-t * 12.0)
		var s := clampf(lp * 1.7 * env + gloop, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 32000.0))
	return _wav(data)


func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
