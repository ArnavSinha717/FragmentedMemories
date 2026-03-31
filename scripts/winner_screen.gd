extends Control

## Shows which emotion won the competitive minigame before revealing the memory fragment.

var blame_won: bool = false
var timer: float = 0.0
const DISPLAY_TIME := 3.5
const FADE_IN := 0.6
const HOLD := 2.0
const FADE_OUT := 0.9

var pulse_time: float = 0.0


func _ready() -> void:
	blame_won = GameManager.get_last_winner_is_blame()


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("debug_skip"):
		GameManager.advance_phase()
		return

	timer += delta
	pulse_time += delta

	if timer >= DISPLAY_TIME:
		GameManager.advance_phase()
		return

	queue_redraw()


func _draw() -> void:
	var vp := get_viewport_rect().size
	var cx: float = vp.x * 0.5
	var cy: float = vp.y * 0.5

	# Background
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.02, 0.04))

	# Fade envelope
	var alpha: float = 1.0
	if timer < FADE_IN:
		alpha = timer / FADE_IN
	elif timer > DISPLAY_TIME - FADE_OUT:
		alpha = (DISPLAY_TIME - timer) / FADE_OUT
	alpha = clampf(alpha, 0.0, 1.0)

	# Winner color
	var col: Color
	var glow_col: Color
	var label_text: String
	if blame_won:
		col = GameManager.get_blame_color()
		glow_col = GameManager.get_blame_color_light()
		label_text = "BLAME WINS"
	else:
		col = GameManager.get_denial_color()
		glow_col = GameManager.get_denial_color_light()
		label_text = "DENIAL WINS"

	# Pulsing glow behind text
	var glow_r: float = 120.0 + sin(pulse_time * 3.0) * 20.0
	draw_circle(Vector2(cx, cy), glow_r, Color(glow_col.r, glow_col.g, glow_col.b, 0.08 * alpha))
	draw_circle(Vector2(cx, cy), glow_r * 0.6, Color(glow_col.r, glow_col.g, glow_col.b, 0.12 * alpha))

	# Radiating lines
	for i in range(12):
		var angle: float = float(i) / 12.0 * TAU + pulse_time * 0.5
		var inner: float = 60.0
		var outer: float = 160.0 + sin(pulse_time * 2.0 + float(i)) * 30.0
		var line_a: float = 0.15 * alpha
		var from_pt := Vector2(cx + cos(angle) * inner, cy + sin(angle) * inner)
		var to_pt := Vector2(cx + cos(angle) * outer, cy + sin(angle) * outer)
		draw_line(from_pt, to_pt, Color(col.r, col.g, col.b, line_a), 2.0)

	# Main text
	var font := ThemeDB.fallback_font
	var font_size: int = 48
	var text_size := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := Vector2(cx - text_size.x * 0.5, cy + text_size.y * 0.3)

	# Text shadow
	draw_string(font, text_pos + Vector2(2, 2), label_text, HORIZONTAL_ALIGNMENT_CENTER,
		-1, font_size, Color(0, 0, 0, 0.5 * alpha))
	# Text
	draw_string(font, text_pos, label_text, HORIZONTAL_ALIGNMENT_CENTER,
		-1, font_size, Color(col.r, col.g, col.b, alpha))

	# Subtitle
	var sub_text := "Their memory surfaces..." if blame_won else "Their memory surfaces..."
	var sub_size: int = 20
	var sub_w := font.get_string_size(sub_text, HORIZONTAL_ALIGNMENT_CENTER, -1, sub_size)
	var sub_alpha: float = clampf((timer - 1.0) / 0.5, 0.0, 1.0) * alpha
	draw_string(font, Vector2(cx - sub_w.x * 0.5, cy + 50), sub_text, HORIZONTAL_ALIGNMENT_CENTER,
		-1, sub_size, Color(0.7, 0.7, 0.8, sub_alpha * 0.7))

