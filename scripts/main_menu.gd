extends Control

@onready var title_label: Label = $VBox/TitleLabel
@onready var subtitle_label: Label = $VBox/SubtitleLabel
@onready var play_button: Button = $VBox/PlayButton

var time_elapsed: float = 0.0
var shapes: Array[Dictionary] = []
const NUM_SHAPES := 40
var title_crack_progress := 0.0
var selected := false


func _ready() -> void:
	title_label.visible = false
	subtitle_label.visible = false

	play_button.text = "PLAY"
	play_button.pressed.connect(_on_play)

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.12, 0.12, 0.2, 0.8)
	btn_style.border_color = Color(0.4, 0.4, 0.55, 0.6)
	btn_style.set_border_width_all(1)
	btn_style.set_corner_radius_all(4)
	btn_style.set_content_margin_all(16)
	play_button.add_theme_stylebox_override("normal", btn_style)

	var btn_hover: StyleBoxFlat = btn_style.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.18, 0.18, 0.3, 0.9)
	btn_hover.border_color = Color(0.6, 0.55, 0.7, 0.8)
	play_button.add_theme_stylebox_override("hover", btn_hover)

	var btn_focus: StyleBoxFlat = btn_hover.duplicate() as StyleBoxFlat
	btn_focus.border_color = Color(0.7, 0.65, 0.8, 0.9)
	btn_focus.set_border_width_all(2)
	play_button.add_theme_stylebox_override("focus", btn_focus)

	var btn_pressed: StyleBoxFlat = btn_hover.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = Color(0.25, 0.22, 0.4, 0.95)
	play_button.add_theme_stylebox_override("pressed", btn_pressed)

	GameManager.reset_game()

	# Grab focus so controller can select the button
	play_button.grab_focus()

	for i in range(NUM_SHAPES):
		_spawn_shape(true)


func _spawn_shape(randomize_x: bool) -> void:
	var warm: bool = randf() > 0.5
	var base_col: Color
	if warm:
		base_col = Color(
			randf_range(0.7, 0.95), randf_range(0.35, 0.55),
			randf_range(0.2, 0.4), randf_range(0.04, 0.15))
	else:
		base_col = Color(
			randf_range(0.15, 0.35), randf_range(0.2, 0.4),
			randf_range(0.45, 0.75), randf_range(0.04, 0.15))

	shapes.append({
		"pos": Vector2(
			randf_range(-100, 1380) if randomize_x else randf_range(-100, -20),
			randf_range(-50, 770)),
		"vel": Vector2(randf_range(8, 35), randf_range(-12, 12)),
		"size": randf_range(4, 25),
		"color": base_col,
		"type": randi() % 3,
		"rot": randf_range(0, TAU),
		"rot_speed": randf_range(-0.5, 0.5),
		"phase": randf_range(0, TAU),
		"bob_amp": randf_range(5, 20),
		"bob_speed": randf_range(0.3, 1.2),
	})


func _process(delta: float) -> void:
	time_elapsed += delta
	title_crack_progress = minf(1.0, time_elapsed * 0.15)

	for i in range(shapes.size() - 1, -1, -1):
		var s: Dictionary = shapes[i]
		s.pos = (s.pos as Vector2) + (s.vel as Vector2) * delta
		s.rot = (s.rot as float) + (s.rot_speed as float) * delta
		if (s.pos as Vector2).x > 1400:
			shapes.remove_at(i)
			_spawn_shape(false)

	queue_redraw()


func _draw() -> void:
	# Background gradient
	for row: int in range(36):
		var t: float = float(row) / 36.0
		var col := Color(0.04, 0.04, 0.08).lerp(Color(0.08, 0.06, 0.12), t)
		draw_rect(Rect2(0, row * 20, 1280, 20), col)

	# Floating shapes
	for s: Dictionary in shapes:
		var pos: Vector2 = s.pos
		pos.y += sin(time_elapsed * (s.bob_speed as float) + (s.phase as float)) * (s.bob_amp as float)
		var sz: float = s.size
		var col: Color = s.color
		col.a *= 0.6 + sin(time_elapsed * 0.8 + (s.phase as float)) * 0.3

		match (s.type as int):
			0: draw_circle(pos, sz, col)
			1:
				var half := Vector2(sz, sz * 0.7)
				var rot: float = s.rot
				draw_colored_polygon(PackedVector2Array([
					pos + Vector2(-half.x, -half.y).rotated(rot),
					pos + Vector2(half.x, -half.y).rotated(rot),
					pos + Vector2(half.x, half.y).rotated(rot),
					pos + Vector2(-half.x, half.y).rotated(rot)]), col)
			2:
				var rot: float = s.rot
				draw_colored_polygon(PackedVector2Array([
					pos + Vector2(0, -sz).rotated(rot),
					pos + Vector2(sz * 0.87, sz * 0.5).rotated(rot),
					pos + Vector2(-sz * 0.87, sz * 0.5).rotated(rot)]), col)

	var font := ThemeDB.fallback_font
	var cx: float = 640.0

	# Title glow
	var glow_a: float = 0.06 + sin(time_elapsed * 1.5) * 0.03
	draw_circle(Vector2(cx, 260), 180, Color(0.4, 0.35, 0.55, glow_a))
	draw_circle(Vector2(cx, 260), 100, Color(0.5, 0.4, 0.6, glow_a * 1.5))

	# Title text — "FRACTURED" and "MEMORIES" drawn separately with crack between
	var title_a: float = minf(1.0, time_elapsed * 0.5)
	var word1 := "FRACTURED"
	var word2 := "MEMORIES"
	var w1_size := font.get_string_size(word1, HORIZONTAL_ALIGNMENT_CENTER, -1, 52)
	var w2_size := font.get_string_size(word2, HORIZONTAL_ALIGNMENT_CENTER, -1, 52)

	# Fractured slides slightly left, Memories slightly right (the fracture)
	var split: float = title_crack_progress * 6.0
	var col_cold := Color(0.55, 0.6, 0.85, title_a)
	var col_warm := Color(0.9, 0.6, 0.45, title_a)

	# Shadow
	draw_string(font, Vector2(cx - w1_size.x * 0.5 - split + 2, 242), word1, HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color(0, 0, 0, title_a * 0.4))
	draw_string(font, Vector2(cx - w2_size.x * 0.5 + split + 2, 302), word2, HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color(0, 0, 0, title_a * 0.4))
	# Main text
	draw_string(font, Vector2(cx - w1_size.x * 0.5 - split, 240), word1, HORIZONTAL_ALIGNMENT_LEFT, -1, 52, col_cold)
	draw_string(font, Vector2(cx - w2_size.x * 0.5 + split, 300), word2, HORIZONTAL_ALIGNMENT_LEFT, -1, 52, col_warm)

	# Crack line between the words
	var crack_a: float = title_crack_progress * 0.6
	var crack_y := 262.0
	# Main vertical crack
	draw_line(Vector2(cx, crack_y - 30 * title_crack_progress), Vector2(cx, crack_y + 30 * title_crack_progress), Color(0.6, 0.6, 0.65, crack_a), 2.0)
	# Branch cracks
	if title_crack_progress > 0.3:
		var bp: float = (title_crack_progress - 0.3) / 0.7
		draw_line(Vector2(cx, crack_y), Vector2(cx - 25 * bp, crack_y - 20 * bp), Color(0.5, 0.5, 0.55, crack_a * 0.6), 1.5)
		draw_line(Vector2(cx, crack_y), Vector2(cx + 20 * bp, crack_y + 15 * bp), Color(0.5, 0.5, 0.55, crack_a * 0.6), 1.5)
		draw_line(Vector2(cx, crack_y - 10), Vector2(cx + 15 * bp, crack_y - 25 * bp), Color(0.5, 0.5, 0.55, crack_a * 0.4), 1.0)

	# Subtitle
	var sub_a: float = clampf((time_elapsed - 1.5) * 0.4, 0.0, 0.7)
	var sub_text := "Two halves. One fractured mind."
	var sub_w := font.get_string_size(sub_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
	draw_string(font, Vector2(cx - sub_w.x * 0.5, 345), sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.5, 0.5, 0.55, sub_a))

	# Character sprites flanking the title
	var char_a: float = clampf((time_elapsed - 0.8) * 0.3, 0.0, 0.6)
	# Blame (left)
	var b_frame: int = GameManager.anim_frame(time_elapsed, 4, 4.0)
	GameManager.draw_blame_sprite(self, Vector2(200, 400), b_frame, 5, 1.2, false, Color(1, 1, 1, char_a))
	# Denial (right)
	var d_frame: int = GameManager.anim_frame(time_elapsed, 2, 3.0)
	GameManager.draw_denial_sprite(self, Vector2(1080, 400), d_frame, 0, 1.8, true, Color(1, 1, 1, char_a))

	# Connecting thread between them (faint)
	if char_a > 0.1:
		var thread_a: float = char_a * 0.15
		for seg: int in range(20):
			var t: float = float(seg) / 20.0
			var x: float = lerpf(220.0, 1060.0, t)
			var wave: float = sin(time_elapsed * 1.2 + t * 8.0) * 8.0
			var x2: float = lerpf(220.0, 1060.0, (float(seg) + 1.0) / 20.0)
			var wave2: float = sin(time_elapsed * 1.2 + ((t + 0.05) * 8.0)) * 8.0
			var seg_col := col_cold.lerp(col_warm, t)
			seg_col.a = thread_a
			draw_line(Vector2(x, 360 + wave), Vector2(x2, 360 + wave2), seg_col, 1.0)

	# Controls hint at bottom
	var hint_a: float = clampf((time_elapsed - 3.0) * 0.2, 0.0, 0.5)
	var hint := "P1: WASD + F/G/R  |  P2: Arrows + Enter/Shift//  |  Controllers supported"
	var hint_w := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
	draw_string(font, Vector2(cx - hint_w.x * 0.5, 680), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 0.4, 0.45, hint_a))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		if (event as InputEventJoypadButton).button_index == 0 or (event as InputEventJoypadButton).button_index == 2:
			_on_play()


func _on_play() -> void:
	if not selected:
		selected = true
		GameManager.advance_phase()
