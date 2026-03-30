extends Control

@onready var title_label: Label = $VBox/TitleLabel
@onready var subtitle_label: Label = $VBox/SubtitleLabel
@onready var play_button: Button = $VBox/PlayButton
@onready var bg: ColorRect = $BG

var time_elapsed: float = 0.0

# Floating shapes — circles, rectangles, triangles drifting across the screen
var shapes: Array[Dictionary] = []
const NUM_SHAPES := 35


func _ready() -> void:
	bg.color = Color(0.06, 0.06, 0.1)
	title_label.text = "FRACTURED MEMORIES"
	subtitle_label.text = "A game about two halves of one mind"

	play_button.text = "PLAY"
	play_button.pressed.connect(_on_play)

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.15, 0.15, 0.25)
	btn_style.border_color = Color(0.4, 0.4, 0.55)
	btn_style.set_border_width_all(2)
	btn_style.set_corner_radius_all(6)
	btn_style.set_content_margin_all(16)
	play_button.add_theme_stylebox_override("normal", btn_style)

	var btn_hover: StyleBoxFlat = btn_style.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.2, 0.2, 0.35)
	play_button.add_theme_stylebox_override("hover", btn_hover)

	GameManager.reset_game()

	# Generate floating shapes
	for i in range(NUM_SHAPES):
		_spawn_shape(true)


func _spawn_shape(randomize_x: bool) -> void:
	var warm: bool = randf() > 0.5
	var base_col: Color
	if warm:
		base_col = Color(
			randf_range(0.7, 0.95),
			randf_range(0.35, 0.55),
			randf_range(0.2, 0.4),
			randf_range(0.06, 0.2)
		)
	else:
		base_col = Color(
			randf_range(0.15, 0.35),
			randf_range(0.2, 0.4),
			randf_range(0.45, 0.75),
			randf_range(0.06, 0.2)
		)

	shapes.append({
		"pos": Vector2(
			randf_range(-100, 1380) if randomize_x else randf_range(-100, -20),
			randf_range(-50, 770)
		),
		"vel": Vector2(randf_range(8, 35), randf_range(-12, 12)),
		"size": randf_range(6, 30),
		"color": base_col,
		"type": randi() % 3,  # 0=circle, 1=rect, 2=triangle
		"rot": randf_range(0, TAU),
		"rot_speed": randf_range(-0.5, 0.5),
		"phase": randf_range(0, TAU),  # for floating bob
		"bob_amp": randf_range(5, 20),
		"bob_speed": randf_range(0.3, 1.2),
	})


func _process(delta: float) -> void:
	time_elapsed += delta

	# Update shapes
	for i in range(shapes.size() - 1, -1, -1):
		var s: Dictionary = shapes[i]
		s.pos = (s.pos as Vector2) + (s.vel as Vector2) * delta
		s.rot = (s.rot as float) + (s.rot_speed as float) * delta

		# Off screen right? Respawn from left
		if (s.pos as Vector2).x > 1400:
			shapes.remove_at(i)
			_spawn_shape(false)

	queue_redraw()


func _draw() -> void:
	# Draw all floating shapes
	for s: Dictionary in shapes:
		var pos: Vector2 = s.pos
		# Add vertical bob
		pos.y += sin(time_elapsed * (s.bob_speed as float) + (s.phase as float)) * (s.bob_amp as float)
		var sz: float = s.size
		var col: Color = s.color
		# Gentle pulse on alpha
		col.a *= 0.7 + sin(time_elapsed * 0.8 + (s.phase as float)) * 0.3

		match (s.type as int):
			0: # Circle
				draw_circle(pos, sz, col)
			1: # Rectangle (rotated)
				var half := Vector2(sz, sz * 0.7)
				var rot: float = s.rot
				var corners := PackedVector2Array([
					pos + Vector2(-half.x, -half.y).rotated(rot),
					pos + Vector2(half.x, -half.y).rotated(rot),
					pos + Vector2(half.x, half.y).rotated(rot),
					pos + Vector2(-half.x, half.y).rotated(rot),
				])
				draw_colored_polygon(corners, col)
			2: # Triangle (rotated)
				var rot: float = s.rot
				var tri := PackedVector2Array([
					pos + Vector2(0, -sz).rotated(rot),
					pos + Vector2(sz * 0.87, sz * 0.5).rotated(rot),
					pos + Vector2(-sz * 0.87, sz * 0.5).rotated(rot),
				])
				draw_colored_polygon(tri, col)

	# Center crack line (subtle)
	var crack_alpha: float = 0.1 + sin(time_elapsed * 0.5) * 0.05
	draw_line(Vector2(640, 200), Vector2(640, 520), Color(0.5, 0.5, 0.55, crack_alpha), 1.5)
	# Branch cracks
	draw_line(Vector2(640, 320), Vector2(620, 280), Color(0.5, 0.5, 0.55, crack_alpha * 0.6), 1.0)
	draw_line(Vector2(640, 380), Vector2(660, 420), Color(0.5, 0.5, 0.55, crack_alpha * 0.6), 1.0)


func _on_play() -> void:
	GameManager.advance_phase()
