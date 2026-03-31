extends Control

## Intro: Grey world. Two shapes emerge from the same fractured point.

@onready var dialogue: Node = $DialogueSystem

var time_elapsed: float = 0.0
var phase: int = 0 # 0=fade_in, 1=crack, 2=shapes_emerge, 3=dialogue, 4=done
var crack_progress: float = 0.0
var shape1_pos: Vector2 = Vector2(640, 360)
var shape2_pos: Vector2 = Vector2(640, 360)
var shape1_target: Vector2 = Vector2(400, 360)
var shape2_target: Vector2 = Vector2(880, 360)
var shape_alpha: float = 0.0
var fade_alpha: float = 1.0 # starts black, fades in
var particles: Array[Dictionary] = []


func _ready() -> void:
	phase = 0
	time_elapsed = 0.0
	# Generate floating particles
	for i in range(30):
		particles.append({
			"pos": Vector2(randf_range(0, 1280), randf_range(0, 720)),
			"speed": randf_range(5, 20),
			"size": randf_range(1, 3),
			"alpha": randf_range(0.1, 0.3)
		})
	dialogue.dialogue_finished.connect(_on_dialogue_done)


func _process(delta: float) -> void:
	time_elapsed += delta

	match phase:
		0: # Fade from black
			fade_alpha = max(0.0, 1.0 - time_elapsed * 0.5)
			if time_elapsed > 2.5:
				phase = 1
				time_elapsed = 0.0
		1: # Crack appears in center
			crack_progress = min(1.0, time_elapsed * 0.4)
			if time_elapsed > 3.0:
				phase = 2
				time_elapsed = 0.0
		2: # Two shapes emerge and drift apart
			var t: float = minf(1.0, time_elapsed * 0.3)
			t = t * t * (3.0 - 2.0 * t) # smoothstep
			shape1_pos = Vector2(640, 360).lerp(shape1_target, t)
			shape2_pos = Vector2(640, 360).lerp(shape2_target, t)
			shape_alpha = min(1.0, time_elapsed * 0.5)
			if time_elapsed > 4.0:
				phase = 3
				_start_dialogue()
		3: # Dialogue playing
			pass
		4: # Done, advance
			fade_alpha = min(1.0, time_elapsed * 0.8)
			if time_elapsed > 1.5:
				GameManager.advance_phase()

	# Update particles
	for p: Dictionary in particles:
		p.pos.y -= p.speed * delta
		if p.pos.y < -10:
			p.pos.y = 730
			p.pos.x = randf_range(0, 1280)

	queue_redraw()


func _draw() -> void:
	# Grey particles
	for p: Dictionary in particles:
		draw_circle(p.pos, p.size, Color(0.5, 0.5, 0.55, p.alpha * (1.0 - fade_alpha)))

	# Center crack
	if phase >= 1:
		var crack_len := crack_progress * 200.0
		var center := Vector2(640, 360)
		var crack_col := Color(0.6, 0.6, 0.65, crack_progress * 0.8)
		draw_line(center + Vector2(0, -crack_len), center + Vector2(0, crack_len), crack_col, 2.0)
		# Branch cracks
		if crack_progress > 0.3:
			var bp := (crack_progress - 0.3) / 0.7
			draw_line(center, center + Vector2(-40 * bp, -60 * bp), crack_col, 1.5)
			draw_line(center, center + Vector2(35 * bp, -45 * bp), crack_col, 1.5)
			draw_line(center, center + Vector2(-25 * bp, 50 * bp), crack_col, 1.5)

	# Two characters emerging
	if phase >= 2:
		# P2 Denial
		var denial_mod := Color(1, 1, 1, shape_alpha * 0.85)
		var d_frame: int = GameManager.anim_frame(time_elapsed, 4, 6.0)
		GameManager.draw_denial_sprite(self, shape1_pos + Vector2(0, 35), d_frame, 0, 2.2, false, denial_mod)

		# P1 Blame
		var blame_mod := Color(1, 1, 1, shape_alpha * 0.85)
		var b_frame: int = GameManager.anim_frame(time_elapsed, 4, 6.0)
		GameManager.draw_blame_sprite(self, shape2_pos + Vector2(0, 30), b_frame, 5, 1.6, true, blame_mod)

	# Fade overlay
	if fade_alpha > 0.01:
		draw_rect(Rect2(0, 0, 1280, 720), Color(0, 0, 0, fade_alpha))


func _start_dialogue() -> void:
	var lines: Array[Dictionary] = [
		{"speaker": "", "text": "A grey world. Silent. Still.", "color": Color(0.6, 0.6, 0.65)},
		{"speaker": "", "text": "Something cracks at the center.", "color": Color(0.6, 0.6, 0.65)},
		{"speaker": "", "text": "Two shapes emerge... from the same fracture.", "color": Color(0.6, 0.6, 0.65)},
		{"speaker": "", "text": "They don't know each other. They don't know themselves.", "color": Color(0.6, 0.6, 0.65)},
		{"speaker": "", "text": "But they feel the tension.", "color": Color(0.5, 0.5, 0.6)},
	]
	dialogue.play_dialogue(lines)


func _on_dialogue_done() -> void:
	phase = 4
	time_elapsed = 0.0
