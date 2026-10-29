# Dev tool (not part of test_3d): times the sandbox sim with 28 units. Run: godot --headless --path . --script res://tests/perf_sim.gd
extends SceneTree
const Sandbox := preload("res://sim/sandbox_battle.gd")
func _initialize() -> void:
	var b = Sandbox.new()
	b.spawn_party()
	for i in 24:
		b.spawn("skeleton" if i % 2 == 0 else "goblin", Vector2(8.0 + (i % 6) * 0.9, -5.0 + (i / 6) * 2.0))
	var t0 := Time.get_ticks_usec()
	var worst := 0
	var n := 1200
	for i in n:
		var a := Time.get_ticks_usec()
		b.tick()
		b.take_events()
		worst = maxi(worst, Time.get_ticks_usec() - a)
	var total := Time.get_ticks_usec() - t0
	print("SIM units=%d ticks=%d avg=%.2f ms worst=%.2f ms (budget at 30 Hz: 33 ms)" % [b.units.size(), n, total / 1000.0 / n, worst / 1000.0])
	quit()
