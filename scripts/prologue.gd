extends Control

## Prologue — Sets the scene after pressing Play.
## Sequential text screens with gentle fades. No spoilers.

var time_elapsed := 0.0
var line_index := 0
var line_timer := 0.0
var fade_alpha := 1.0  # starts black
var particles: Array[Dictionary] = []

const FADE_IN := 1.2
const HOLD := 3.5
const FADE_OUT := 1.0
const LINE_DURATION := FADE_IN + HOLD + FADE_OUT  # per line

var lines: Array[Dictionary] = [
	{"text": "Two best friends. One story.", "color": Color(0.7, 0.7, 0.75), "size": 28},
	{"text": "One night changed everything.", "color": Color(0.6, 0.55, 0.6), "size": 26},
	{"text": "From the grief, two emotions emerged —\neach carrying a fragment of what happened.", "color": Color(0.65, 0.6, 0.65), "size": 22},
	{"text": "BLAME\nThe weight of what went wrong.", "color": Color(0.45, 0.5, 0.75), "size": 24},
	{"text": "DENIAL\nThe refusal to remember.", "color": Color(0.9, 0.6, 0.45), "size": 24},
	{"text": "They think they're enemies.\nThey don't yet know they need each other.", "color": Color(0.6, 0.6, 0.65), "size": 22},
	{"text": "The truth can only surface when both sides are heard.", "color": Color(0.75, 0.72, 0.7), "size": 24},
]


func _ready() -> void:
	for i in range(25):
		particles.append({
			"pos": Vector2(randf_range(0, 1280), randf_range(0, 720)),
			"vel": Vector2(randf_range(-6, 6), randf_range(-10, -3)),
			"size": randf_range(1, 3),
			"alpha": randf_range(0.03, 0.12),
		})


func _process(delta: float) -> void:
	time_elapsed += delta
	line_timer += delta

	# Skip on any press
	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("p1_attack") or Input.is_action_just_pressed("p2_attack"):
		line_index += 1
		line_timer = 0.0
		if line_index >= lines.size():
			GameManager.advance_phase()
			return

	if line_timer >= LINE_DURATION:
		line_timer = 0.0
		line_index += 1
		if line_index >= lines.size():
			# Final fade out then advance
			fade_alpha = minf(1.0, fade_alpha + delta * 2.0)
			if fade_alpha >= 1.0:
				GameManager.advance_phase()
			queue_redraw()
			return

	# Particles
	for p: Dictionary in particles:
		p.pos = (p.pos as Vector2) + (p.vel as Vector2) * delta
		if (p.pos as Vector2).y < -10:
			p.pos = Vector2(randf_range(0, 1280), 730)

	queue_redraw()


func _draw() -> void:
	# Background
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.04, 0.04, 0.06))

	# Particles
	for p: Dictionary in particles:
		draw_circle(p.pos as Vector2, p.size as float, Color(0.5, 0.5, 0.55, p.alpha as float))

	if line_index >= lines.size():
		draw_rect(Rect2(0, 0, 1280, 720), Color(0, 0, 0, fade_alpha))
		return

	# Current line fade envelope
	var alpha: float = 1.0
	if line_timer < FADE_IN:
		alpha = line_timer / FADE_IN
	elif line_timer > FADE_IN + HOLD:
		alpha = 1.0 - (line_timer - FADE_IN - HOLD) / FADE_OUT
	alpha = clampf(alpha, 0.0, 1.0)

	var font := ThemeDB.fallback_font
	var line: Dictionary = lines[line_index]
	var text: String = line.text as String
	var col: Color = line.color as Color
	col.a = alpha
	var sz: int = line.size as int

	# Split by newline for multi-line support
	var parts: PackedStringArray = text.split("\n")
	var total_h: float = float(parts.size()) * float(sz + 12)
	var start_y: float = 360.0 - total_h * 0.5 + float(sz) * 0.5

	for i: int in parts.size():
		var part: String = parts[i]
		var tw: float = font.get_string_size(part, HORIZONTAL_ALIGNMENT_CENTER, -1, sz).x
		var y: float = start_y + float(i) * float(sz + 12)
		# Shadow
		draw_string(font, Vector2(640 - tw * 0.5 + 1, y + 1), part, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, alpha * 0.4))
		# Text
		draw_string(font, Vector2(640 - tw * 0.5, y), part, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

	# Skip hint at bottom
	var hint_a: float = 0.3 + sin(time_elapsed * 2.0) * 0.1
	draw_string(font, Vector2(530, 660), "Press SPACE / X to continue", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.4, 0.4, 0.5, hint_a))
