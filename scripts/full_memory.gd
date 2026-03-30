extends Control

## Full Memory Assembly — All 4 fragments shown together. The complete truth.

@onready var dialogue: Node = $DialogueSystem

var time_elapsed := 0.0
var phase: int = 0 # 0=assembly, 1=dialogue, 2=guilt_emerges, 3=done
var fragment_positions: Array[Vector2] = [
	Vector2(320, 220), Vector2(960, 220),
	Vector2(320, 480), Vector2(960, 480)
]
var fragment_alphas: Array[float] = [0.0, 0.0, 0.0, 0.0]
var fragment_reveal_index := 0
var reveal_timer := 0.0
var guilt_alpha := 0.0
var pulse_time := 0.0


func _ready() -> void:
	dialogue.dialogue_finished.connect(_on_dialogue_done)


func _process(delta: float) -> void:
	time_elapsed += delta
	pulse_time += delta

	match phase:
		0: # Reveal fragments one by one
			reveal_timer += delta
			if reveal_timer > 1.2 and fragment_reveal_index < 4:
				fragment_reveal_index += 1
				reveal_timer = 0.0

			for i in range(fragment_reveal_index):
				fragment_alphas[i] = min(1.0, fragment_alphas[i] + delta * 0.8)

			if fragment_reveal_index >= 4 and time_elapsed > 7.0:
				phase = 1
				_start_dialogue()

		1: pass # Dialogue
		2: # Guilt emerges
			guilt_alpha = min(1.0, guilt_alpha + delta * 0.4)
			if time_elapsed > 3.0:
				phase = 3
		3:
			GameManager.advance_phase()

	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.04, 0.04, 0.06))
	# Draw connecting lines between fragments
	for i in range(fragment_reveal_index):
		for j in range(i + 1, fragment_reveal_index):
			var alpha: float = min(fragment_alphas[i], fragment_alphas[j]) * 0.15
			draw_line(fragment_positions[i], fragment_positions[j], Color(0.5, 0.5, 0.55, alpha), 1.0)

	# Draw fragment placeholders
	var fragment_ids: Array[String] = GameManager.fragment_order
	var fragment_colors: Dictionary = {
		GameManager.GOOD_1: Color(0.9, 0.65, 0.4),
		GameManager.GOOD_2: Color(0.85, 0.6, 0.45),
		GameManager.BAD_1: Color(0.4, 0.45, 0.65),
		GameManager.BAD_2: Color(0.6, 0.2, 0.2)
	}
	var fragment_labels: Dictionary = {
		GameManager.GOOD_1: "Happy Times",
		GameManager.GOOD_2: "The Promise",
		GameManager.BAD_1: "Tears",
		GameManager.BAD_2: "The Accident"
	}

	for i in range(mini(fragment_reveal_index, 4)):
		if i >= fragment_ids.size():
			break
		var fid: String = fragment_ids[i]
		var pos: Vector2 = fragment_positions[i]
		var alpha: float = fragment_alphas[i]
		var col: Color = fragment_colors.get(fid, Color.WHITE)
		col.a = alpha * 0.6

		# Try to load actual texture
		var tex_path := GameManager.get_fragment_texture_path(fid)
		if ResourceLoader.exists(tex_path):
			var tex: Texture2D = load(tex_path) as Texture2D
			if tex:
				draw_texture_rect(tex, Rect2(pos - Vector2(120, 80), Vector2(240, 160)), false, Color(1, 1, 1, alpha))
		else:
			# Placeholder rectangle
			draw_rect(Rect2(pos - Vector2(100, 65), Vector2(200, 130)), col)
			draw_rect(Rect2(pos - Vector2(100, 65), Vector2(200, 130)), Color(col.r, col.g, col.b, alpha * 0.4), false, 2.0)

		# Label
		var font := ThemeDB.fallback_font
		var label: String = fragment_labels.get(fid, "")
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		draw_string(font, pos + Vector2(-text_size.x * 0.5, 80), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.7, 0.75, alpha * 0.8))

	# Center pulse when all revealed
	if fragment_reveal_index >= 4:
		var center := Vector2(640, 360)
		var pulse_alpha := sin(pulse_time * 2.0) * 0.1 + 0.15
		draw_circle(center, 30, Color(0.6, 0.55, 0.6, pulse_alpha))

	# Guilt emergence
	if phase >= 2:
		var center := Vector2(640, 680 - guilt_alpha * 300)
		# Large dark shape
		var guilt_col := Color(0.1, 0.08, 0.12, guilt_alpha * 0.9)
		draw_circle(center, 80 * guilt_alpha, guilt_col)
		# Tendrils
		for i in range(5):
			var angle := (float(i) / 5.0) * TAU + pulse_time * 0.3
			var tendril_end := center + Vector2(cos(angle), sin(angle)) * 120 * guilt_alpha
			draw_line(center, tendril_end, Color(0.15, 0.1, 0.18, guilt_alpha * 0.5), 3.0)
		# Eyes
		draw_circle(center + Vector2(-20, -10), 8, Color(0.4, 0.1, 0.1, guilt_alpha))
		draw_circle(center + Vector2(20, -10), 8, Color(0.4, 0.1, 0.1, guilt_alpha))


func _start_dialogue() -> void:
	var lines: Array[Dictionary] = [
		{"speaker": "Blame", "text": "She gave her life for us.", "color": GameManager.get_blame_color_light()},
		{"speaker": "Denial", "text": "She gave her life for us.", "color": GameManager.get_denial_color_light()},
		{"speaker": "", "text": "...", "color": Color(0.4, 0.4, 0.45)},
		{"speaker": "Denial", "text": "And I forgot her.", "color": GameManager.get_denial_color_light()},
		{"speaker": "Blame", "text": "I remembered her wrong. I thought remembering meant punishing us.", "color": GameManager.get_blame_color_light()},
		{"speaker": "Denial", "text": "She wouldn't want that.", "color": GameManager.get_denial_color_light()},
		{"speaker": "Blame", "text": "No. She wouldn't.", "color": GameManager.get_blame_color_light()},
		{"speaker": "Blame", "text": "So why are we still doing this to ourselves?", "color": GameManager.get_blame_color_light()},
		{"speaker": "", "text": "Something stirs in the darkness behind them...", "color": Color(0.4, 0.3, 0.35)},
	]
	dialogue.play_dialogue(lines)


func _on_dialogue_done() -> void:
	if phase == 1:
		phase = 2
		time_elapsed = 0.0
