class_name Qr
## Minimal QR encoder: byte mode, ECC level L, mask 0, versions 1-4
## (up to 78 bytes — plenty for a LAN join URL). The algorithm was verified
## against OpenCV's QR decoder before being ported here.

const _VER_TOTAL := {1: 26, 2: 44, 3: 70, 4: 100}
const _VER_DATA := {1: 19, 2: 34, 3: 55, 4: 80}
const _VER_CAP := {1: 17, 2: 32, 3: 53, 4: 78}
const _VER_ALIGN := {1: 0, 2: 18, 3: 22, 4: 26}

static var _exp := PackedInt32Array()
static var _log := PackedInt32Array()


## Returns a black/white Image, one pixel per module plus a 4-module quiet
## zone. Scale it up with nearest-neighbor filtering for display.
static func make_image(text: String) -> Image:
	var m := _make_matrix(text)
	var size := m.size()
	var quiet := 4
	var dim := size + quiet * 2
	var img := Image.create_empty(dim, dim, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	for r in size:
		for c in size:
			if m[r][c] == 1:
				img.set_pixel(c + quiet, r + quiet, Color.BLACK)
	return img


static func _gf_init() -> void:
	if not _exp.is_empty():
		return
	_exp.resize(512)
	_log.resize(256)
	var x := 1
	for i in 255:
		_exp[i] = x
		_log[x] = i
		x <<= 1
		if x & 0x100:
			x ^= 0x11D
	for i in range(255, 512):
		_exp[i] = _exp[i - 255]


static func _gf_mul(a: int, b: int) -> int:
	if a == 0 or b == 0:
		return 0
	return _exp[_log[a] + _log[b]]


static func _rs_ecc(data: PackedInt32Array, n_ecc: int) -> PackedInt32Array:
	_gf_init()
	var gen := PackedInt32Array([1])
	for i in n_ecc:
		var next := PackedInt32Array()
		next.resize(gen.size() + 1)
		for j in gen.size():
			next[j] ^= gen[j]
			next[j + 1] ^= _gf_mul(gen[j], _exp[i])
		gen = next
	var rem := PackedInt32Array()
	rem.resize(data.size() + n_ecc)
	for i in data.size():
		rem[i] = data[i]
	for i in data.size():
		var f := rem[i]
		if f != 0:
			for j in range(1, gen.size()):
				rem[i + j] ^= _gf_mul(gen[j], f)
	return rem.slice(data.size())


static func _make_matrix(text: String) -> Array:
	var data := text.to_utf8_buffer()
	var ver := 0
	for v in [1, 2, 3, 4]:
		if data.size() <= int(_VER_CAP[v]):
			ver = v
			break
	assert(ver > 0, "QR payload too long")
	var data_cw_count := int(_VER_DATA[ver])
	var n_ecc := int(_VER_TOTAL[ver]) - data_cw_count

	# Bit stream: mode 0100, 8-bit count, data, terminator, byte pads.
	var bits: Array[int] = []
	_put_bits(bits, 4, 4)
	_put_bits(bits, data.size(), 8)
	for b in data:
		_put_bits(bits, b, 8)
	_put_bits(bits, 0, mini(4, data_cw_count * 8 - bits.size()))
	while bits.size() % 8 != 0:
		bits.append(0)
	var cw := PackedInt32Array()
	for i in bits.size() / 8:
		var w := 0
		for k in 8:
			w = (w << 1) | bits[i * 8 + k]
		cw.append(w)
	var pad := [0xEC, 0x11]
	var pi := 0
	while cw.size() < data_cw_count:
		cw.append(pad[pi % 2])
		pi += 1
	cw.append_array(_rs_ecc(cw, n_ecc))

	var size := 21 + 4 * (ver - 1)
	var m: Array = []
	for r in size:
		var row := PackedInt32Array()
		row.resize(size)
		row.fill(-1)
		m.append(row)

	_finder(m, 0, 0, size)
	_finder(m, 0, size - 7, size)
	_finder(m, size - 7, 0, size)
	for i in range(8, size - 8):
		var v := 1 if i % 2 == 0 else 0
		m[6][i] = v
		m[i][6] = v
	var a := int(_VER_ALIGN[ver])
	if a > 0:
		for r in range(-2, 3):
			for c in range(-2, 3):
				m[a + r][a + c] = 1 if maxi(absi(r), absi(c)) != 1 else 0
	m[4 * ver + 9][8] = 1
	for i in 9:
		if m[8][i] == -1:
			m[8][i] = 0
		if m[i][8] == -1:
			m[i][8] = 0
	for i in 8:
		if m[8][size - 1 - i] == -1:
			m[8][size - 1 - i] = 0
		if m[size - 1 - i][8] == -1:
			m[size - 1 - i][8] = 0

	var is_func: Array = []
	for r in size:
		var row := PackedByteArray()
		row.resize(size)
		for c in size:
			row[c] = 1 if m[r][c] != -1 else 0
		is_func.append(row)

	# Zigzag data placement with mask 0.
	var stream: Array[int] = []
	for w in cw:
		for k in range(7, -1, -1):
			stream.append((w >> k) & 1)
	var bi := 0
	var col := size - 1
	var upward := true
	while col > 0:
		if col == 6:
			col -= 1
		for step in size:
			var r := (size - 1 - step) if upward else step
			for dc in 2:
				var c := col - dc
				if is_func[r][c] == 1:
					continue
				var b := stream[bi] if bi < stream.size() else 0
				bi += 1
				if (r + c) % 2 == 0:
					b ^= 1
				m[r][c] = b
		upward = not upward
		col -= 2

	# Format info for (L, mask 0).
	var data5 := (0b01 << 3) | 0
	var rem := data5 << 10
	for i in range(14, 9, -1):
		if (rem >> i) & 1:
			rem ^= 0x537 << (i - 10)
	var fmt := ((data5 << 10) | (rem & 0x3FF)) ^ 0x5412
	var coords_a := [[8, 0], [8, 1], [8, 2], [8, 3], [8, 4], [8, 5], [8, 7], [8, 8],
		[7, 8], [5, 8], [4, 8], [3, 8], [2, 8], [1, 8], [0, 8]]
	var coords_b := [[size - 1, 8], [size - 2, 8], [size - 3, 8], [size - 4, 8],
		[size - 5, 8], [size - 6, 8], [size - 7, 8],
		[8, size - 8], [8, size - 7], [8, size - 6], [8, size - 5],
		[8, size - 4], [8, size - 3], [8, size - 2], [8, size - 1]]
	for i in 15:
		var bit := (fmt >> (14 - i)) & 1
		m[coords_a[i][0]][coords_a[i][1]] = bit
		m[coords_b[i][0]][coords_b[i][1]] = bit
	return m


static func _finder(m: Array, r0: int, c0: int, size: int) -> void:
	for r in range(-1, 8):
		for c in range(-1, 8):
			var rr := r0 + r
			var cc := c0 + c
			if rr < 0 or rr >= size or cc < 0 or cc >= size:
				continue
			var inside := r >= 0 and r <= 6 and c >= 0 and c <= 6
			if inside and (r == 0 or r == 6 or c == 0 or c == 6 \
					or (r >= 2 and r <= 4 and c >= 2 and c <= 4)):
				m[rr][cc] = 1
			else:
				m[rr][cc] = 0


static func _put_bits(bits: Array[int], val: int, n: int) -> void:
	for i in range(n - 1, -1, -1):
		bits.append((val >> i) & 1)
