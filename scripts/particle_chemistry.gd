extends RefCounted
## The finite visual sample is not a second physical simulation.
## A=3 groups tritium/helium-3; A=7 groups lithium-7/beryllium-7.
## Charge below belongs to these visual representatives, not isotope accounting.

enum K { QR, QG, QB, P, N, D, HE3, HE4, LI7, E, H, HE }
const KIND_COUNT := 12
const CHARGE := [0, 0, 0, 1, 0, 1, 2, 2, 3, -1, 0, 0]
const BARYON := [1, 1, 1, 3, 3, 6, 9, 12, 21, 0, 3, 12] # thirds of a baryon

# Inputs, outputs. Negative events reverse the same rule, including exchanges.
const RULES := {
	"pn_D": [[K.P, K.N], [K.D]],
	"Dp": [[K.D, K.P], [K.HE3]],
	"Dn": [[K.D, K.N], [K.HE3]],
	"He3n": [[K.HE3, K.N], [K.HE3, K.P]],
	"DDn": [[K.D, K.D], [K.HE3, K.N]],
	"DDp": [[K.D, K.D], [K.HE3, K.P]],
	"A3Dn": [[K.HE3, K.D], [K.HE4, K.N]],
	"A3Dp": [[K.HE3, K.D], [K.HE4, K.P]],
	"A3n": [[K.HE3, K.N], [K.HE4]],
	"A3p": [[K.HE3, K.P], [K.HE4]],
	"Li": [[K.HE4, K.HE3], [K.LI7]],
	"He_melt": [[K.HE4], [K.P, K.P, K.N, K.N]],
	"A3_melt": [[K.HE3], [K.P, K.P, K.N]],
	"Li_melt": [[K.LI7], [K.P, K.P, K.P, K.N, K.N, K.N, K.N]],
	"Be7n": [[K.LI7, K.N], [K.LI7, K.P]],
	"Be7n_He": [[K.LI7, K.N], [K.HE4, K.HE4]],
	"Li7p_He": [[K.LI7, K.P], [K.HE4, K.HE4]],
	"He3He3": [[K.HE3, K.HE3], [K.HE4, K.P, K.P]],
	"Li7D": [[K.LI7, K.D], [K.HE4, K.HE4, K.N]],
	"Be7D": [[K.LI7, K.D], [K.HE4, K.HE4, K.P]],
	"T_melt": [[K.HE3], [K.P, K.N, K.N]],
	"Be_melt": [[K.LI7], [K.P, K.P, K.P, K.P, K.N, K.N, K.N]],
	"recH": [[K.P, K.E], [K.H]],
	"recHe": [[K.HE4, K.E, K.E], [K.HE]],
}


static func rule(channel: String, direction: int) -> Array:
	if direction not in [-1, 1] or not RULES.has(channel):
		return []
	var pair: Array = RULES[channel]
	return pair if direction > 0 else [pair[1], pair[0]]


## Deterministic apportionment: nuclei are rounded down, remaining baryons go
## to free nucleons. Every sample has exactly `baryons` baryons, including quarks.
## A species below one display particle is represented by the numeric HUD only.
static func sample(u, baryons: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(KIND_COUNT)
	baryons = maxi(0, baryons)
	var nucleons := clampi(roundi(clampf(u.hadron, 0.0, 1.0) * baryons), 0, baryons)
	for k in [K.QR, K.QG, K.QB]:
		out[k] = baryons - nucleons
	var remaining := nucleons
	for item in [[K.LI7, u.Y7, 7], [K.HE4, u.Y4, 4], [K.HE3, u.Y3, 3], [K.D, u.YD, 2]]:
		var count := mini(floori(maxf(item[1], 0.0) * nucleons), remaining / int(item[2]))
		out[item[0]] = count
		remaining -= count * int(item[2])
	out[K.N] = clampi(roundi(maxf(u.Yn, 0.0) * nucleons), 0, remaining)
	out[K.P] = remaining - out[K.N]
	out[K.H] = clampi(roundi((1.0 - u.xH) * out[K.P]), 0, out[K.P])
	out[K.P] -= out[K.H]
	out[K.HE] = clampi(roundi((1.0 - u.xHe) * out[K.HE4]), 0, out[K.HE4])
	out[K.HE4] -= out[K.HE]
	# Electrons exist in the sample even when the visual layer hides them at high T.
	# This makes reheating/ionization and density changes charge-balanced on screen.
	for k in KIND_COUNT:
		if k != K.E:
			out[K.E] += out[k] * CHARGE[k]
	return out
