# solar_ephem.gd —— 解析星历核心(GDScript 移植)
# 同源: deepseek-harness/tools/ephemeris/ephemeris.mjs + tools/coords/rotation.mjs (已过 9 项天文回归)
# 精度: 行星 Standish J2000 根数(1800-2050) 内行星<1角分; 月球 Meeus 截断 ~0.3'; GMST IAU 近似
# 坐标约定: 返回黄道 J2000 右手系 Vector3(x,y,z), z=黄北极; 游戏层映射 g=(x, z, -y)
class_name SolarEphem
extends RefCounted

const AU_KM := 149597870.7
const UTC_TT_SECONDS := 69.184  # 闰秒硬编码37 + TT-TAI 32.184, 单机无感

# JPL Standish 近似根数: el=[a(au), e, I(deg), L(deg), varpi(deg), Omega(deg)] + 每儒略世纪变率
const ELEM := {
	"mercury": {"el": [0.38709927, 0.20563593, 7.00497902, 252.25032350, 77.45779628, 48.33076593], "rate": [0.00000037, 0.00001906, -0.00594749, 149472.67411175, 0.16047689, -0.12534081]},
	"venus": {"el": [0.72333566, 0.00677672, 3.39467605, 181.97909950, 131.60246718, 76.67984255], "rate": [0.00000390, -0.00004107, -0.00078890, 58517.81538729, 0.00268329, -0.27769418]},
	"earth": {"el": [1.00000261, 0.01671123, -0.00001531, 100.46457166, 102.93768193, 0.0], "rate": [0.00000562, -0.00004392, -0.01294668, 35999.37244981, 0.32327364, 0.0]},
	"mars": {"el": [1.52371034, 0.09339410, 1.84969142, -4.55343205, -23.94362959, 49.55953891], "rate": [0.00001847, 0.00007882, -0.00813131, 19140.30268499, 0.44441088, -0.29257343]},
	"jupiter": {"el": [5.20288700, 0.04838624, 1.30439695, 34.39644051, 14.72847983, 100.47390909], "rate": [-0.00011607, -0.00013253, -0.00183714, 3034.74612775, 0.21252668, 0.20469106]},
	"saturn": {"el": [9.53667594, 0.05386179, 2.48599187, 49.95424423, 92.59887831, 113.66242448], "rate": [-0.00125060, -0.00050991, 0.00193609, 1222.49362201, -0.41897216, -0.28867794]},
	"uranus": {"el": [19.18916464, 0.04725744, 0.77263783, 313.23810451, 170.95427630, 74.01692503], "rate": [-0.00196176, -0.00004397, -0.00242939, 428.48202785, 0.40805281, 0.04240589]},
	"neptune": {"el": [30.06992276, 0.00859048, 1.77004347, -55.12002969, 44.96476227, 131.78422574], "rate": [0.00026291, 0.00005105, 0.00035372, 218.45945325, -0.32241464, -0.00508664]},
}

static func norm360(x: float) -> float:
	return fposmod(x, 360.0)

static func sind(x: float) -> float:
	return sin(deg_to_rad(x))

static func cosd(x: float) -> float:
	return cos(deg_to_rad(x))

static func jd_tt_from_ms(ms: float) -> float:
	return ms / 86400000.0 + 2440587.5 + UTC_TT_SECONDS / 86400.0

static func jd_from_ms(ms: float) -> float:
	return ms / 86400000.0 + 2440587.5

static func centuries_from_ms(ms: float) -> float:
	return (jd_tt_from_ms(ms) - 2451545.0) / 36525.0

static func solve_kepler(m_deg: float, e: float) -> float:
	var E := m_deg + e * sind(m_deg) * 180.0 / PI
	for i in 8:
		var dm := m_deg - (E - e * 180.0 / PI * sind(E))
		E += dm / (1.0 - e * cosd(E))
	return E

# 日心 J2000 黄道直角坐标 (au)。m_override_deg 有效(> -1e8)时用指定平近点角(轨道线采样)
static func heliocentric(name: String, t: float, m_override_deg: float = -1.0e9) -> Vector3:
	var p: Dictionary = ELEM[name]
	var el: Array = p["el"]
	var rate: Array = p["rate"]
	var a := float(el[0]) + float(rate[0]) * t
	var e := float(el[1]) + float(rate[1]) * t
	var inc := float(el[2]) + float(rate[2]) * t
	var L := float(el[3]) + float(rate[3]) * t
	var wb := float(el[4]) + float(rate[4]) * t
	var om := float(el[5]) + float(rate[5]) * t
	var w := wb - om
	var m := norm360(L - wb)
	if m_override_deg > -1.0e8:
		m = norm360(m_override_deg)
	var E := solve_kepler(m, e)
	var xp := a * (cosd(E) - e)
	var yp := a * sqrt(1.0 - e * e) * sind(E)
	var cw := cosd(w); var sw := sind(w); var c_o := cosd(om); var s_o := sind(om)
	var ci := cosd(inc); var si := sind(inc)
	return Vector3(
		(cw * c_o - sw * s_o * ci) * xp + (-sw * c_o - cw * s_o * ci) * yp,
		(cw * s_o + sw * c_o * ci) * xp + (-sw * s_o + cw * c_o * ci) * yp,
		(sw * si) * xp + (cw * si) * yp
	)

# 轨道线采样: 固定根数, 平近点角扫 0..360
static func orbit_point(name: String, t: float, m_deg: float) -> Vector3:
	return heliocentric(name, t, m_deg)

# 月球地心黄道球坐标 (of-date): {lon(deg), lat(deg), dist(km)} —— Meeus 截断
static func moon_geocentric(t: float) -> Dictionary:
	var lp := 218.3164477 + 481267.88123421 * t - 0.0015786 * t * t
	var d := 297.8501921 + 445267.1114034 * t - 0.0018819 * t * t
	var m := 357.5291092 + 35999.0502909 * t - 0.0001536 * t * t
	var mp := 134.9633964 + 477198.8675055 * t + 0.0087414 * t * t
	var f := 93.2720950 + 483202.0175233 * t - 0.0036539 * t * t
	var lon := lp + 6.288774 * sind(mp) + 1.274027 * sind(2 * d - mp) + 0.658314 * sind(2 * d) \
		+ 0.213618 * sind(2 * mp) - 0.185116 * sind(m) - 0.114332 * sind(2 * f) \
		+ 0.058793 * sind(2 * d - 2 * mp) + 0.057066 * sind(2 * d - m - mp) + 0.053322 * sind(2 * d + mp) \
		+ 0.045758 * sind(2 * d - m) - 0.040923 * sind(m - mp) - 0.034720 * sind(d) - 0.030383 * sind(m + mp)
	var lat := 5.128122 * sind(f) + 0.280602 * sind(mp + f) + 0.277693 * sind(mp - f) \
		+ 0.173237 * sind(2 * d - f) + 0.055413 * sind(2 * d + f - mp)
	var dist := 385000.56 - 20905.355 * cosd(mp) - 3699.111 * cosd(2 * d - mp) - 2955.968 * cosd(2 * d)
	return {"lon": norm360(lon), "lat": lat, "dist": dist}

# 平黄赤交角 (deg, IAU1980)
static func obliquity(t: float) -> float:
	return 23.43929111 - 0.01300417 * t - 1.639e-7 * t * t + 5.036e-7 * t * t * t

# 格林尼治平恒星时 GMST (deg)。jd_ut: UTC 儒略日
static func gmst_deg(jd_ut: float) -> float:
	var t := (jd_ut - 2451545.0) / 36525.0
	return norm360(280.46061837 + 360.98564736629 * (jd_ut - 2451545.0) \
		+ 0.000387933 * t * t - t * t * t / 38710000.0)

# 太阳地心视黄经 (deg, of-date) —— 供直下点诊断
static func sun_apparent_lon(t: float) -> float:
	var e := heliocentric("earth", t)
	var geo := norm360(rad_to_deg(atan2(-e.y, -e.x)))
	var pr := (5028.796195 * t + 1.1054348 * t * t) / 3600.0
	return norm360(geo + pr - 0.005691)

# 太阳直下点经度 (deg, 东经为正, -180..180) —— 与 tools/coords/rotation.mjs subSolar 对拍
static func subsolar_lon_at(t: float, sim_ms: float) -> float:
	var lon_ecl := sun_apparent_lon(t)
	var ep := deg_to_rad(obliquity(t))
	var lo := deg_to_rad(lon_ecl)
	var ye := sin(lo) * cos(ep)
	var ra := norm360(rad_to_deg(atan2(ye, cos(lo))))
	var lon := norm360(ra - gmst_deg(jd_from_ms(sim_ms)))
	if lon > 180.0:
		lon -= 360.0
	return lon
