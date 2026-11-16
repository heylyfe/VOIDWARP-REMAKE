class_name VoidRng
extends RefCounted

## Mulberry32-style RNG plus the 32-bit mixing helpers.
## Line-by-line port of terrain_ref/voidgen.py: mul32, fmix, mix and class Rng.
## Draw order and draw counts are part of the determinism contract (TERRAIN_SPEC section 3).
## Python's self.range(n) is named urange(n) here so it cannot shadow the global range().

const M32 := 0xFFFFFFFF


static func mul32(a: int, b: int) -> int:
	return ((a & 0xFFFF) * b + ((((a >> 16) * b) & 0xFFFF) << 16)) & M32


static func fmix(x: int) -> int:
	var z: int = x
	z ^= z >> 16
	z = mul32(z, 0x85EBCA6B)
	z ^= z >> 13
	z = mul32(z, 0xC2B2AE35)
	z ^= z >> 16
	return z


static func mix(a: int, b: int) -> int:
	return fmix((a ^ mul32((b + 0x9E3779B9) & M32, 0x01000193)) & M32)


var s: int


func _init(p_seed: int) -> void:
	s = p_seed & M32


func u32() -> int:
	s = (s + 0x6D2B79F5) & M32
	var z: int = s
	z = mul32(z ^ (z >> 15), z | 1)
	z ^= (z + mul32(z ^ (z >> 7), z | 61)) & M32
	return (z ^ (z >> 14)) & M32


## uniform int in [0, n). n must be 1..2^20 (Python reference contract).
func urange(n: int) -> int:
	return (u32() * n) >> 32


## uniform int in [a, b] inclusive. If b < a returns a WITHOUT drawing.
func ri(a: int, b: int) -> int:
	if b <= a:
		return a
	return a + urange(b - a + 1)


func chance(num: int, den: int) -> bool:
	return urange(den) < num


func pick(seq: Array) -> Variant:
	return seq[urange(seq.size())]


## names: sequence, weights: parallel ints >= 0. Total must be > 0.
func wpick(names: Array, weights: Array) -> Variant:
	var tot := 0
	for w in weights:
		tot += w
	var r := urange(tot)
	for i in range(names.size()):
		r -= weights[i]
		if r < 0:
			return names[i]
	return names[names.size() - 1]


func shuffle(lst: Array) -> void:
	var i: int = lst.size() - 1
	while i > 0:
		var j: int = urange(i + 1)
		var tmp: Variant = lst[i]
		lst[i] = lst[j]
		lst[j] = tmp
		i -= 1
