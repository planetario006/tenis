class_name BallPhysics
extends RefCounted
## Física de la pelota de tenis:
##  - gravedad + arrastre cuadrático (Cd ≈ 0.55)
##  - efecto Magnus: coef. de sustentación Cl = 1 / (2 + v/(R·ω))  (Mehta)
##  - rebote con modelo de impulso rígido (restitución normal + fricción de Coulomb/rodadura),
##    bola como cáscara fina I = 2/3 m R². El topspin "muerde" y se frena menos; el cortado derrapa.
## Convención de espín: ω vector en rad/s. Topspin para una bola que viaja en d: ω = UP × d · |ω|.

const R := Court.BALL_R
const MASS := 0.0577
const RHO := 1.2
const AREA := PI * R * R
const CD := 0.55
const G := 9.81
const K_INERTIA := 2.0 / 3.0
const SPIN_DECAY := 0.10

static func accel(v: Vector3, w: Vector3) -> Vector3:
	var a := Vector3(0.0, -G, 0.0)
	var sp := v.length()
	if sp > 0.05:
		a -= v * (0.5 * RHO * CD * AREA * sp / MASS)
		var wl := w.length()
		if wl > 0.5:
			var s := R * wl / sp
			var cl := 1.0 / (2.0 + 1.0 / s)
			var f := 0.5 * RHO * AREA * cl * sp * sp / MASS
			var dir := w.cross(v)
			var dl := dir.length()
			if dl > 1e-6:
				a += dir * (f / dl)
	return a

## Un paso RK4. Devuelve [pos, vel, omega].
static func step(p: Vector3, v: Vector3, w: Vector3, dt: float) -> Array:
	var k1v := accel(v, w)
	var v2 := v + k1v * (dt * 0.5)
	var k2v := accel(v2, w)
	var v3 := v + k2v * (dt * 0.5)
	var k3v := accel(v3, w)
	var v4 := v + k3v * dt
	var k4v := accel(v4, w)
	var np := p + (v + 2.0 * v2 + 2.0 * v3 + v4) * (dt / 6.0)
	var nv := v + (k1v + 2.0 * k2v + 2.0 * k3v + k4v) * (dt / 6.0)
	return [np, nv, w * exp(-SPIN_DECAY * dt)]

## Rebote contra el suelo. Devuelve [vel', omega'].
static func bounce(v: Vector3, w: Vector3, e: float, mu: float) -> Array:
	var rc := Vector3(0.0, -R, 0.0)
	var vc := v + w.cross(rc)                     # velocidad del punto de contacto
	var ut := Vector3(vc.x, 0.0, vc.z)
	var ut_len := ut.length()
	var jn := -(1.0 + e) * v.y                    # impulso normal (masa unidad)
	var vo := v
	var wo := w
	# la fricción también resta algo de rebote vertical: el cortado derrapa y queda más bajo
	vo.y = -e * (1.0 - 0.12 * clampf(ut_len / 30.0, 0.0, 1.0)) * v.y
	if ut_len > 1e-4:
		var that := -ut / ut_len
		var j_stick := ut_len / (1.0 + 1.0 / K_INERTIA)
		var j := minf(mu * jn, j_stick)
		vo += that * j
		wo += Vector3(-that.z, 0.0, that.x) * (j / (K_INERTIA * R))
	return [vo, wo]

## Trayectoria desde (p0,v0,w0) hasta el primer contacto con el suelo.
static func trace(p0: Vector3, v0: Vector3, w0: Vector3, dt: float = 1.0 / 90.0, max_t: float = 4.0, far: float = 40.0) -> Dictionary:
	var p := p0
	var v := v0
	var w := w0
	var t := 0.0
	var net_clear := 99.0
	var crossed := false
	while t < max_t:
		var r := step(p, v, w, dt)
		var np: Vector3 = r[0]
		var nv: Vector3 = r[1]
		if not crossed and p.z * np.z <= 0.0 and p.z != np.z:
			var f := p.z / (p.z - np.z)
			var yc := lerpf(p.y, np.y, f)
			var xc := lerpf(p.x, np.x, f)
			net_clear = yc - (Court.net_height(xc) + R)
			crossed = true
		if np.y <= R and nv.y < 0.0:
			var f2 := (p.y - R) / maxf(p.y - np.y, 1e-6)
			return {"land": p.lerp(np, f2), "t": t + dt * f2, "net_clear": net_clear, "crossed": crossed, "vel": v.lerp(nv, f2)}
		if Vector2(np.x - p0.x, np.z - p0.z).length() > far:
			break
		p = np
		v = nv
		w = r[2]
		t += dt
	return {"land": p, "t": t, "net_clear": net_clear, "crossed": crossed, "vel": v}

## Predice la trayectoria completa (incluye botes) como muestras para IA / barra de timing.
static func predict(p0: Vector3, v0: Vector3, w0: Vector3, surface: Dictionary, duration: float = 3.0, dt: float = 1.0 / 60.0) -> Array:
	var out: Array = []
	var p := p0
	var v := v0
	var w := w0
	var t := 0.0
	var bounces := 0
	out.append({"t": 0.0, "p": p, "v": v, "b": 0})
	while t < duration:
		var r := step(p, v, w, dt)
		var np: Vector3 = r[0]
		var nv: Vector3 = r[1]
		var nw: Vector3 = r[2]
		if p.z * np.z < 0.0:
			var f := p.z / (p.z - np.z)
			if lerpf(p.y, np.y, f) < Court.net_height(lerpf(p.x, np.x, f)) + R:
				break                                   # la bola muere en la red
		if np.y <= R and nv.y < 0.0:
			var f2 := (p.y - R) / maxf(p.y - np.y, 1e-6)
			var bp := p.lerp(np, f2)
			var rb := bounce(v.lerp(nv, f2), nw, surface.e, surface.mu)
			np = bp
			np.y = R
			nv = rb[0]
			nw = rb[1]
			bounces += 1
		p = np
		v = nv
		w = nw
		t += dt
		out.append({"t": t, "p": p, "v": v, "b": bounces})
	return out

# ---------------------------------------------------------------------------------------------
# Planificador de golpes: encuentra el ángulo de salida (o la velocidad) que lleva la bola
# a un punto objetivo con la física completa (arrastre + Magnus), respetando la altura de red.
# ---------------------------------------------------------------------------------------------

static func spin_vector(dnorm: Vector3, spin: float) -> Vector3:
	return Vector3.UP.cross(dnorm) * spin   # spin > 0 topspin, < 0 backspin

static func _launch(dnorm: Vector3, speed: float, theta: float) -> Vector3:
	return (dnorm * cos(theta) + Vector3.UP * sin(theta)) * speed

static func _range(p0: Vector3, dnorm: Vector3, speed: float, theta: float, w: Vector3, dist: float) -> Dictionary:
	var tr := trace(p0, _launch(dnorm, speed, theta), w, 1.0 / 90.0, 3.5, dist + 8.0)
	var land: Vector3 = tr.land
	var d := Vector2(land.x - p0.x, land.z - p0.z).dot(Vector2(dnorm.x, dnorm.z))
	return {"d": d, "clear": tr.net_clear, "crossed": tr.crossed, "land": land}

static func solve_angle(p0: Vector3, dnorm: Vector3, dist: float, speed: float, w: Vector3, margin: float) -> Dictionary:
	var th_prev := deg_to_rad(-10.0)
	var r_prev := _range(p0, dnorm, speed, th_prev, w, dist)
	var best := {"ok": false, "theta": th_prev, "err": 1e9, "clear": -9.0}
	var th := th_prev
	while th < deg_to_rad(52.0):
		th += deg_to_rad(3.0)
		var r := _range(p0, dnorm, speed, th, w, dist)
		var e0: float = r_prev.d - dist
		var e1: float = r.d - dist
		if (e0 <= 0.0 and e1 >= 0.0) or (e0 >= 0.0 and e1 <= 0.0):
			var lo := th_prev
			var hi := th
			var rm := r
			for i in 9:
				var mid := 0.5 * (lo + hi)
				rm = _range(p0, dnorm, speed, mid, w, dist)
				if ((rm.d - dist) < 0.0) == (e0 < 0.0):
					lo = mid
				else:
					hi = mid
			var cand_th := 0.5 * (lo + hi)
			var cl: float = rm.clear
			if cl >= margin:
				return {"ok": true, "theta": cand_th, "err": absf(rm.d - dist), "clear": cl}
			if cl > best.clear:
				best = {"ok": false, "theta": cand_th, "err": absf(rm.d - dist), "clear": cl}
		th_prev = th
		r_prev = r
	return best

static func solve_speed(p0: Vector3, dnorm: Vector3, dist: float, theta: float, w: Vector3, v_lo: float, v_hi: float) -> Dictionary:
	var lo := v_lo
	var hi := v_hi
	var rm := _range(p0, dnorm, hi, theta, w, dist)
	if rm.d < dist:
		return {"ok": false, "speed": hi, "clear": rm.clear}
	for i in 12:
		var mid := 0.5 * (lo + hi)
		rm = _range(p0, dnorm, mid, theta, w, dist)
		if rm.d < dist:
			lo = mid
		else:
			hi = mid
	var sp := 0.5 * (lo + hi)
	rm = _range(p0, dnorm, sp, theta, w, dist)
	return {"ok": true, "speed": sp, "clear": rm.clear}

## shot: ver Shots.TYPES. power: 0..1. Devuelve {v, w, speed, theta, ok}
static func plan(p0: Vector3, target: Vector3, shot: Dictionary, power: float, side_spin: float = 0.0) -> Dictionary:
	var flat := Vector3(target.x - p0.x, 0.0, target.z - p0.z)
	var dist := maxf(flat.length(), 1.0)
	var dn := flat / dist
	var spin := lerpf(shot.spin_min, shot.spin_max, power)
	var w := spin_vector(dn, spin) + Vector3.UP * side_spin
	if shot.mode == "speed":
		var th := deg_to_rad(shot.angle)
		var s := solve_speed(p0, dn, dist, th, w, 4.0, 45.0)
		return {"v": _launch(dn, s.speed, th), "w": w, "speed": s.speed, "theta": th, "ok": s.ok, "clear": s.clear}
	var speed := lerpf(shot.v_min, shot.v_max, power)
	var res := {}
	for attempt in 9:
		res = solve_angle(p0, dn, dist, speed, w, shot.net_margin)
		if res.ok:
			break
		speed *= 0.93
	return {"v": _launch(dn, speed, res.theta), "w": w, "speed": speed, "theta": res.theta, "ok": res.ok, "clear": res.clear}
