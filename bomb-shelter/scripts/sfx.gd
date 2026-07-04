class_name Sfx
extends Node
## Procedural sound effects — the WAVs are synthesized in code at startup so
## the project stays asset-free. Other nodes trigger sounds via
## get_tree().call_group(&"sfx", ...), same pattern as camera trauma.

const RATE := 22050
const MAX_VOICES := 12

var _booms: Array[AudioStreamWAV] = []
var _splat: AudioStreamWAV
var _jump_s: AudioStreamWAV
var _step_s: AudioStreamWAV
var _pickup_s: AudioStreamWAV
var _clank_s: AudioStreamWAV
var _tick_s: AudioStreamWAV
var _snap_s: AudioStreamWAV
var _fanfare_s: AudioStreamWAV
var _womp_s: AudioStreamWAV


func _ready() -> void:
	add_to_group(&"sfx")
	# One voice per Bomb.Type: NORMAL, BIG, CLUSTER, BOUNCY.
	_booms = [
		_make_boom(20260703, 0.9, 95.0, 28.0, 5.5, 3.5, 0.002, 0.0),
		_make_boom(11223344, 1.4, 70.0, 20.0, 3.2, 2.0, 0.0025, 0.0),
		_make_boom(55667788, 0.55, 160.0, 45.0, 9.0, 6.0, 0.009, 0.0),
		_make_boom(99001122, 0.85, 110.0, 35.0, 6.0, 4.0, 0.001, 230.0),
	]
	_splat = _make_splat()
	_jump_s = _make_jump()
	_step_s = _make_step()
	_pickup_s = _make_pickup()
	_clank_s = _make_clank()
	_tick_s = _make_tick()
	_snap_s = _make_snap()
	_fanfare_s = _make_fanfare()
	_womp_s = _make_womp()


## size_mult ~0.5 (bomblet) .. ~4 (big bomb at max blast scale);
## type indexes Bomb.Type so each kind has its own voice.
func play_explosion(pos: Vector2, size_mult: float, type := 0) -> void:
	var vol := clampf(-10.0 + size_mult * 5.0, -14.0, 2.0)
	var pitch := randf_range(0.9, 1.1) / clampf(size_mult, 0.55, 1.7)
	_play(_booms[clampi(type, 0, _booms.size() - 1)], vol, pitch)


func play_splat(_pos: Vector2) -> void:
	_play(_splat, -2.0, randf_range(0.85, 1.25))


func play_jump(_pos: Vector2) -> void:
	_play(_jump_s, -11.0, randf_range(0.95, 1.15))


## Kick: the jump chirp slowed way down reads as a heavy whoosh/thock.
func play_kick(_pos: Vector2) -> void:
	_play(_jump_s, -6.0, randf_range(0.58, 0.72))


## Small, subtle dirt crunch each time a foot plants; a slowed, louder
## variant doubles as the landing thud.
func play_step(_pos: Vector2) -> void:
	_play(_step_s, -22.0, randf_range(0.9, 1.2))


func play_land(_pos: Vector2) -> void:
	_play(_step_s, -13.0, randf_range(0.55, 0.75))


func play_pickup(_pos: Vector2) -> void:
	_play(_pickup_s, -8.0, randf_range(0.98, 1.05))


func play_armor_break(_pos: Vector2) -> void:
	_play(_clank_s, -4.0, randf_range(0.9, 1.05))


## Accelerating countdown blip in a bomb's final 1.5 seconds. Low priority:
## skipped when the mixer is busy so booms always win.
func play_tick(_pos: Vector2) -> void:
	if get_child_count() >= 10:
		return
	_play(_tick_s, -16.0, randf_range(0.97, 1.03))


## The crack of a blast lighting another bomb's fuse.
func play_snap(_pos: Vector2) -> void:
	_play(_snap_s, -9.0, randf_range(0.9, 1.15))


func play_fanfare(_pos: Vector2) -> void:
	_play(_fanfare_s, -5.0, 1.0)


func play_womp(_pos: Vector2) -> void:
	_play(_womp_s, -5.0, 1.0)


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
## f_hi→f_lo is the sub sweep; noise/sub decay shape the body; crackle sets
## the density of debris pops; boing_hz > 0 adds a wobbling springy overtone
## (the bouncy bomb's rubbery voice).
func _make_boom(sd: int, dur: float, f_hi: float, f_lo: float,
		noise_decay: float, sub_decay: float, crackle: float,
		boing_hz: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var brown := 0.0
	var phase := 0.0
	var boing_phase := 0.0
	for i in n:
		var t := float(i) / RATE
		brown = clampf((brown + rng.randf_range(-1.0, 1.0) * 0.35) * 0.985, -1.0, 1.0)
		var freq := lerpf(f_hi, f_lo, minf(t * 2.0, 1.0))
		phase += TAU * freq / RATE
		var s := brown * 1.15 * exp(-t * noise_decay) + sin(phase) * 0.9 * exp(-t * sub_decay)
		if boing_hz > 0.0:
			boing_phase += TAU * boing_hz * (1.0 + 0.25 * sin(TAU * 7.0 * t)) / RATE
			s += sin(boing_phase) * 0.45 * exp(-t * 4.5)
		if rng.randf() < crackle * exp(-t * 2.0):
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


## Hop: quick rising sine chirp with a whisper of noise.
func _make_jump() -> AudioStreamWAV:
	var n := int(RATE * 0.18)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var freq := lerpf(170.0, 430.0, minf(t * 7.0, 1.0))
		phase += TAU * freq / RATE
		var s := sin(phase) * 0.7 * exp(-t * 14.0) \
			+ rng.randf_range(-1.0, 1.0) * 0.12 * exp(-t * 26.0)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	return _wav(data)


## Footstep: granular dirt crunch — a dense cluster of micro-pops (impact)
## thinning into a short grind, with low body and high grit.
func _make_step() -> AudioStreamWAV:
	var n := int(RATE * 0.08)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var raw := rng.randf_range(-0.18, 0.18) * exp(-t * 55.0)
		var density := 0.28 * exp(-t * 40.0)
		if rng.randf() < density:
			var amp := rng.randf_range(0.35, 0.75)
			raw += amp if rng.randf() < 0.5 else -amp
		lp += (raw - lp) * 0.45
		var grit := raw - lp
		var s := (lp * 0.85 + grit * 0.65) * exp(-t * 22.0)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	return _wav(data)


## Armor pickup: a bright two-note chime (C6 then G6).
func _make_pickup() -> AudioStreamWAV:
	var n := int(RATE * 0.32)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var freq := 1046.5 if t < 0.12 else 1568.0
		phase += TAU * freq / RATE
		var env := minf(t * 60.0, 1.0) * exp(-t * 7.0)
		if t >= 0.12:
			env = exp(-(t - 0.12) * 6.0)
		var s := sin(phase) * 0.55 * env + sin(phase * 2.0) * 0.12 * env
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	return _wav(data)


## Armor break: metallic clank — detuned partials plus a noise crack.
func _make_clank() -> AudioStreamWAV:
	var n := int(RATE * 0.35)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 909090
	var p1 := 0.0
	var p2 := 0.0
	var p3 := 0.0
	for i in n:
		var t := float(i) / RATE
		p1 += TAU * 812.0 / RATE
		p2 += TAU * 1087.0 / RATE
		p3 += TAU * 1372.0 / RATE
		var s := (sin(p1) * 0.4 + sin(p2) * 0.3 + sin(p3) * 0.2) * exp(-t * 9.0)
		s += rng.randf_range(-1.0, 1.0) * 0.5 * exp(-t * 40.0)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	return _wav(data)


## Countdown blip: a 40 ms high sine ping.
func _make_tick() -> AudioStreamWAV:
	var n := int(RATE * 0.04)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * 2100.0 / RATE
		var s := sin(phase) * minf(t * 400.0, 1.0) * exp(-t * 80.0) * 0.8
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	return _wav(data)


## Chain-ignite: a short electric crack.
func _make_snap() -> AudioStreamWAV:
	var n := int(RATE * 0.07)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 616161
	var prev := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		phase += TAU * 950.0 / RATE
		var s := (noise - prev) * 0.9 * exp(-t * 110.0) + sin(phase) * 0.3 * exp(-t * 50.0)
		prev = noise
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	return _wav(data)


## Win fanfare: rising C-E-G-C arpeggio with a sustained final note.
func _make_fanfare() -> AudioStreamWAV:
	var notes: Array[float] = [523.25, 659.25, 784.0, 1046.5]
	var starts: Array[float] = [0.0, 0.16, 0.32, 0.48]
	var n := int(RATE * 1.1)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var idx := 0
		for k in starts.size():
			if t >= starts[k]:
				idx = k
		var since := t - starts[idx]
		var last := idx == notes.size() - 1
		phase += TAU * notes[idx] / RATE
		var env := minf(since * 250.0, 1.0) * exp(-since * (3.0 if last else 9.0))
		var s := (sin(phase) + 0.25 * sin(phase * 2.0) + 0.12 * sin(phase * 3.0)) * 0.45 * env
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	return _wav(data)


## Draw: two sad descending notes.
func _make_womp() -> AudioStreamWAV:
	var n := int(RATE * 0.7)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var freq := 349.23 if t < 0.3 else 233.08
		freq *= 1.0 + 0.015 * sin(TAU * 5.5 * t)
		phase += TAU * freq / RATE
		var since := t if t < 0.3 else t - 0.3
		var env := minf(since * 200.0, 1.0) * exp(-since * 6.0)
		var s := (sin(phase) + 0.2 * sin(phase * 2.0)) * 0.5 * env
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	return _wav(data)


func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
