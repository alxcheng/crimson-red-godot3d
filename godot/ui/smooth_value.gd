class_name SmoothValue
extends RefCounted
## Spring-damper animation primitive for EVERY gradual UI change (position, size, colour channel,
## alpha, scale, bar fill, glow, shake...). Set `target` whenever you like, call `update(dt)` once per
## frame, draw with `value`. Changing the target never resets velocity, so it can change on a dime.
##
## `speed` is the spring's natural frequency in rad/s (the old "BOX_SPEED"-style rate): higher is
## snappier. `damping_ratio` 1.0 = critically damped (no overshoot, the default); < 1.0 overshoots and
## settles (use for pops, pulses and "bounciness"); > 1.0 is sluggish.
##
## The update is the EXACT analytic solution of the spring ODE (not Euler), so the result does not
## depend on the frame rate and a long dt (a hitch) cannot blow it up.
##
## Hover rule: test hover against the element's stationary layout rect, and apply `value` only when
## drawing. Testing the animated rect creates a hover/unhover feedback loop.

const SETTLE_DISTANCE := 0.0005
const SETTLE_VELOCITY := 0.005

var value: float
var target: float
var velocity := 0.0
var speed: float
var damping_ratio: float


func _init(start: float = 0.0, p_speed: float = 12.0, p_damping_ratio: float = 1.0) -> void:
	value = start
	target = start
	speed = p_speed
	damping_ratio = p_damping_ratio


func update(dt: float) -> void:
	if dt <= 0.0:
		return
	var w := speed
	var z := damping_ratio
	var e0 := value - target
	var v0 := velocity
	var e: float
	var v: float
	if w <= 0.0:
		return
	if absf(z - 1.0) < 0.0001:
		var decay := exp(-w * dt)
		var c := v0 + w * e0
		e = (e0 + c * dt) * decay
		v = (v0 - w * c * dt) * decay
	elif z < 1.0:
		var wd := w * sqrt(1.0 - z * z)
		var decay := exp(-z * w * dt)
		var c := cos(wd * dt)
		var s := sin(wd * dt)
		e = decay * (e0 * c + (v0 + z * w * e0) / wd * s)
		v = decay * (v0 * c - (z * w * v0 + w * w * e0) / wd * s)
	else:
		var root := w * sqrt(z * z - 1.0)
		var r1 := -w * z + root
		var r2 := -w * z - root
		var c2 := (v0 - r1 * e0) / (r2 - r1)
		var c1 := e0 - c2
		var d1 := exp(r1 * dt)
		var d2 := exp(r2 * dt)
		e = c1 * d1 + c2 * d2
		v = c1 * r1 * d1 + c2 * r2 * d2
	value = target + e
	velocity = v
	if absf(e) < SETTLE_DISTANCE and absf(v) < SETTLE_VELOCITY:
		value = target
		velocity = 0.0


## Jump to `v` with no motion (first display, a screen that should not fly in from the corner).
func snap(v: float) -> void:
	value = v
	target = v
	velocity = 0.0


## Add an instantaneous velocity: pulses, hit "pops", shake kicks (target stays put).
func kick(extra_velocity: float) -> void:
	velocity += extra_velocity


func is_settled() -> bool:
	return value == target and velocity == 0.0
