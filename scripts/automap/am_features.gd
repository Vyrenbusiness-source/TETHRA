class_name AmFeatures
extends RefCounted

## Musik-Analyse fuer den 4K-Auto-Mapper (docs/automap/spec.md, Abschnitt AmFeatures).
##
## Ablauf von analyze():
##   1. STFT (eigene FFT, Hann, 512/256 bei 22050 Hz) -> 20 Baender je Frame (11,6 ms).
##   2. Harmonisch/perkussiv trennen: Median ueber die Zeit (je Band) gegen Median ueber
##      die Frequenz (je Frame), weiche Masken.
##   3. Je Ebene ein eigener Anstiegs-Verlauf (Log-Fluss je Band, nur Zuwachs):
##      Kick (perkussiv < 150 Hz), Snare (perkussiv 150 Hz..5,8 kHz mit Hoehenanteil),
##      Hi-Hat/Becken (perkussiv > 5,8 kHz), Bass (harmonisch < 260 Hz),
##      Instrument/Stimme (harmonisch 260 Hz..3,5 kHz; Stimme = gleitende Tonhoehe).
##   4. Tonhoehe: Bass ueber eine zweite, lange FFT nur an den Bass-Anschlaegen
##      (10,8 Hz je Bin), Instrument/Stimme ueber die staerkste Spektrallinie.
##   5. Gehaltene Toene: harmonischer Pegel im Band des Tons bleibt nach dem Anschlag oben.
##   6. Lautheit je Frame, Abschnitte ueber Neuheit (0,5-s-Bloecke), Art/Kiai/lead je Abschnitt.
##
## Die teuren Schritte (FFT, Mediane) laufen ueber den WorkerThreadPool; mit
## params.threads = 1 laeuft alles im aufrufenden Thread.

const RATE := 22050

const KINDS: Array[String] = ["kick", "snare", "hat", "bass", "tonal", "vocal", "other"]

## Bandgrenzen in Hz (20 Baender). Gruppen unten als Band-Index.
const BAND_EDGES: Array[float] = [30.0, 65.0, 110.0, 150.0, 200.0, 260.0, 340.0, 440.0, 570.0,
		740.0, 960.0, 1250.0, 1600.0, 2100.0, 2700.0, 3500.0, 4500.0, 5800.0, 7500.0, 9500.0, 11025.0]
const B_LOW_END := 3      # Kick: Baender 0..2 (< 150 Hz)
const B_BASS_END := 5     # Bass: Baender 0..4 (< 260 Hz)
const B_MID_START := 5    # Instrument/Stimme: Baender 5..14 (260 Hz..3,5 kHz)
const B_MID_END := 15
const B_PM_START := 3     # Snare-Koerper: Baender 3..13 (150 Hz..2,7 kHz)
const B_PM_END := 14
const B_HI_START := 14    # Hi-Hat/Becken: Baender 14..19 (> 2,7 kHz)
const AGG_K := 15          # Werte je Frame aus der HPSS-Stufe

const DEFAULTS := {
	"threads": 0,                # 0 = alle Kerne, 1 = ohne Thread-Pool
	"n_fft": 512,
	"hop": 256,
	"gamma": 20.0,               # Log-Kompression je Band: log(1 + gamma * S / P95 des Bands)
	"floor_db": -36.0,            # Baender unter diesem Pegel (gegen das lauteste Band) gelten als leer
	"mask_db": -35.0,            # Verdeckung: Pegel unter dem lautesten gehaltenen Band (Zeit-Median) zaehlt nicht
	"mask_decay_db": 1.0,        # so schnell (dB je Frame) faellt die Verdeckung nach einem gehaltenen Ton
	"median_time": 9,            # Frames (ungerade), harmonisch
	"median_freq": 5,            # Baender (ungerade), perkussiv
	# Lage der Anschlagzeit gegen den Fluss-Gipfel, je Art gegen die Menschen-Maps abgestimmt
	# (docs/automap/features.md, Abschnitt Vorlauf je Art): der Gipfel liegt bei Kick/Bass 14..18 ms
	# und bei Ton/Stimme 6..10 ms spaeter als bei Snare/Hat. Ein Zurueckgehen an den Beginn des
	# Anstiegs aenderte daran nichts (fester Versatz). Frueher ein gemeinsamer Wert onset_shift_ms
	# fuer Snare/Hat/other (3, abgestimmt 6); Snare und other lagen damit 6..9 ms spaet. onset_shift_ms
	# wirkt nicht mehr.
	"shift_snare_ms": -6.5,
	"shift_hat_ms": -2.0,
	"shift_other_ms": -6.0,
	"shift_low_ms": -13.0,       # Kick/Bass
	"shift_harm_ms": -5.0,       # Instrument/Stimme
	"kick_min": 0.25,            # schwaechere Kicks (perkussive Staerke, normiert) lagen in der Messung auf Zufallsniveau
	"hold_ratio": 0.5,           # Pegel 3..5 Frames nach dem Einsatz (Zeit-Median) / Spitze: darueber ein Ton
	"min_flux": 0.6,             # kleinster Anstieg (Log-Einheiten), der als Anschlag zaehlt
	"min_gap_ms": 45.0,          # Mindestabstand zweier Anschlaege derselben Ebene
	"kick_abs": 1.2, "kick_rel": 1.3,
	"snare_abs": 1.2, "snare_rel": 1.3,
	"hat_abs": 1.0, "hat_rel": 1.3,
	"bass_abs": 1.5, "bass_rel": 1.4,
	"snare_ratio": 0.15,         # Hoehen-/Mitten-Leistung im Anschlag: darunter "other"
	"hat_ratio": 12.0,           # darueber ist es ein Becken, kein Trommel-Anschlag
	"kick_over_snare": 0.8,      # Kick schluckt gleichzeitigen Mitten-Anschlag ab diesem Verhaeltnis
	"kick_ratio": 0.3,           # Kick nur, wenn die tiefe Leistung (< 150 Hz) mind. so stark steigt wie x Mitten
	"hat_kick_ratio": 0.0001,    # Becken am Kick nur, wenn die Hoehen-Leistung mind. x Kick-Leistung steigt
	"bass_ratio": 0.3,           # Bass nur, wenn die gehaltene Leistung < 260 Hz mind. x Mitten steigt (Stimme!)
	"tonal_ratio": 0.01,         # Ton/Stimme nur, wenn die gehaltene Mitten-Leistung mind. x Bass steigt
	"vocal_min": 0.38,           # Anteil gleitender Frames, ab dem die Linie als Stimme gilt
	"glide_lo_st": 0.08, "glide_hi_st": 2.0,   # Halbtoene je Frame: "gleitet"
	"vocal_lo_hz": 120.0, "vocal_hi_hz": 1100.0,
	"mid_peak_lo_hz": 180.0, "mid_peak_hi_hz": 3000.0,
	"bass_pitch_lo_hz": 32.7, "bass_pitch_hi_hz": 261.6,
	"tonal_pitch_lo_hz": 130.8, "tonal_pitch_hi_hz": 2093.0,
	"vocal_pitch_lo_hz": 98.0, "vocal_pitch_hi_hz": 1046.5,
	"sustain_min_ms": 220.0,
	"sustain_keep": 0.35,        # Pegel-Anteil, bis zu dem ein Ton als gehalten gilt
	"sustain_max_ms": 8000.0,
	"energy_range_db": 40.0,
	"section_block_ms": 500.0,
	"section_window_s": 4.0,
	"section_min_s": 8.0,
	"section_novelty": 0.22,
	"kiai_abs": 0.5, "kiai_margin": 0.15,   # beste Variante der Messung ueber 155 Sets
	"break_max": 0.3,
	"form_track_grid": 1.0,      # ohne params.grid: Taktgitter selbst ueber AmGrid.track holen (0 = feste 2-s-Bloecke)
	"lead_drums_eps": 4.0, "lead_bass_eps": 2.5, "lead_tonal_eps": 3.0, "lead_vocal_frac": 0.6,
}


# --------------------------------------------------------------------------- FFT

class _Fft extends RefCounted:
	var m: int
	var rev: PackedInt32Array
	var wr: PackedFloat32Array
	var wi: PackedFloat32Array

	func _init(size: int) -> void:
		m = size
		var bits := 0
		while (1 << bits) < m:
			bits += 1
		rev.resize(m)
		for i in m:
			var r := 0
			for b in bits:
				if i & (1 << b):
					r |= 1 << (bits - 1 - b)
			rev[i] = r
		wr.resize(m >> 1)
		wi.resize(m >> 1)
		for k in (m >> 1):
			wr[k] = cos(TAU * k / m)
			wi[k] = -sin(TAU * k / m)

	## In-place, Eingabe steht schon in Bit-Umkehr-Reihenfolge.
	func run(re: PackedFloat32Array, im: PackedFloat32Array) -> void:
		var n := m
		var twr := wr
		var twi := wi
		var i := 0
		while i < n:
			var ar := re[i]
			var ai := im[i]
			var br := re[i + 1]
			var bi := im[i + 1]
			re[i] = ar + br
			im[i] = ai + bi
			re[i + 1] = ar - br
			im[i + 1] = ai - bi
			i += 2
		var size := 4
		while size <= n:
			var half := size >> 1
			@warning_ignore("integer_division")
			var step := n / size
			for k in half:
				var c := twr[k * step]
				var s := twi[k * step]
				var j := k
				while j < n:
					var l := j + half
					var xr := re[l]
					var xi := im[l]
					var tr := c * xr - s * xi
					var ti := c * xi + s * xr
					var ur := re[j]
					var ui := im[j]
					re[l] = ur - tr
					im[l] = ui - ti
					re[j] = ur + tr
					im[j] = ui + ti
					j += size
			size <<= 1


class _Stft extends RefCounted:
	var pad: PackedFloat32Array
	var n: int
	var hop: int
	var frames: int
	var per: int
	var win: PackedFloat32Array
	var fft: _Fft
	var pc: PackedFloat32Array
	var psn: PackedFloat32Array
	var band_lo: PackedInt32Array
	var band_hi: PackedInt32Array
	var nb: int
	var k_lo: int
	var k_hi: int
	var bin_hz: float
	var out: Array = []
	var out_pk: Array = []

	func run(ci: int) -> void:
		var f0 := ci * per
		var f1 := mini(frames, f0 + per)
		var m := n >> 1
		var re := PackedFloat32Array()
		re.resize(m)
		var im := PackedFloat32Array()
		im.resize(m)
		var pw := PackedFloat32Array()
		pw.resize(m + 1)
		pw.fill(0.0)
		var o := PackedFloat32Array()
		o.resize(maxi(f1 - f0, 0) * nb)
		var pk := PackedFloat32Array()
		pk.resize(maxi(f1 - f0, 0))
		var lpad := pad
		var lwin := win
		var lrev := fft.rev
		var lfft := fft
		var lpc := pc
		var lps := psn
		var lo := band_lo
		var hi := band_hi
		var lnb := nb
		var lhop := hop
		var klo := k_lo
		var khi := k_hi
		var kmax := hi[lnb - 1]
		for f in range(f0, f1):
			var base := f * lhop
			for k in m:
				var j := lrev[k]
				var k2 := k << 1
				re[j] = lpad[base + k2] * lwin[k2]
				im[j] = lpad[base + k2 + 1] * lwin[k2 + 1]
			lfft.run(re, im)
			for k in range(1, kmax):
				var kk := m - k
				var ar := re[k]
				var ai := im[k]
				var br := re[kk]
				var bi := -im[kk]
				var orr := ai - bi
				var oi := br - ar
				var c := lpc[k]
				var s := lps[k]
				var xr := ar + br + c * orr + s * oi
				var xi := ai + bi + c * oi - s * orr
				pw[k] = (xr * xr + xi * xi) * 0.25
			var o0 := (f - f0) * lnb
			for b in lnb:
				var acc := 0.0
				for k in range(lo[b], hi[b]):
					acc += pw[k]
				o[o0 + b] = sqrt(acc)
			var best := klo
			var bv := pw[klo]
			for k in range(klo + 1, khi):
				if pw[k] > bv:
					bv = pw[k]
					best = k
			var hz := 0.0
			if bv > 1e-7 and best > 1:
				var la := log(pw[best - 1] + 1e-12)
				var lb := log(bv + 1e-12)
				var lc := log(pw[best + 1] + 1e-12)
				var den := la - 2.0 * lb + lc
				var dlt := 0.0
				if den < -1e-9:
					dlt = clampf(0.5 * (la - lc) / den, -0.5, 0.5)
				hz = (best + dlt) * bin_hz
			pk[f - f0] = hz
		out[ci] = o
		out_pk[ci] = pk


class _Hpss extends RefCounted:
	var s: PackedFloat32Array      # Frame-major: s[f * nb + b]
	var nb: int
	var frames: int
	var per: int
	var kt: int
	var kf: int
	var gamma: float
	var floor_ref: float
	var mask: PackedFloat32Array   # je Frame: Verdeckungs-Pegel aus dem Zeit-Median
	var refs: Array = []           # je Band: P95 der Staerke
	var hb: Array = []             # je Band: Zeit-Median
	var out: Array = []

	func med_band(b: int) -> void:
		var f_n := frames
		var col := PackedFloat32Array()
		col.resize(f_n)
		var ls := s
		var lnb := nb
		for f in f_n:
			col[f] = ls[f * lnb + b]
		var h := PackedFloat32Array()
		h.resize(f_n)
		var r := kt >> 1
		for f in f_n:
			var a := maxi(0, f - r)
			var e := mini(f_n, f + r + 1)
			var w := col.slice(a, e)
			w.sort()
			h[f] = w[w.size() >> 1]
		hb[b] = h
		col.sort()
		refs[b] = maxf(col[int(0.95 * (f_n - 1))], 0.1 * col[f_n - 1])

	func agg(ci: int) -> void:
		var f0 := ci * per
		var f1 := mini(frames, f0 + per)
		var o := PackedFloat32Array()
		o.resize(maxi(f1 - f0, 0) * AGG_K)
		var lnb := nb
		var pr1 := PackedFloat32Array()
		pr1.resize(lnb)
		pr1.fill(0.0)
		var pr2 := pr1.duplicate()
		var ls := s
		var gb := PackedFloat32Array()
		gb.resize(lnb)
		var cols: Array[PackedFloat32Array] = []
		for b in lnb:
			cols.append(hb[b])
			gb[b] = gamma / maxf(float(refs[b]), floor_ref)
		var r := kf >> 1
		var wn := mini(kf, lnb)
		var fs := maxi(f0 - 2, 0)
		for f in range(fs, f1):
			var row := f * lnb
			var a_kick := 0.0
			var a_bass := 0.0
			var a_mid := 0.0
			var a_hi := 0.0
			var e_hl := 0.0
			var e_hm := 0.0
			var e_p := 0.0
			var e_tot := 0.0
			var w_pm := 0.0
			var w_hi := 0.0
			var w_lo := 0.0
			var w_hl := 0.0
			var w_hm := 0.0
			var s_l5 := 0.0
			var s_mid := 0.0
			var mk := mask[f]
			for b in lnb:
				var w0 := clampi(b - r, 0, lnb - wn)
				var w := ls.slice(row + w0, row + w0 + wn)
				w.sort()
				var pv := w[wn >> 1]
				var hv := cols[b][f]
				var sv := ls[row + b]
				var h2 := hv * hv
				var mh := h2 / (h2 + pv * pv + 1e-9)
				var lg := gb[b]
				var spv := maxf(sv * (1.0 - mh) - mk, 0.0)
				var shv := maxf(hv * mh - mk, 0.0)
				var ssv := maxf(sv - mk, 0.0)
				var lh := log(1.0 + lg * shv)
				var lp := log(1.0 + lg * spv)
				# Anschlag: Rohpegel gegen das Hoechste der zwei Frames davor (Schwankungen zaehlen nicht)
				var lr := log(1.0 + lg * ssv)
				var dr := lr - maxf(pr1[b], pr2[b])
				pr2[b] = pr1[b]
				pr1[b] = lr
				e_tot += sv * sv
				e_p += lp
				if b < B_BASS_END:
					w_hl += shv * shv
					s_l5 += ssv * ssv
					e_hl += lh
				elif b < B_MID_END:
					e_hm += lh
				if b >= B_HI_START:
					w_hi += spv * spv
				elif b >= B_PM_START:
					w_pm += spv * spv
					w_hm += shv * shv
					s_mid += ssv * ssv
				else:
					w_lo += spv * spv
				if dr > 0.0:
					if b < B_LOW_END:
						a_kick += dr
					if b < B_BASS_END:
						a_bass += dr
					if b >= B_HI_START:
						a_hi += dr
					elif b >= B_PM_START:
						a_mid += dr
			if f >= f0:
				var i := (f - f0) * AGG_K
				if f == 0:
					a_kick = 0.0
					a_bass = 0.0
					a_mid = 0.0
					a_hi = 0.0
				o[i] = a_kick
				o[i + 1] = a_bass
				o[i + 2] = a_mid
				o[i + 3] = a_hi
				o[i + 4] = e_hl
				o[i + 5] = e_hm
				o[i + 6] = e_p
				o[i + 7] = e_tot
				o[i + 8] = w_pm
				o[i + 9] = w_hi
				o[i + 10] = w_lo
				o[i + 11] = w_hl
				o[i + 12] = w_hm
				o[i + 13] = s_l5
				o[i + 14] = s_mid
		out[ci] = o


## Tonhoehe der Bass-Anschlaege: 2048 Samples, 8-fach gemittelt -> 256 Punkte, FFT (10,8 Hz/Bin).
class _BassPitch extends RefCounted:
	var pcm: PackedFloat32Array
	var rate: int
	var starts: PackedInt32Array
	var per: int
	var fft: _Fft
	var win: PackedFloat32Array
	var lo_hz: float
	var hi_hz: float
	var out: Array = []

	func run(ci: int) -> void:
		var i0 := ci * per
		var i1 := mini(starts.size(), i0 + per)
		var res := PackedFloat32Array()
		res.resize(maxi(i1 - i0, 0))
		var re := PackedFloat32Array()
		re.resize(256)
		var im := PackedFloat32Array()
		im.resize(256)
		var lp := pcm
		var n := lp.size()
		var lrev := fft.rev
		var lwin := win
		var bin := rate / 8.0 / 256.0
		var ka := maxi(2, int(floor(lo_hz / bin)))
		var kb := mini(126, int(ceil(hi_hz / bin)))
		for i in range(i0, i1):
			var s0 := starts[i]
			for k in 256:
				var a := s0 + (k << 3)
				var acc := 0.0
				if a + 8 <= n and a >= 0:
					acc = lp[a] + lp[a + 1] + lp[a + 2] + lp[a + 3] + lp[a + 4] + lp[a + 5] + lp[a + 6] + lp[a + 7]
				var j := lrev[k]
				re[j] = acc * lwin[k]
				im[j] = 0.0
			fft.run(re, im)
			var best := ka
			var bv := -1.0
			for k in range(ka, kb + 1):
				var v := re[k] * re[k] + im[k] * im[k]
				if v > bv:
					bv = v
					best = k
			var hz := 0.0
			if bv > 1e-9:
				var pa := re[best - 1] * re[best - 1] + im[best - 1] * im[best - 1]
				var pc2 := re[best + 1] * re[best + 1] + im[best + 1] * im[best + 1]
				var la := log(pa + 1e-12)
				var lb := log(bv + 1e-12)
				var lc := log(pc2 + 1e-12)
				var den := la - 2.0 * lb + lc
				var dlt := 0.0
				if den < -1e-9:
					dlt = clampf(0.5 * (la - lc) / den, -0.5, 0.5)
				hz = (best + dlt) * bin
			res[i - i0] = hz
		out[ci] = res


## Tonklassen (Chroma) fuer die Liedform: lange FFT (4096 bei 22050 Hz, 5,4 Hz je Bin), ohne Ueberlappung.
## Je Frame 12 Werte (C..H), Betrag der Bins 60 Hz..2,1 kHz auf die naechste Tonklasse summiert.
class _Chroma extends RefCounted:
	var pcm: PackedFloat32Array
	var n: int
	var frames: int
	var per: int
	var fft: _Fft
	var win: PackedFloat32Array
	var pc: PackedFloat32Array
	var psn: PackedFloat32Array
	var bin_pc: PackedInt32Array
	var k0: int
	var k1: int
	var out: Array = []

	func run(ci: int) -> void:
		var f0 := ci * per
		var f1 := mini(frames, f0 + per)
		var m := n >> 1
		var re := PackedFloat32Array()
		re.resize(m)
		var im := PackedFloat32Array()
		im.resize(m)
		var o := PackedFloat32Array()
		o.resize(maxi(f1 - f0, 0) * 12)
		o.fill(0.0)
		var lp := pcm
		var np := lp.size()
		var lrev := fft.rev
		var lwin := win
		var lpc := pc
		var lps := psn
		var lbp := bin_pc
		for f in range(f0, f1):
			var base := f * n
			for k in m:
				var j := lrev[k]
				var k2 := base + (k << 1)
				re[j] = (lp[k2] * lwin[k << 1]) if k2 < np else 0.0
				im[j] = (lp[k2 + 1] * lwin[(k << 1) + 1]) if k2 + 1 < np else 0.0
			fft.run(re, im)
			var o0 := (f - f0) * 12
			for k in range(k0, k1):
				var kk := m - k
				var ar := re[k]
				var ai := im[k]
				var br := re[kk]
				var bi := -im[kk]
				var orr := ai - bi
				var oi := br - ar
				var c := lpc[k]
				var s := lps[k]
				var xr := ar + br + c * orr + s * oi
				var xi := ai + bi + c * oi - s * orr
				o[o0 + lbp[k]] += sqrt(xr * xr + xi * xi) * 0.5
		out[ci] = o


# --------------------------------------------------------------------------- Datei

## {ok, error, pcm: PackedFloat32Array, rate: int, duration_ms: float}
static func decode(audio_path: String) -> Dictionary:
	var res := {"ok": false, "error": "", "pcm": PackedFloat32Array(), "rate": RATE, "duration_ms": 0.0}
	if not FileAccess.file_exists(audio_path):
		res.error = "Datei nicht gefunden"
		return res
	var ff := ClipExporter.find_ffmpeg()
	if ff == "":
		res.error = "ffmpeg nicht gefunden"
		return res
	var tmp := ProjectSettings.globalize_path("user://am_features_%d_%d.raw" % [Time.get_ticks_usec(), randi() % 100000])
	var out := []
	var code := OS.execute(ff, ["-v", "error", "-y", "-i", audio_path, "-vn", "-ac", "1",
			"-ar", str(RATE), "-f", "f32le", tmp], out, true)
	var pcm := PackedFloat32Array()
	if code == 0 and FileAccess.file_exists(tmp):
		pcm = FileAccess.get_file_as_bytes(tmp).to_float32_array()
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	if pcm.is_empty():
		res.error = "Audio nicht dekodierbar"
		return res
	res.ok = true
	res.pcm = pcm
	res.duration_ms = pcm.size() * 1000.0 / RATE
	return res


## {artist, title}: Tags der Datei, sonst Dateiname ("Kuenstler - Titel").
static func tags(audio_path: String) -> Dictionary:
	var artist := ""
	var title := ""
	if FileAccess.file_exists(audio_path):
		var ff := ClipExporter.find_ffmpeg()
		if ff != "":
			var out := []
			if OS.execute(ff, ["-v", "error", "-i", audio_path, "-f", "ffmetadata", "-"], out, false) == 0 and out.size() > 0:
				for line in String(out[0]).split("\n"):
					var kv := line.strip_edges().split("=", true, 1)
					if kv.size() != 2:
						continue
					var k := kv[0].to_lower()
					if k == "artist" and artist == "":
						artist = kv[1].strip_edges()
					elif k == "title" and title == "":
						title = kv[1].strip_edges()
	return tags_from(artist, title, audio_path.get_file().get_basename())


## Reine Logik von tags(): Tag-Werte (leer = fehlt) und Dateiname ohne Endung.
static func tags_from(artist: String, title: String, stem: String) -> Dictionary:
	artist = clean_name(artist)
	title = clean_name(title)
	if title == "":
		var st := clean_name(stem)
		var parts := st.split(" - ", true, 1)
		if parts.size() == 2 and parts[1].strip_edges() != "":
			if artist == "":
				artist = parts[0].strip_edges()
			title = parts[1].strip_edges()
		else:
			title = st
	if title == "":
		title = stem.strip_edges()
	if artist == "":
		artist = "Unknown"
	return {"artist": artist, "title": title}


## Entfernt Zusaetze wie "(Official Video)", "[Lyrics]", "(prod. X)", "prod. by X".
static func clean_name(s: String) -> String:
	var re := RegEx.new()
	re.compile("(?i)\\s*[\\(\\[\\{][^\\)\\]\\}]*\\b(official|offiziell\\w*|video|audio|lyrics?|visuali[sz]er|prod|produced|hd|hq|4k|mv|explicit|videoclip|musikvideo|free download)\\b[^\\)\\]\\}]*[\\)\\]\\}]")
	s = re.sub(s, "", true)
	re.compile("(?i)\\s+(prod\\.?|produced)\\s+(by\\s+)?\\S.*$")
	s = re.sub(s, "", true)
	re.compile("\\s{2,}")
	s = re.sub(s, " ", true)
	return s.strip_edges()


# --------------------------------------------------------------------------- Analyse

static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "duration_ms": 0.0, "events": [], "energy": PackedFloat32Array(),
			"frame_ms": 0.0, "sections": []}


static func _run_group(c: Callable, count: int, threads: int) -> void:
	if count <= 0:
		return
	if threads == 1 or count == 1:
		for i in count:
			c.call(i)
		return
	var id := WorkerThreadPool.add_group_task(c, count, -1, true, "am_features")
	WorkerThreadPool.wait_for_group_task_completion(id)


static func _percentile(v: PackedFloat32Array, q: float) -> float:
	if v.is_empty():
		return 0.0
	var c := v.duplicate()
	c.sort()
	return c[clampi(int(q * (c.size() - 1)), 0, c.size() - 1)]


## Spitzen eines Anstiegs-Verlaufs. Liefert [zeit_in_frames: float, wert: float, frame: int, verhaeltnis: float].
## soft: Zeit = Beginn des Anstiegs (zurueckgehen, solange der Fluss schon deutlich steigt).
static func _pick(fl: PackedFloat32Array, k_abs: float, k_rel: float, gap: int, soft: bool, min_flux: float = 0.0) -> Array:
	var n := fl.size()
	var res: Array = []
	if n < 4:
		return res
	var ps := PackedFloat64Array()
	ps.resize(n + 1)
	var acc := 0.0
	ps[0] = 0.0
	for f in n:
		acc += fl[f]
		ps[f + 1] = acc
	var gm := acc / n
	if gm <= 1e-9:
		return res
	var last_f := -100000
	var last_v := 0.0
	for f in range(1, n - 1):
		var v := fl[f]
		if v <= 0.0 or v < fl[f - 1] or v <= fl[f + 1]:
			continue
		var a := maxi(0, f - 12)
		var b := mini(n, f + 7)
		var thr := maxf(k_abs * gm + k_rel * (ps[b] - ps[a]) / (b - a), min_flux)
		if v < thr:
			continue
		if f - last_f < gap:
			if v <= last_v:
				continue
			res.pop_back()
		var pv := fl[f - 1]
		var nv := fl[f + 1]
		var tf := f + (nv - pv) / (pv + v + nv)
		if soft:
			var st := f
			while st > 1 and f - st < 6 and fl[st - 1] >= 0.25 * v and fl[st - 1] <= fl[st]:
				st -= 1
			if st < f:
				tf = (tf + st) * 0.5
		res.append([tf, v, f, v / thr])
		last_f = f
		last_v = v
	return res


static func _normalize(list: Array) -> void:
	if list.is_empty():
		return
	var vals := PackedFloat32Array()
	for e in list:
		vals.append(e[1])
	var ref := maxf(_percentile(vals, 0.95), 1e-9)
	for e in list:
		e[1] = clampf(float(e[1]) / ref, 0.0, 1.0)


static func _frame_index(list: Array, frames: int) -> PackedInt32Array:
	var idx := PackedInt32Array()
	idx.resize(frames)
	idx.fill(-1)
	for i in list.size():
		idx[int(list[i][2])] = i
	return idx


static func _near(idx: PackedInt32Array, f: int, tol: int) -> int:
	for d in range(-tol, tol + 1):
		var g := f + d
		if g >= 0 and g < idx.size() and idx[g] >= 0:
			return idx[g]
	return -1


static func _pos(hz: float, lo: float, hi: float) -> float:
	if hz <= 0.0:
		return 0.5
	return clampf(log(hz / lo) / log(hi / lo), 0.0, 1.0)


static func _band_of(hz: float, nb: int) -> int:
	for b in nb:
		if hz < BAND_EDGES[b + 1]:
			return b
	return nb - 1


## Kiai je Abschnitt aus den Intensitaeten: ab max(kiai_abs, hoechste - kiai_margin).
static func kiai_flags(intens: Array, kiai_abs: float, kiai_margin: float) -> Array:
	var imax := 0.0
	for v in intens:
		imax = maxf(imax, float(v))
	var thr := maxf(kiai_abs, imax - kiai_margin)
	var res: Array = []
	for v in intens:
		res.append(float(v) >= thr)
	return res


static func analyze(pcm: PackedFloat32Array, rate: int, params: Dictionary = {}) -> Dictionary:
	var p := DEFAULTS.duplicate()
	p.merge(params, true)
	if rate <= 0 or pcm.size() < rate / 2:
		return _fail("Audio zu kurz")
	var n: int = int(p.n_fft)
	var hop: int = int(p.hop)
	if n < 64 or (n & (n - 1)) != 0 or hop < 16 or hop > n:
		return _fail("n_fft/hop ungueltig")
	var threads: int = int(p.threads)
	var cores := maxi(1, OS.get_processor_count())
	var frame_ms := hop * 1000.0 / rate
	var duration_ms := pcm.size() * 1000.0 / rate
	var m := n >> 1
	var nb := BAND_EDGES.size() - 1

	# ---- 1. STFT -> Baender
	var st := _Stft.new()
	var pad := PackedFloat32Array()
	pad.resize(m)
	pad.fill(0.0)
	pad.append_array(pcm)
	var tail := PackedFloat32Array()
	tail.resize(n + hop)
	tail.fill(0.0)
	pad.append_array(tail)
	st.pad = pad
	st.n = n
	st.hop = hop
	@warning_ignore("integer_division")
	st.frames = pcm.size() / hop + 1
	var frames := st.frames
	st.win.resize(n)
	for i in n:
		st.win[i] = 0.5 - 0.5 * cos(TAU * i / n)
	st.fft = _Fft.new(m)
	st.pc.resize(m + 1)
	st.psn.resize(m + 1)
	for k in m + 1:
		st.pc[k] = cos(TAU * k / n)
		st.psn[k] = sin(TAU * k / n)
	st.bin_hz = float(rate) / n
	st.nb = nb
	st.band_lo.resize(nb)
	st.band_hi.resize(nb)
	for b in nb:
		var lo := clampi(int(ceil(BAND_EDGES[b] / st.bin_hz)), 1, m - 1)
		var hi := clampi(int(ceil(BAND_EDGES[b + 1] / st.bin_hz)), 1, m - 1)
		st.band_lo[b] = lo
		st.band_hi[b] = maxi(hi, lo)
	st.k_lo = clampi(int(round(float(p.mid_peak_lo_hz) / st.bin_hz)), 2, m - 3)
	st.k_hi = clampi(int(round(float(p.mid_peak_hi_hz) / st.bin_hz)), st.k_lo + 1, mini(m - 2, st.band_hi[nb - 1] - 1))
	var chunks := clampi(cores * 3, 1, maxi(1, frames / 64))
	st.per = int(ceil(float(frames) / chunks))
	st.out.resize(chunks)
	st.out_pk.resize(chunks)
	_run_group(st.run, chunks, threads)
	var spec := PackedFloat32Array()
	var pk := PackedFloat32Array()
	for ci in chunks:
		spec.append_array(st.out[ci])
		pk.append_array(st.out_pk[ci])
	st.pad = PackedFloat32Array()
	pad = PackedFloat32Array()

	# ---- 2. Harmonisch/perkussiv, Anstiegs-Verlaeufe je Ebene
	var hp := _Hpss.new()
	hp.s = spec
	hp.nb = nb
	hp.frames = frames
	hp.kt = maxi(3, int(p.median_time) | 1)
	hp.kf = maxi(3, int(p.median_freq) | 1)
	hp.gamma = float(p.gamma)
	hp.hb.resize(nb)
	hp.refs.resize(nb)
	_run_group(hp.med_band, nb, threads)
	var gref := 0.0
	for b in nb:
		gref = maxf(gref, float(hp.refs[b]))
	if gref <= 1e-6:
		var silent := _fail("")
		silent.ok = true
		silent.duration_ms = duration_ms
		silent.frame_ms = frame_ms
		var en0 := PackedFloat32Array()
		en0.resize(frames)
		en0.fill(0.0)
		silent.energy = en0
		silent.sections = [{"start_ms": 0.0, "end_ms": duration_ms, "intensity": 0.0, "kind": "break", "kiai": false, "lead": "tonal"}]
		return silent
	hp.floor_ref = gref * pow(10.0, float(p.floor_db) / 20.0)
	# Verdeckung: gehaltene Toene (Zeit-Median) lecken ueber die Fensterflanken in fast leere Baender;
	# dort schwankt das Leck mit der Phase und erzeugte Schein-Anstiege. Was weiter als mask_db unter
	# dem lautesten gehaltenen Band liegt, wird abgezogen. Steigt sofort, faellt langsam (keine Schein-
	# Anstiege, wenn ein lauter Ton endet).
	var mk_lin := pow(10.0, float(p.mask_db) / 20.0)
	var mk_dec := pow(10.0, -absf(float(p.mask_decay_db)) / 20.0)
	hp.mask.resize(frames)
	var mk_prev := 0.0
	var hcols: Array[PackedFloat32Array] = []
	for b in nb:
		hcols.append(hp.hb[b])
	for f in frames:
		var mx := 0.0
		for b in nb:
			mx = maxf(mx, hcols[b][f])
		mk_prev = maxf(mx * mk_lin, mk_prev * mk_dec)
		hp.mask[f] = mk_prev
	hp.per = st.per
	hp.out.resize(chunks)
	_run_group(hp.agg, chunks, threads)
	var agg := PackedFloat32Array()
	for ci in chunks:
		agg.append_array(hp.out[ci])
	var f_kick := PackedFloat32Array()
	var f_bass := PackedFloat32Array()
	var f_mid := PackedFloat32Array()
	var f_hi := PackedFloat32Array()
	var e_hl := PackedFloat32Array()
	var e_hm := PackedFloat32Array()
	var e_p := PackedFloat32Array()
	var e_tot := PackedFloat32Array()
	var w_pm := PackedFloat32Array()
	var w_hi := PackedFloat32Array()
	var w_lo := PackedFloat32Array()
	var w_hl := PackedFloat32Array()
	var w_hm := PackedFloat32Array()
	var s_l5 := PackedFloat32Array()
	var s_mid := PackedFloat32Array()
	var tracks: Array[PackedFloat32Array] = [f_kick, f_bass, f_mid, f_hi, e_hl, e_hm, e_p, e_tot, w_pm, w_hi, w_lo, w_hl, w_hm, s_l5, s_mid]
	for arr in tracks:
		arr.resize(frames)
	for f in frames:
		var i := f * AGG_K
		for k in AGG_K:
			tracks[k][f] = agg[i + k]

	# ---- 3. Stimme: Anteil gleitender Tonhoehe um jeden Frame
	var glide := PackedFloat32Array()
	glide.resize(frames + 1)
	glide[0] = 0.0
	var g_lo: float = p.glide_lo_st
	var g_hi: float = p.glide_hi_st
	var v_lo: float = p.vocal_lo_hz
	var v_hi: float = p.vocal_hi_hz
	var inv_ln2x12 := 12.0 / log(2.0)
	var gacc := 0.0
	var prev_hz := 0.0
	for f in frames:
		var hz := pk[f]
		if hz >= v_lo and hz <= v_hi and prev_hz > 0.0:
			var d := absf(log(hz / prev_hz)) * inv_ln2x12
			if d >= g_lo and d <= g_hi:
				gacc += 1.0
		prev_hz = hz
		glide[f + 1] = gacc
	var voc := PackedFloat32Array()
	voc.resize(frames)
	for f in frames:
		var a := maxi(0, f - 4)
		var b := mini(frames, f + 13)
		voc[f] = (glide[b] - glide[a]) / (b - a)

	# ---- 4. Anschlaege je Ebene
	# Einsatz-Zeit aus dem Rohspektrum (Anstieg gegen die zwei Frames davor; die harmonische Spur ist
	# durch den Zeit-Median traeg und zu spaet). Die Ebene entscheidet die Trennung: bleibt der Pegel
	# danach im Zeit-Median stehen, ist es ein Ton (Bass/Instrument/Stimme), sonst ein Schlag.
	var gap := maxi(1, int(round(float(p.min_gap_ms) / frame_ms)))
	var mf: float = p.min_flux
	var lows := _pick(f_kick, p.kick_abs, p.kick_rel, gap, false, mf)
	var bass_c := _pick(f_bass, p.bass_abs, p.bass_rel, gap, false, mf)
	var mid_c := _pick(f_mid, p.snare_abs, p.snare_rel, gap, false, mf)
	var hats := _pick(f_hi, p.hat_abs, p.hat_rel, gap, false, mf)
	var hold2: float = float(p.hold_ratio) * float(p.hold_ratio)
	var k_ratio: float = p.kick_ratio
	var b_ratio: float = p.bass_ratio
	var t_ratio: float = p.tonal_ratio
	var kicks: Array = []
	for e in lows:
		var f: int = e[2]
		if _held(w_hl, s_l5, f, frames) >= hold2:
			continue
		# Kick nur, wenn die Leistung unter 150 Hz traegt: der Einsatz eines Tons in den Mitten (Stimme,
		# Instrument) leckt ueber die Hauptkeule des Fensters auch nach unten.
		var r_lo := _rise(w_lo, f, frames)
		if r_lo >= k_ratio * _rise(w_pm, f, frames):
			# Staerke aus der perkussiven Leistung: ein liegender Bass senkt den Roh-Anstieg, nicht diese.
			e[1] = sqrt(r_lo)
			kicks.append(e)
	var basses: Array = []
	for e in bass_c:
		var f: int = e[2]
		if _held(w_hl, s_l5, f, frames) < hold2:
			continue
		# Bass nur, wenn die gehaltene Leistung unter 260 Hz den Anstieg traegt: der Grundton einer
		# Stimme oder eines Instruments liegt oft ueber 150 Hz, die Leistung aber in den Mitten.
		if _rise(w_hl, f, frames, 4) >= b_ratio * _rise(w_hm, f, frames, 4):
			basses.append(e)
	var mids: Array = []
	var harm: Array = []
	for e in mid_c:
		var f: int = e[2]
		if _held(w_hm, s_mid, f, frames) >= hold2:
			# Einsatz eines lauten Basstons streut kurz in die Mitten; ein Ton dort muss gegen den Bass zaehlen.
			if _rise(w_hm, f, frames, 4) >= t_ratio * _rise(w_hl, f, frames, 4):
				harm.append(e)
		else:
			mids.append(e)
	_normalize(kicks)
	var k_min: float = p.kick_min
	kicks = kicks.filter(func(e: Array) -> bool: return float(e[1]) >= k_min)
	_normalize(mids)
	_normalize(hats)
	_normalize(basses)
	var kick_idx := _frame_index(kicks, frames)
	var sh_snare: float = p.shift_snare_ms
	var sh_hat: float = p.shift_hat_ms
	var sh_other: float = p.shift_other_ms
	var shift_low: float = p.shift_low_ms
	var events: Array = []
	for e in kicks:
		events.append({"t_ms": maxf(0.0, float(e[0]) * frame_ms + shift_low), "strength": e[1], "kind": "kick", "pitch": -1.0, "sustain_ms": 0.0})
	var snare_list: Array = []
	var k_over: float = p.kick_over_snare
	var sn_ratio: float = p.snare_ratio
	var hat_ratio: float = p.hat_ratio
	for e in mids:
		var f: int = e[2]
		var fb := maxi(f - 2, 0)
		var fn := mini(f + 1, frames - 1)
		var d_pm := maxf(maxf(w_pm[f], w_pm[fn]) - w_pm[fb], 1e-12)
		var d_hi := maxf(maxf(w_hi[f], w_hi[fn]) - w_hi[fb], 0.0)
		if d_hi >= hat_ratio * d_pm:
			continue
		var ki := _near(kick_idx, f, 2)
		if ki >= 0 and float(kicks[ki][1]) * k_over >= float(e[1]):
			continue
		var kind := "snare" if d_hi >= sn_ratio * d_pm else "other"
		if kind == "snare":
			snare_list.append(e)
		events.append({"t_ms": maxf(0.0, float(e[0]) * frame_ms + (sh_snare if kind == "snare" else sh_other)), "strength": e[1],
				"kind": kind, "pitch": -1.0, "sustain_ms": 0.0})
	var snare_idx := _frame_index(snare_list, frames)
	var hk_ratio: float = p.hat_kick_ratio
	for e in hats:
		var f: int = e[2]
		if _near(snare_idx, f, 2) >= 0:
			continue
		# Klick eines Kicks reicht bis in die Hoehen; ein Becken muss gegen den Kick hoerbar sein.
		if _near(kick_idx, f, 2) >= 0 and _rise(w_hi, f, frames) < hk_ratio * _rise(w_lo, f, frames):
			continue
		events.append({"t_ms": maxf(0.0, float(e[0]) * frame_ms + sh_hat), "strength": e[1], "kind": "hat", "pitch": -1.0, "sustain_ms": 0.0})

	var sus_min: float = p.sustain_min_ms
	var sus_keep: float = p.sustain_keep
	var sus_max_f := int(float(p.sustain_max_ms) / frame_ms)

	# Bass: Tonhoehe ueber die lange FFT, Halten im staerksten tiefen Band.
	if not basses.is_empty():
		var bp := _BassPitch.new()
		bp.pcm = pcm
		bp.rate = rate
		bp.lo_hz = p.bass_pitch_lo_hz
		bp.hi_hz = p.bass_pitch_hi_hz
		bp.fft = _Fft.new(256)
		bp.win.resize(256)
		for i in 256:
			bp.win[i] = 0.5 - 0.5 * cos(TAU * i / 256.0)
		bp.starts.resize(basses.size())
		for i in basses.size():
			bp.starts[i] = int(float(basses[i][0]) * hop) + 128
		var bchunks := clampi(cores * 2, 1, basses.size())
		bp.per = int(ceil(float(basses.size()) / bchunks))
		bp.out.resize(bchunks)
		_run_group(bp.run, bchunks, threads)
		var bhz := PackedFloat32Array()
		for ci in bchunks:
			bhz.append_array(bp.out[ci])
		for i in basses.size():
			var e: Array = basses[i]
			var f: int = e[2]
			var bnd := 0
			var bmax := -1.0
			var fr := mini(f + 3, frames - 1)
			for b in B_BASS_END:
				var hv: float = (hp.hb[b] as PackedFloat32Array)[fr]
				if hv > bmax:
					bmax = hv
					bnd = b
			var f_next := frames
			if i + 1 < basses.size():
				f_next = int(basses[i + 1][2])
			var sus := _sustain(hp.hb[bnd], f, mini(f_next, f + sus_max_f), sus_keep) * frame_ms
			events.append({"t_ms": maxf(0.0, float(e[0]) * frame_ms + shift_low), "strength": e[1], "kind": "bass",
					"pitch": _pos(bhz[i], p.bass_pitch_lo_hz, p.bass_pitch_hi_hz),
					"sustain_ms": sus if sus >= sus_min else 0.0})

	# Instrument / Stimme
	var voc_min: float = p.vocal_min
	var kept: Array = []
	for e in harm:
		e.append(voc[int(e[2])] >= voc_min)
		kept.append(e)
	_normalize(kept)
	for i in kept.size():
		var e: Array = kept[i]
		var f: int = e[2]
		var cand := PackedFloat32Array()
		for d in range(1, 6):
			var g := f + d
			if g < frames and pk[g] > 0.0:
				cand.append(pk[g])
		var hz := 0.0
		if not cand.is_empty():
			cand.sort()
			hz = cand[cand.size() >> 1]
		var is_voc: bool = e[4]
		var bnd := clampi(_band_of(hz, nb), B_MID_START - 1, B_MID_END - 1) if hz > 0.0 else B_MID_START + 2
		var f_next := frames
		if i + 1 < kept.size():
			f_next = int(kept[i + 1][2])
		var sus := _sustain(hp.hb[bnd], f, mini(f_next, f + sus_max_f), sus_keep) * frame_ms
		var pos := _pos(hz, p.vocal_pitch_lo_hz, p.vocal_pitch_hi_hz) if is_voc else _pos(hz, p.tonal_pitch_lo_hz, p.tonal_pitch_hi_hz)
		events.append({"t_ms": maxf(0.0, float(e[0]) * frame_ms + float(p.shift_harm_ms)), "strength": e[1],
				"kind": "vocal" if is_voc else "tonal", "pitch": pos,
				"sustain_ms": sus if sus >= sus_min else 0.0})
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t_ms < b.t_ms)
	events = _merge_onsets(events, 2.0 * frame_ms)

	# ---- 5. Lautheit je Frame
	var db := PackedFloat32Array()
	db.resize(frames)
	for f in frames:
		db[f] = 10.0 * log(e_tot[f] + 1e-9) / log(10.0)
	var top := _percentile(db, 0.98)
	var rng: float = maxf(float(p.energy_range_db), 1.0)
	var energy := PackedFloat32Array()
	energy.resize(frames)
	for f in frames:
		var a := db[maxi(f - 1, 0)]
		var c := db[mini(f + 1, frames - 1)]
		energy[f] = clampf(((a + db[f] + c) / 3.0 - (top - rng)) / rng, 0.0, 1.0)

	# ---- 6. Takte und Liedform
	var grid: Dictionary = p.grid if p.get("grid") is Dictionary else {}
	if (grid.get("segments", []) as Array).is_empty() and float(p.form_track_grid) > 0.0:
		grid = AmGrid.track(pcm, rate, p.grid_params if p.get("grid_params") is Dictionary else {})
	var bars := bar_starts(grid if grid.get("ok", true) else {}, duration_ms)
	var chroma := _chroma(pcm, rate, threads, cores)
	var bf := _bar_feats(bars, duration_ms, frames, frame_ms, spec, nb, energy, e_p, e_hl, e_hm, voc, float(p.vocal_min), chroma, events)

	# ---- 7. Abschnitte
	var sections := _sections(p, frames, frame_ms, duration_ms, energy, e_p, e_hl, e_hm, voc, events)
	var res := {"ok": true, "error": "", "duration_ms": duration_ms, "events": events, "energy": energy,
			"frame_ms": frame_ms, "sections": sections}
	if p.get("debug_form", false):
		bf["bars"] = bars
		res["form_debug"] = bf
	if p.get("debug", false):
		res["debug"] = {"f_kick": f_kick, "f_bass": f_bass, "f_mid": f_mid, "f_hi": f_hi, "voc": voc,
				"spec": spec, "refs": hp.refs, "floor_ref": hp.floor_ref, "hb": hp.hb, "nb": nb}
	return res


## Gehaltener Anteil des Einsatzes: Zuwachs der Zeit-Median-Leistung (3..5 Frames danach gegen 1..3
## Frames davor) / Zuwachs der Rohleistung (Spitze f..f+2 gegen davor). Ein Schlag ueber einem
## liegenden Ton aendert den Zeit-Median kaum (-> 0), ein neuer Ton hebt ihn (-> 1).
static func _held(wh: PackedFloat32Array, sr: PackedFloat32Array, f: int, frames: int) -> float:
	var pk := 0.0
	for g in range(f, mini(f + 3, frames)):
		pk = maxf(pk, sr[g])
	var hb := 0.0
	var sb := 0.0
	var cb := 0
	for g in range(maxi(f - 3, 0), f):
		hb += wh[g]
		sb += sr[g]
		cb += 1
	if cb > 0:
		hb /= cb
		sb /= cb
	var acc := 0.0
	var c := 0
	for g in range(f + 3, mini(f + 6, frames)):
		acc += wh[g]
		c += 1
	if c == 0:
		return 0.0
	var d_raw := pk - sb
	if d_raw <= 1e-12:
		return 0.0
	return maxf(acc / c - hb, 0.0) / d_raw


## Anstieg einer Leistungs-Spur am Anschlag-Frame f: Hoechstwert in f..f+ahead gegen 2 Frames vorher, >= 0.
static func _rise(w: PackedFloat32Array, f: int, frames: int, ahead: int = 1) -> float:
	var fb := maxi(f - 2, 0)
	var mx := w[f]
	for g in range(f + 1, mini(f + ahead + 1, frames)):
		mx = maxf(mx, w[g])
	return maxf(mx - w[fb], 0.0)


## Ein akustischer Einsatz = ein Ereignis je Ebene, die ihn wirklich traegt:
## "other" (perkussiv ohne Trommel-Form) entfaellt, wenn derselbe Einsatz schon als Trommel,
## Bass, Ton oder Stimme erkannt ist; ein kurzer Bass auf einem Kick ist der Ausklang des Kicks.
static func _merge_onsets(events: Array, tol_ms: float) -> Array:
	var n := events.size()
	var drop := PackedByteArray()
	drop.resize(n)
	drop.fill(0)
	for i in n:
		var e: Dictionary = events[i]
		var k: String = e.kind
		if k != "other" and not (k == "bass" and float(e.sustain_ms) <= 0.0):
			continue
		var t: float = e.t_ms
		var j := i - 1
		while j >= 0 and t - float(events[j].t_ms) <= tol_ms:
			if _merges_into(k, events[j].kind):
				drop[i] = 1
			j -= 1
		j = i + 1
		while j < n and float(events[j].t_ms) - t <= tol_ms:
			if _merges_into(k, events[j].kind):
				drop[i] = 1
			j += 1
	var res: Array = []
	for i in n:
		if drop[i] == 0:
			res.append(events[i])
	return res


static func _merges_into(kind: String, other: String) -> bool:
	if kind == "other":
		return other != "other"
	return other == "kick"


## Frames ab f, in denen der harmonische Pegel des Bands oben bleibt.
static func _sustain(h: PackedFloat32Array, f: int, f_end: int, keep: float) -> float:
	var n := h.size()
	var ref := 0.0
	for d in range(1, 6):
		if f + d < n:
			ref = maxf(ref, h[f + d])
	if ref <= 1e-9:
		return 0.0
	var thr := ref * keep
	var g := f + 2
	var lim := mini(f_end, n)
	while g < lim and h[g] >= thr:
		g += 1
	return float(g - f)


static func _sections(p: Dictionary, frames: int, frame_ms: float, duration_ms: float, energy: PackedFloat32Array,
		e_p: PackedFloat32Array, e_hl: PackedFloat32Array, e_hm: PackedFloat32Array, voc: PackedFloat32Array,
		events: Array) -> Array:
	var blk := maxi(1, int(round(float(p.section_block_ms) / frame_ms)))
	var nblk := int(ceil(float(frames) / blk))
	var feats: Array[PackedFloat32Array] = []
	for k in 4:
		var a := PackedFloat32Array()
		a.resize(nblk)
		a.fill(0.0)
		feats.append(a)
	var vfrac := PackedFloat32Array()
	vfrac.resize(nblk)
	var voc_min: float = p.vocal_min
	var hm_sum := 0.0
	for f in frames:
		hm_sum += e_hm[f]
	var hm_mean := hm_sum / frames
	for i in nblk:
		var a := i * blk
		var b := mini(frames, a + blk)
		var s0 := 0.0
		var s1 := 0.0
		var s2 := 0.0
		var s3 := 0.0
		var vc := 0
		for f in range(a, b):
			s0 += energy[f]
			s1 += e_p[f]
			s2 += e_hl[f]
			s3 += e_hm[f]
			if voc[f] >= voc_min and e_hm[f] >= 0.5 * hm_mean:
				vc += 1
		var c := float(b - a)
		feats[0][i] = s0 / c
		feats[1][i] = s1 / c
		feats[2][i] = s2 / c
		feats[3][i] = s3 / c
		vfrac[i] = vc / c
	var loud := feats[0].duplicate()
	for k in range(1, 4):
		var mx := 1e-9
		for i in nblk:
			mx = maxf(mx, feats[k][i])
		for i in nblk:
			feats[k][i] /= mx
	# Ereignisse je Block und Art
	var cnt: Array[PackedInt32Array] = []
	for k in KINDS.size():
		var a := PackedInt32Array()
		a.resize(nblk)
		a.fill(0)
		cnt.append(a)
	var blk_ms := blk * frame_ms
	var all_cnt := PackedFloat32Array()
	all_cnt.resize(nblk)
	all_cnt.fill(0.0)
	for e: Dictionary in events:
		var bi := clampi(int(float(e.t_ms) / blk_ms), 0, nblk - 1)
		cnt[KINDS.find(e.kind)][bi] += 1
		all_cnt[bi] += 1.0
	# Neuheit
	var w := maxi(2, int(round(float(p.section_window_s) * 1000.0 / blk_ms)))
	var min_len := maxi(2, int(round(float(p.section_min_s) * 1000.0 / blk_ms)))
	var nov := PackedFloat32Array()
	nov.resize(nblk)
	nov.fill(0.0)
	var wts: Array[float] = [2.0, 1.0, 1.0, 1.0]
	for i in range(w, nblk - w + 1):
		var d := 0.0
		for k in 4:
			var pa := 0.0
			var pb := 0.0
			for j in w:
				pa += feats[k][i - 1 - j]
				pb += feats[k][i + j] if i + j < nblk else feats[k][nblk - 1]
			d += wts[k] * absf(pb - pa) / w
		nov[i] = d
	var cands: Array = []
	var thr: float = p.section_novelty
	for i in range(1, nblk - 1):
		if nov[i] >= thr and nov[i] >= nov[i - 1] and nov[i] > nov[i + 1]:
			cands.append([nov[i], i])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var cuts: Array[int] = [0, nblk]
	for c in cands:
		var ci: int = c[1]
		var ok := true
		for x in cuts:
			if absi(x - ci) < min_len:
				ok = false
				break
		if ok:
			cuts.append(ci)
	cuts.sort()
	var lo := _percentile(loud, 0.1)
	var hi := maxf(_percentile(loud, 0.95), lo + 1e-3)
	var dens_ref := maxf(_percentile(all_cnt, 0.95), 1.0)
	var secs: Array = []
	var intens: Array = []
	var slopes: Array = []
	for si in cuts.size() - 1:
		var a := cuts[si]
		var b := cuts[si + 1]
		var ls := 0.0
		var ds := 0.0
		var h1 := 0.0
		var h2 := 0.0
		var vs := 0.0
		var kc: Array[float] = []
		kc.resize(KINDS.size())
		kc.fill(0.0)
		@warning_ignore("integer_division")
		var mid := (a + b) / 2
		for i in range(a, b):
			ls += loud[i]
			ds += all_cnt[i]
			vs += vfrac[i]
			if i < mid:
				h1 += loud[i]
			else:
				h2 += loud[i]
			for k in KINDS.size():
				kc[k] += cnt[k][i]
		var c := float(b - a)
		var inten := clampf(0.7 * clampf((ls / c - lo) / (hi - lo), 0.0, 1.0) + 0.3 * clampf(ds / c / dens_ref, 0.0, 1.0), 0.0, 1.0)
		var slope := 0.0
		if mid > a and b > mid:
			slope = h2 / (b - mid) - h1 / (mid - a)
		var secs_s := c * blk_ms / 1000.0
		var drums_eps := (kc[0] + kc[1] + kc[2] + kc[6]) / secs_s
		var s_d := clampf(drums_eps / float(p.lead_drums_eps), 0.0, 1.0) * (0.6 + 0.4 * inten)
		var s_b := clampf(kc[3] / secs_s / float(p.lead_bass_eps), 0.0, 1.0) * 0.7
		var s_t := clampf(kc[4] / secs_s / float(p.lead_tonal_eps), 0.0, 1.0) * 0.75
		var s_v := clampf(vs / c / float(p.lead_vocal_frac), 0.0, 1.0) * (1.1 - 0.4 * inten)
		var lead := "tonal"
		var best := 0.15
		if s_t > best:
			best = s_t
		if s_b > best:
			best = s_b
			lead = "bass"
		if s_d > best:
			best = s_d
			lead = "drums"
		if s_v > best:
			best = s_v
			lead = "vocal"
		intens.append(inten)
		slopes.append(slope)
		secs.append({"start_ms": a * blk_ms, "end_ms": minf(b * blk_ms, duration_ms), "intensity": inten,
				"kind": "verse", "kiai": false, "lead": lead})
	secs[0].start_ms = 0.0
	secs[secs.size() - 1].end_ms = duration_ms
	var kf := kiai_flags(intens, p.kiai_abs, p.kiai_margin)
	var brk: float = p.break_max
	var med_i := 0.5
	if not intens.is_empty():
		var tmp := PackedFloat32Array(intens)
		med_i = _percentile(tmp, 0.5) + 1e-5
	for si in secs.size():
		var s: Dictionary = secs[si]
		var it: float = intens[si]
		s.kiai = kf[si]
		if kf[si]:
			s.kind = "chorus"
		elif si == 0 and secs.size() > 1 and it < 0.5 and it <= med_i:
			s.kind = "intro"
		elif si == secs.size() - 1 and secs.size() > 1 and it < 0.5 and it <= med_i:
			s.kind = "outro"
		elif it < brk:
			s.kind = "break"
		elif si + 1 < secs.size() and kf[si + 1] and float(slopes[si]) > 0.04:
			s.kind = "build"
		else:
			s.kind = "verse"
	return secs


# --------------------------------------------------------------------------- Liedform

## Chroma je langem Frame: {"c": PackedFloat32Array (frames * 12), "frame_ms": float, "frames": int}.
static func _chroma(pcm: PackedFloat32Array, rate: int, threads: int, cores: int) -> Dictionary:
	var n := 4096
	var m := n >> 1
	var ch := _Chroma.new()
	ch.pcm = pcm
	ch.n = n
	@warning_ignore("integer_division")
	ch.frames = maxi(1, (pcm.size() + n - 1) / n)
	ch.fft = _Fft.new(m)
	ch.win.resize(n)
	for i in n:
		ch.win[i] = 0.5 - 0.5 * cos(TAU * i / n)
	ch.pc.resize(m + 1)
	ch.psn.resize(m + 1)
	for k in m + 1:
		ch.pc[k] = cos(TAU * k / n)
		ch.psn[k] = sin(TAU * k / n)
	var bin_hz := float(rate) / n
	ch.k0 = maxi(2, int(ceil(60.0 / bin_hz)))
	ch.k1 = mini(m - 1, int(floor(2100.0 / bin_hz)))
	ch.bin_pc.resize(m)
	ch.bin_pc.fill(0)
	for k in range(ch.k0, ch.k1):
		var midi := 69.0 + 12.0 * log(k * bin_hz / 440.0) / log(2.0)
		ch.bin_pc[k] = posmod(int(round(midi)), 12)
	var chunks := clampi(cores * 2, 1, ch.frames)
	ch.per = int(ceil(float(ch.frames) / chunks))
	ch.out.resize(chunks)
	_run_group(ch.run, chunks, threads)
	var c := PackedFloat32Array()
	for ci in chunks:
		c.append_array(ch.out[ci])
	return {"c": c, "frame_ms": n * 1000.0 / rate, "frames": ch.frames}


## Taktanfaenge in akustischer Zeit (Gitter in Map-Zeit + lead_ms), aufsteigend, erster = 0.
## Ohne Gitter: feste Bloecke von fallback_ms.
static func bar_starts(grid: Dictionary, duration_ms: float, lead_ms: float = AmGrid.OSU_LEAD_MS,
		fallback_ms: float = 2000.0) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.append(0.0)
	var segs: Array = grid.get("segments", []) if grid.get("segments") is Array else []
	if segs.is_empty():
		var t := fallback_ms
		while t < duration_ms - 0.5 * fallback_ms:
			out.append(t)
			t += fallback_ms
		return out
	for si in segs.size():
		var s: Dictionary = segs[si]
		var beat := maxf(float(s.get("beat_ms", 500.0)), 50.0)
		var bar := beat * maxi(int(s.get("meter", 4)), 1)
		while bar < 1000.0:
			bar *= 2.0   # sehr schnelles Gitter: Doppeltakte, sonst wird die Liedform zu fein
		var d := float(s.get("downbeat_ms", s.get("start_ms", 0.0))) + lead_ms
		var a := -INF if si == 0 else float(s.get("start_ms", 0.0)) + lead_ms
		var b := duration_ms if si + 1 == segs.size() else float(segs[si + 1].get("start_ms", duration_ms)) + lead_ms
		if si > 0 and a > out[out.size() - 1] + 0.25 * bar:
			out.append(a)   # neue rote Linie = neuer Takt
		var k := ceilf(((maxf(a, 0.0)) - d) / bar - 1e-6)
		var t := d + k * bar
		while t < b - 1.0:
			if t > out[out.size() - 1] + 0.25 * bar and t < duration_ms - 0.25 * bar:
				out.append(t)
			t += bar
	return out


## Merkmale je Takt. Liefert Arrays gleicher Laenge (Taktzahl).
static func _bar_feats(bars: PackedFloat64Array, duration_ms: float, frames: int, frame_ms: float, spec: PackedFloat32Array,
		nb: int, energy: PackedFloat32Array, e_p: PackedFloat32Array, e_hl: PackedFloat32Array, e_hm: PackedFloat32Array,
		voc: PackedFloat32Array, voc_min: float, chroma: Dictionary, events: Array) -> Dictionary:
	var nbar := bars.size()
	var loud := PackedFloat32Array()
	var ep := PackedFloat32Array()
	var ehl := PackedFloat32Array()
	var ehm := PackedFloat32Array()
	var vf := PackedFloat32Array()
	var tim := PackedFloat32Array()   # nbar * nb, log-Pegel je Band
	var chm := PackedFloat32Array()   # nbar * 12, auf Summe 1
	var cnt := PackedFloat32Array()   # nbar * 7, Ereignisse je Sekunde je Art
	var stg := PackedFloat32Array()   # nbar * 7, Staerke-Summe je Sekunde je Art
	for arr: PackedFloat32Array in [loud, ep, ehl, ehm, vf]:
		arr.resize(nbar)
	tim.resize(nbar * nb)
	chm.resize(nbar * 12)
	chm.fill(0.0)
	cnt.resize(nbar * 7)
	cnt.fill(0.0)
	stg.resize(nbar * 7)
	stg.fill(0.0)
	var hm_sum := 0.0
	for f in frames:
		hm_sum += e_hm[f]
	var hm_mean := hm_sum / maxi(frames, 1)
	var cc: PackedFloat32Array = chroma.c
	var cfm: float = chroma.frame_ms
	var cfr: int = chroma.frames
	var acc := PackedFloat32Array()
	acc.resize(nb)
	for i in nbar:
		var t0 := bars[i]
		var t1 := bars[i + 1] if i + 1 < nbar else duration_ms
		var f0 := clampi(int(t0 / frame_ms), 0, frames - 1)
		var f1 := clampi(int(t1 / frame_ms), f0 + 1, frames)
		var s0 := 0.0
		var s1 := 0.0
		var s2 := 0.0
		var s3 := 0.0
		var vc := 0
		acc.fill(0.0)
		for f in range(f0, f1):
			s0 += energy[f]
			s1 += e_p[f]
			s2 += e_hl[f]
			s3 += e_hm[f]
			if voc[f] >= voc_min and e_hm[f] >= 0.5 * hm_mean:
				vc += 1
			var o := f * nb
			for b in nb:
				acc[b] += spec[o + b] * spec[o + b]
		var c := float(f1 - f0)
		loud[i] = s0 / c
		ep[i] = s1 / c
		ehl[i] = s2 / c
		ehm[i] = s3 / c
		vf[i] = vc / c
		for b in nb:
			tim[i * nb + b] = log(acc[b] / c + 1e-10)
		var g0 := clampi(int(round(t0 / cfm)), 0, cfr - 1)
		var g1 := clampi(int(round(t1 / cfm)), g0 + 1, cfr)
		var tot := 1e-9
		for g in range(g0, g1):
			for q in 12:
				var v := sqrt(cc[g * 12 + q])
				chm[i * 12 + q] += v
				tot += v
		for q in 12:
			chm[i * 12 + q] /= tot
	var ki := 0
	for e: Dictionary in events:
		var t: float = e.t_ms
		while ki + 1 < nbar and bars[ki + 1] <= t:
			ki += 1
		var k := KINDS.find(e.kind)
		cnt[ki * 7 + k] += 1.0
		stg[ki * 7 + k] += float(e.strength)
	for i in nbar:
		var t1 := bars[i + 1] if i + 1 < nbar else duration_ms
		var sec := maxf((t1 - bars[i]) / 1000.0, 0.05)
		for k in 7:
			cnt[i * 7 + k] /= sec
			stg[i * 7 + k] /= sec
	return {"n": nbar, "nb": nb, "loud": loud, "ep": ep, "ehl": ehl, "ehm": ehm, "voc": vf, "timbre": tim, "chroma": chm,
			"cnt": cnt, "str": stg}


static func _zs(x: PackedFloat32Array) -> PackedFloat32Array:
	var n := x.size()
	var m := 0.0
	for v in x:
		m += v
	m /= maxi(n, 1)
	var q := 0.0
	for v in x:
		q += (v - m) * (v - m)
	var sd := sqrt(q / maxi(n, 1)) + 1e-6
	var o := PackedFloat32Array()
	o.resize(n)
	for i in n:
		o[i] = (x[i] - m) / sd
	return o


## Rang je Wert (0 = kleinster, 1 = groesster), gleiche Werte nach Reihenfolge.
static func _rank(x: PackedFloat32Array) -> PackedFloat32Array:
	var n := x.size()
	var idx: Array = range(n)
	idx.sort_custom(func(a: int, b: int) -> bool: return x[a] < x[b] or (x[a] == x[b] and a < b))
	var o := PackedFloat32Array()
	o.resize(n)
	for k in n:
		o[idx[k]] = float(k) / maxi(n - 1, 1)
	return o


## Grundreihen je Takt fuer Liedform und Dichte (Reihenfolge = FORM_BASE).
const FORM_BASE: Array[String] = ["loud", "lep", "lhl", "lhm", "voc", "ev", "st", "perc", "kick", "snare", "hat"]

static func _form_base(bf: Dictionary) -> Array[PackedFloat32Array]:
	var n: int = bf.n
	var out: Array[PackedFloat32Array] = []
	for k in FORM_BASE.size():
		var a := PackedFloat32Array()
		a.resize(n)
		out.append(a)
	var cnt: PackedFloat32Array = bf.cnt
	var stg: PackedFloat32Array = bf.str
	for i in n:
		out[0][i] = bf.loud[i]
		out[1][i] = log(1.0 + bf.ep[i] * 1000.0)
		out[2][i] = log(1.0 + bf.ehl[i] * 1000.0)
		out[3][i] = log(1.0 + bf.ehm[i] * 1000.0)
		out[4][i] = bf.voc[i]
		var ce := 0.0
		var se := 0.0
		for k in 7:
			ce += cnt[i * 7 + k]
			se += stg[i * 7 + k]
		out[5][i] = ce
		out[6][i] = se
		out[7][i] = stg[i * 7 + 0] + stg[i * 7 + 1] + stg[i * 7 + 2] + stg[i * 7 + 6]
		out[8][i] = stg[i * 7 + 0]
		out[9][i] = stg[i * 7 + 1]
		out[10][i] = stg[i * 7 + 2]
	return out


## Selbstaehnlichkeit der Takte: wc * Kosinus(Chroma) + (1 - wc) * Kosinus(Klangfarbe, je Band z-normiert).
static func _ssm(bf: Dictionary, wc: float) -> PackedFloat32Array:
	var n: int = bf.n
	var nb: int = bf.nb
	var ch := PackedFloat32Array()
	ch.resize(n * 12)
	var chm: PackedFloat32Array = bf.chroma
	for i in n:
		var q := 0.0
		for c in 12:
			var v := sqrt(maxf(chm[i * 12 + c], 0.0))
			ch[i * 12 + c] = v
			q += v * v
		q = sqrt(q) + 1e-9
		for c in 12:
			ch[i * 12 + c] /= q
	var tim: PackedFloat32Array = bf.timbre
	var tb := PackedFloat32Array()
	tb.resize(n * nb)
	for b in nb:
		var m := 0.0
		for i in n:
			m += tim[i * nb + b]
		m /= n
		var s := 0.0
		for i in n:
			s += (tim[i * nb + b] - m) * (tim[i * nb + b] - m)
		s = sqrt(s / n) + 1e-6
		for i in n:
			tb[i * nb + b] = (tim[i * nb + b] - m) / s
	for i in n:
		var q := 0.0
		for b in nb:
			q += tb[i * nb + b] * tb[i * nb + b]
		q = sqrt(q) + 1e-9
		for b in nb:
			tb[i * nb + b] /= q
	var S := PackedFloat32Array()
	S.resize(n * n)
	for i in n:
		for j in range(i, n):
			var a := 0.0
			for c in 12:
				a += ch[i * 12 + c] * ch[j * 12 + c]
			var t := 0.0
			for b in nb:
				t += tb[i * nb + b] * tb[j * nb + b]
			var v := wc * a + (1.0 - wc) * t
			S[i * n + j] = v
			S[j * n + i] = v
	return S


## Neuheit je Takt: Schachbrett-Kern (Gauss, halbe Breite w) entlang der Diagonale, Rand wiederholt.
static func _novelty(S: PackedFloat32Array, n: int, w: int) -> PackedFloat32Array:
	var g := PackedFloat32Array()
	g.resize(2 * w)
	for a in 2 * w:
		var x := (a - w + 0.5) / (w * 0.5)
		g[a] = exp(-0.5 * x * x) * (-1.0 if a < w else 1.0)
	var nov := PackedFloat32Array()
	nov.resize(n)
	var ix := PackedInt32Array()
	ix.resize(2 * w)
	for i in n:
		for a in 2 * w:
			ix[a] = clampi(i - w + a, 0, n - 1)
		var acc := 0.0
		for a in 2 * w:
			var ra := ix[a] * n
			var ga := g[a]
			for b in 2 * w:
				acc += ga * g[b] * S[ra + ix[b]]
		nov[i] = acc
	return nov


## Abschnittsgrenzen (Takt-Indizes, mit 0 und n): Gipfel der Neuheit, auf das Phrasen-Raster (je `phrase`
## Takte, Phase mit der groessten Neuheitssumme) gelegt, gierig nach Staerke mit Mindestlaenge.
static func _cuts(nov: PackedFloat32Array, phrase: int, min_len: int, thr: float) -> PackedInt32Array:
	var n := nov.size()
	var sorted := nov.duplicate()
	sorted.sort()
	var ref := 1.0
	if n > 2:
		# wie numpy.percentile (linear) bei 95 %
		var pos := 0.95 * (n - 1)
		var lo := int(floor(pos))
		var hi := mini(lo + 1, n - 1)
		ref = sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo)
	var nv := PackedFloat32Array()
	nv.resize(n)
	for i in n:
		nv[i] = nov[i] / (ref + 1e-9)
	var cand: Array[int] = []
	for i in range(1, n - 1):
		if nv[i] >= nv[i - 1] and nv[i] > nv[i + 1] and nv[i] > thr:
			cand.append(i)
	if phrase > 1 and not cand.is_empty():
		var best := 0
		var best_s := -INF
		for q in phrase:
			var s := 0.0
			var i := q
			while i < n:
				s += nv[i]
				i += phrase
			if s > best_s:
				best_s = s
				best = q
		var snapped := {}
		@warning_ignore("integer_division")
		var kmax := (n - 1 - best) / phrase
		for c in cand:
			# naechster Rasterpunkt, bei Gleichstand der fruehere
			var k := clampi(int(ceil(float(c - best) / phrase - 0.5)), 0, kmax)
			var j := best + k * phrase
			if j > 0 and j < n:
				snapped[j] = true
		cand.clear()
		for j in snapped:
			cand.append(j)
	cand.sort_custom(func(a: int, b: int) -> bool: return nv[a] > nv[b] or (nv[a] == nv[b] and a < b))
	var cuts: Array[int] = [0, n]
	for c in cand:
		var ok := true
		for x in cuts:
			if absi(c - x) < min_len:
				ok = false
				break
		if ok:
			cuts.append(c)
	cuts.sort()
	return PackedInt32Array(cuts)
