extends Control

## Fatality — Two shapes merge into one. A burst of color shatters GUILT.
## Screen floods with light.

var time_elapsed := 0.0
var phase: int = 0 # 0=merge, 1=burst, 2=flood, 3=done

var p1_pos := Vector2(400, 400)
var p2_pos := Vector2(880, 400)
var merge_target := Vector2(640, 400)
var merged := false
var burst_particles: Array[Dictionary] = []
var burst_radius := 0.0
var flood_alpha := 0.0
var boss_fade := 1.0
var boss_shatter_particles: Array[Dictionary] = []


func _ready() -> void:
	pass


func _process(delta: float) -> void:
	time_elapsed += delta

	match phase:
		0: # Shapes approach and merge
			var t: float = minf(1.0, time_elapsed * 0.3)
			t = t * t * (3.0 - 2.0 * t)
			p1_pos = Vector2(400, 400).lerp(merge_target, t)
			p2_pos = Vector2(880, 400).lerp(merge_target, t)
			if t >= 0.98 and not merged:
				merged = true
				phase = 1
				time_elapsed = 0.0
				_create_burst()

		1: # Color burst
			burst_radius += delta * 600
			boss_fade = max(0, boss_fade - delta * 1.5)
			for p: Dictionary in burst_particles:
				p.pos += p.vel * delta
				p.alpha = max(0, p.alpha - delta * 0.4)
			for p: Dictionary in boss_shatter_particles:
				p.pos += p.vel * delta
				p.alpha = max(0, p.alpha - delta * 0.8)
			if time_elapsed > 2.5:
				phase = 2
				time_elapsed = 0.0

		2: # Screen floods with light
			flood_alpha = min(1.0, time_elapsed * 0.5)
			if time_elapsed > 3.0:
				phase = 3
		3:
			GameManager.advance_phase()

	queue_redraw()


func _create_burst() -> void:
	# Color burst particles
	for i in range(60):
		var angle := randf() * TAU
		var speed := randf_range(100, 500)
		var col := Color(
			randf_range(0.5, 1.0),
			randf_range(0.4, 0.9),
			randf_range(0.3, 0.8),
		)
		burst_particles.append({
			"pos": merge_target,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"size": randf_range(3, 12),
			"color": col,
			"alpha": 1.0,
			"type": randi() % 3
		})
	# Boss shatter
	for i in range(20):
		var angle := randf() * TAU
		var speed := randf_range(50, 200)
		boss_shatter_particles.append({
			"pos": Vector2(640, 250),
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"size": randf_range(5, 15),
			"alpha": 1.0
		})


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.03, 0.03, 0.05))
	# Boss remnant (fading)
	if boss_fade > 0:
		var bp := Vector2(640, 250)
		draw_circle(bp, 70 * boss_fade, Color(0.08, 0.06, 0.1, boss_fade * 0.7))
		draw_circle(bp + Vector2(-22, -12), 10 * boss_fade, Color(0.5, 0.1, 0.12, boss_fade * 0.5))
		draw_circle(bp + Vector2(22, -12), 10 * boss_fade, Color(0.5, 0.1, 0.12, boss_fade * 0.5))

	# Boss shatter particles
	for p: Dictionary in boss_shatter_particles:
		draw_rect(Rect2(p.pos - Vector2(p.size, p.size) * 0.5, Vector2(p.size, p.size)),
			Color(0.15, 0.1, 0.18, p.alpha))

	if not merged:
		# P1 Blame approaching
		draw_rect(Rect2(p1_pos - Vector2(22, 22), Vector2(44, 44)), GameManager.get_blame_color())
		# P2 Denial approaching
		draw_circle(p2_pos, 24, GameManager.get_denial_color())
	else:
		# Merged shape — a new form, blending both colors
		var merged_col := GameManager.get_blame_color().lerp(GameManager.get_denial_color(), 0.5)
		merged_col = merged_col.lerp(Color.WHITE, 0.2)
		# Draw as pentagon — neither circle nor square, something new
		var pts := PackedVector2Array()
		for i in range(6):
			var angle := (float(i) / 6.0) * TAU - PI / 2.0
			pts.append(merge_target + Vector2(cos(angle), sin(angle)) * 35)
		draw_colored_polygon(pts, merged_col)
		# Inner glow
		draw_circle(merge_target, 20, Color(1, 0.95, 0.85, 0.4))

	# Burst ring
	if phase >= 1:
		var ring_alpha: float = maxf(0.0, 1.0 - burst_radius / 800.0)
		draw_arc(merge_target, burst_radius, 0, TAU, 64, Color(1, 0.9, 0.7, ring_alpha * 0.5), 4.0)

	# Burst particles
	for p: Dictionary in burst_particles:
		var col: Color = p.color
		col.a = p.alpha
		match p.type:
			0: draw_circle(p.pos, p.size, col)
			1: draw_rect(Rect2(p.pos - Vector2(p.size, p.size), Vector2(p.size * 2, p.size * 2)), col)
			2:
				var tri := PackedVector2Array([
					p.pos + Vector2(0, -p.size),
					p.pos + Vector2(p.size, p.size),
					p.pos + Vector2(-p.size, p.size)
				])
				draw_colored_polygon(tri, col)

	# Light flood
	if flood_alpha > 0:
		draw_rect(Rect2(0, 0, 1280, 720), Color(1, 0.98, 0.93, flood_alpha))
