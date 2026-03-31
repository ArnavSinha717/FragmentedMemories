extends Control

## Full Memory Assembly — All 4 fragment images shown together.
## After dialogue, GUILT corrupts the background to black and emerges from the darkness.

@onready var dialogue: Node = $DialogueSystem

var time_elapsed := 0.0
var phase: int = 0 # 0=assembly, 1=dialogue, 2=corruption, 3=guilt_emerges, 4=done
var fragment_positions: Array[Vector2] = [
	Vector2(320, 220), Vector2(960, 220),
	Vector2(320, 480), Vector2(960, 480)
]
var fragment_alphas: Array[float] = [0.0, 0.0, 0.0, 0.0]
var fragment_reveal_index := 0
var reveal_timer := 0.0
var guilt_alpha := 0.0
var pulse_time := 0.0

# Fragment image textures
var fragment_textures: Array = [null, null, null, null]  # Loaded in _ready

# Image paths per fragment ID
var fragment_image_map: Dictionary = {
	"G1": "res://pictures/smiling_friends.png",
	"G2": "res://pictures/bucket_list.png",
	"B1": "res://pictures/sad_crying.png",
	"B2": "res://pictures/dead.png",
}

var fragment_labels_map: Dictionary = {
	"G1": "Happy Times",
	"G2": "The Promise",
	"B1": "Tears",
	"B2": "The Accident",
}


func _ready() -> void:
	dialogue.dialogue_finished.connect(_on_dialogue_done)
	# Pre-load textures for the 4 fragments in their reveal order
	for i in range(mini(4, GameManager.fragment_order.size())):
		var fid: String = GameManager.fragment_order[i]
		var path: String = fragment_image_map.get(fid, "")
		if path != "" and ResourceLoader.exists(path):
			fragment_textures[i] = load(path)


func _process(delta: float) -> void:
	time_elapsed += delta
	pulse_time += delta

	match phase:
		0: # Reveal fragment images one by one
			reveal_timer += delta
			if reveal_timer > 1.5 and fragment_reveal_index < 4:
				fragment_reveal_index += 1
				reveal_timer = 0.0

			for i in range(fragment_reveal_index):
				fragment_alphas[i] = minf(1.0, fragment_alphas[i] + delta * 0.7)

			if fragment_reveal_index >= 4 and time_elapsed > 8.0:
				phase = 1
				_start_dialogue()

		1: pass # Dialogue
		2: # Corruption — GUILT turns everything black
			# Wait for corruption to finish (all shards corrupted)
			if not GameManager.collapse_active:
				phase = 3
				time_elapsed = 0.0
		3: # Guilt emerges from the darkness
			guilt_alpha = minf(1.0, guilt_alpha + delta * 0.25)
			# Fade out fragment images as guilt takes over
			for i in range(4):
				fragment_alphas[i] = maxf(0.0, fragment_alphas[i] - delta * 0.4)
			if time_elapsed > 5.0:
				phase = 4
		4:
			GameManager.advance_phase()

	queue_redraw()


func _draw() -> void:
	# Draw connecting lines between fragments
	for i in range(fragment_reveal_index):
		for j in range(i + 1, fragment_reveal_index):
			var alpha: float = minf(fragment_alphas[i], fragment_alphas[j]) * 0.2
			draw_line(fragment_positions[i], fragment_positions[j], Color(0.5, 0.5, 0.55, alpha), 1.5)

	# Draw the 4 fragment IMAGES
	var fragment_ids: Array[String] = GameManager.fragment_order
	for i in range(mini(fragment_reveal_index, 4)):
		if i >= fragment_ids.size():
			break
		var fid: String = fragment_ids[i]
		var pos: Vector2 = fragment_positions[i]
		var alpha: float = fragment_alphas[i]

		# Draw the actual image
		var tex: Texture2D = fragment_textures[i] as Texture2D
		if tex:
			var img_size := Vector2(260, 175)
			draw_texture_rect(tex, Rect2(pos - img_size * 0.5, img_size), false, Color(1, 1, 1, alpha))
			# Subtle border
			draw_rect(Rect2(pos - img_size * 0.5, img_size), Color(0.6, 0.6, 0.65, alpha * 0.3), false, 2.0)
		else:
			# Fallback colored rectangle
			var col: Color = Color(0.4, 0.4, 0.45, alpha * 0.5)
			draw_rect(Rect2(pos - Vector2(100, 65), Vector2(200, 130)), col)

		# Label
		var font := ThemeDB.fallback_font
		var label: String = fragment_labels_map.get(fid, "")
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		draw_string(font, pos + Vector2(-text_size.x * 0.5, 100), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.7, 0.75, alpha * 0.8))

	# Center pulse when all revealed
	if fragment_reveal_index >= 4 and phase < 2:
		var center := Vector2(640, 360)
		var pulse_alpha := sin(pulse_time * 2.0) * 0.1 + 0.15
		draw_circle(center, 30, Color(0.6, 0.55, 0.6, pulse_alpha))

	# GUILT emergence from the corrupted black background
	if phase >= 3 and guilt_alpha > 0:
		var center := Vector2(640, 360)
		# Massive dark body — emerges from the blackness
		var body_size: float = 90.0 * guilt_alpha
		draw_circle(center, body_size, Color(0.06, 0.04, 0.08, guilt_alpha * 0.9))
		draw_circle(center, body_size * 0.65, Color(0.1, 0.06, 0.12, guilt_alpha * 0.6))
		# Tendrils reaching outward (curved, organic)
		for i in range(8):
			var base_angle := (float(i) / 8.0) * TAU + pulse_time * 0.2
			var length: float = (150.0 + sin(pulse_time * 1.2 + float(i)) * 40.0) * guilt_alpha
			var prev_pt := center
			for seg: int in range(1, 7):
				var t: float = float(seg) / 6.0
				var wave: float = sin(pulse_time * 1.5 + float(i) * 2.0 + t * 5.0) * 20.0 * t
				var seg_pos := center + Vector2(cos(base_angle), sin(base_angle)) * length * t
				seg_pos += Vector2(-sin(base_angle), cos(base_angle)) * wave
				var seg_thick: float = (5.0 - t * 3.5) * guilt_alpha
				draw_line(prev_pt, seg_pos, Color(0.14, 0.07, 0.18, guilt_alpha * (0.5 - t * 0.2)), maxf(seg_thick, 1.0))
				prev_pt = seg_pos
			draw_circle(prev_pt, 5.0 * guilt_alpha, Color(0.18, 0.1, 0.22, guilt_alpha * 0.35))
		# Eyes — glowing red
		var eye_glow: float = sin(pulse_time * 2.5) * 0.15 + 0.7
		draw_circle(center + Vector2(-25, -15), 12 * guilt_alpha, Color(0.5, 0.1, 0.12, guilt_alpha * eye_glow))
		draw_circle(center + Vector2(25, -15), 12 * guilt_alpha, Color(0.5, 0.1, 0.12, guilt_alpha * eye_glow))
		draw_circle(center + Vector2(-25, -15), 5 * guilt_alpha, Color(0.9, 0.2, 0.2, guilt_alpha))
		draw_circle(center + Vector2(25, -15), 5 * guilt_alpha, Color(0.9, 0.2, 0.2, guilt_alpha))


func _start_dialogue() -> void:
	var lines: Array[Dictionary] = [
		{"speaker": "Blame", "text": "She gave her life for us.", "color": GameManager.get_blame_color_light()},
		{"speaker": "Denial", "text": "She gave her life for us.", "color": GameManager.get_denial_color_light()},
		{"speaker": "", "text": "...", "color": Color(0.4, 0.4, 0.45)},
		{"speaker": "Denial", "text": "And I remembered her wrong.", "color": GameManager.get_denial_color_light()},
		{"speaker": "Blame", "text": "Me too. I thought remembering meant punishing us.", "color": GameManager.get_blame_color_light()},
		{"speaker": "Denial", "text": "She wouldn't want that.", "color": GameManager.get_denial_color_light()},
		{"speaker": "Blame", "text": "No. She wouldn't.", "color": GameManager.get_blame_color_light()},
		{"speaker": "Blame", "text": "So why are we still doing this to ourselves?", "color": GameManager.get_blame_color_light()},
		{"speaker": "", "text": "Something stirs in the darkness...", "color": Color(0.4, 0.3, 0.35)},
	]
	dialogue.play_dialogue(lines)


func _on_dialogue_done() -> void:
	if phase == 1:
		phase = 2
		time_elapsed = 0.0
		GameManager.trigger_collapse()  # GUILT corrupts all shards to black
