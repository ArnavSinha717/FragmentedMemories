extends Control

## Transition: Fighting stops. They realize they're the same person. They walk together.

@onready var dialogue: Node = $DialogueSystem

var time_elapsed: float = 0.0
var phase: int = 0 # 0=fade_in, 1=walking_together, 2=dialogue, 3=fade_out
var shape1_pos := Vector2(400, 400)
var shape2_pos := Vector2(880, 400)
var target_pos := Vector2(640, 400)
var walk_progress := 0.0
var particles: Array[Dictionary] = []


func _ready() -> void:
	dialogue.dialogue_finished.connect(_on_dialogue_done)
	# Spawn gentle particles
	for i in range(20):
		particles.append({
			"pos": Vector2(randf_range(0, 1280), randf_range(0, 720)),
			"speed": Vector2(randf_range(-10, 10), randf_range(-15, -5)),
			"size": randf_range(1, 3),
			"alpha": randf_range(0.05, 0.2)
		})


func _process(delta: float) -> void:
	time_elapsed += delta

	match phase:
		0: # Fade in
			if time_elapsed > 1.5:
				phase = 1
				time_elapsed = 0.0
		1: # They walk toward each other
			walk_progress = min(1.0, time_elapsed * 0.2)
			var t := walk_progress * walk_progress * (3.0 - 2.0 * walk_progress) # smoothstep
			shape1_pos = Vector2(400, 400).lerp(Vector2(560, 400), t)
			shape2_pos = Vector2(880, 400).lerp(Vector2(720, 400), t)
			if time_elapsed > 5.5:
				phase = 2
				_start_dialogue()
		2: pass # Dialogue
		3: # Fade out
			if time_elapsed > 1.5:
				GameManager.advance_phase()

	# Update particles
	for p: Dictionary in particles:
		p.pos += p.speed * delta
		if p.pos.y < -10: p.pos.y = 730
		if p.pos.x < -10: p.pos.x = 1290
		if p.pos.x > 1290: p.pos.x = -10

	queue_redraw()


func _draw() -> void:
	# Soft particles
	for p: Dictionary in particles:
		draw_circle(p.pos, p.size, Color(0.5, 0.5, 0.55, p.alpha))

	# A connecting line that grows as they approach
	if phase >= 1:
		var line_alpha := walk_progress * 0.3
		draw_line(shape1_pos, shape2_pos, Color(0.5, 0.45, 0.5, line_alpha), 1.5)
		# Midpoint glow
		var mid := (shape1_pos + shape2_pos) * 0.5
		draw_circle(mid, 8 * walk_progress, Color(0.6, 0.55, 0.6, walk_progress * 0.3))

	# P2 Denial
	var d_frame: int = GameManager.anim_frame(time_elapsed, 2, 3.0)
	GameManager.draw_denial_sprite(self, shape1_pos + Vector2(0, 30), d_frame, 0, 2.2, false)

	# P1 Blame
	var b_frame: int = GameManager.anim_frame(time_elapsed, 4, 6.0)
	GameManager.draw_blame_sprite(self, shape2_pos + Vector2(0, 25), b_frame, 5, 1.4, true)

	# Fade
	var fade := 0.0
	if phase == 0:
		fade = max(0.0, 1.0 - time_elapsed * 0.7)
	elif phase == 3:
		fade = min(1.0, time_elapsed * 0.7)
	if fade > 0.01:
		draw_rect(Rect2(0, 0, 1280, 720), Color(0, 0, 0, fade))


func _start_dialogue() -> void:
	var lines: Array[Dictionary] = []

	# Only show the full emotional dialogue if BAD_2 was JUST revealed
	# (i.e. it's the most recent fragment). If it was revealed earlier,
	# the fragment reveal already covered the heavy stuff — keep it brief.
	var frags: Array[String] = GameManager.revealed_fragments
	var bad2_is_latest: bool = frags.size() > 0 and frags[frags.size() - 1] == GameManager.BAD_2

	if bad2_is_latest:
		lines = [
			{"speaker": "Denial", "text": "Why is there so much blood?", "color": GameManager.get_denial_color_light()},
			{"speaker": "", "text": "...", "color": Color(0.4, 0.4, 0.45)},
			{"speaker": "Blame", "text": "...You really don't remember.", "color": GameManager.get_blame_color_light()},
			{"speaker": "Denial", "text": "I don't want to.", "color": GameManager.get_denial_color_light()},
			{"speaker": "Blame", "text": "Neither do I.", "color": GameManager.get_blame_color_light()},
			{"speaker": "", "text": "...", "color": Color(0.4, 0.4, 0.45)},
			{"speaker": "Denial", "text": "But we have to, don't we.", "color": GameManager.get_denial_color_light()},
			{"speaker": "Blame", "text": "...Yeah.", "color": GameManager.get_blame_color_light()},
		]

	# Always end with the cooperative transition lines
	lines.append_array([
		{"speaker": "", "text": "The fighting stops. They walk together now.", "color": Color(0.6, 0.6, 0.65)},
		{"speaker": "", "text": "We can't carry this alone. We have to help each other through it.", "color": Color(0.6, 0.6, 0.65)},
	])

	dialogue.play_dialogue(lines)


func _on_dialogue_done() -> void:
	phase = 3
	time_elapsed = 0.0
