extends Control

## Reflection Screen — Final quote. The core message.

var time_elapsed := 0.0
var quote_alpha := 0.0
var subtitle_alpha := 0.0
var particles: Array[Dictionary] = []
var return_hint_alpha := 0.0


func _ready() -> void:
	# Gentle floating particles
	for i in range(40):
		var col := Color(
			randf_range(0.4, 0.8),
			randf_range(0.35, 0.7),
			randf_range(0.3, 0.8),
			randf_range(0.05, 0.15)
		)
		particles.append({
			"pos": Vector2(randf_range(0, 1280), randf_range(0, 720)),
			"vel": Vector2(randf_range(-8, 8), randf_range(-12, -3)),
			"size": randf_range(1.5, 4),
			"color": col
		})


func _process(delta: float) -> void:
	time_elapsed += delta

	# Fade in quote
	if time_elapsed > 1.5:
		quote_alpha = min(1.0, (time_elapsed - 1.5) * 0.3)
	if time_elapsed > 5.0:
		subtitle_alpha = min(1.0, (time_elapsed - 5.0) * 0.3)
	if time_elapsed > 8.0:
		return_hint_alpha = min(0.5, (time_elapsed - 8.0) * 0.15)

	# Particles
	for p: Dictionary in particles:
		p.pos += p.vel * delta
		if p.pos.y < -10:
			p.pos.y = 730
			p.pos.x = randf_range(0, 1280)

	# Return to menu
	if time_elapsed > 6.0:
		if Input.is_action_just_pressed("p1_attack") or Input.is_action_just_pressed("p2_attack") or Input.is_action_just_pressed("ui_accept"):
			GameManager.advance_phase()

	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.04, 0.04, 0.06))
	# Particles
	for p: Dictionary in particles:
		draw_circle(p.pos, p.size, p.color)

	# Main quote
	var font := ThemeDB.fallback_font
	var quote := "She didn't save you so you could spend your life drowning."
	var quote2 := "Live. Remember and honour her by living."
	var q_size := font.get_string_size(quote, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
	var q2_size := font.get_string_size(quote2, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)

	var quote_color := Color(0.8, 0.78, 0.75, quote_alpha)
	draw_string(font, Vector2(640 - q_size.x * 0.5, 320), quote,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, quote_color)
	draw_string(font, Vector2(640 - q2_size.x * 0.5, 365), quote2,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, quote_color)

	# Subtitle
	var sub := "For everyone who carries someone they've lost."
	var sub_size := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	draw_string(font, Vector2(640 - sub_size.x * 0.5, 430), sub,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.55, 0.55, 0.6, subtitle_alpha * 0.7))

	# Two small shapes — now at peace
	if subtitle_alpha > 0.3:
		var sa := subtitle_alpha * 0.5
		# Blame shape (small)
		draw_rect(Rect2(Vector2(580, 470), Vector2(16, 16)), Color(GameManager.get_blame_color(), sa))
		# Denial shape (small)
		draw_circle(Vector2(700, 478), 9, Color(GameManager.get_denial_color(), sa))
		# Connecting line
		draw_line(Vector2(596, 478), Vector2(691, 478), Color(0.5, 0.5, 0.55, sa * 0.4), 1.0)

	# Return hint
	if return_hint_alpha > 0:
		var hint := "[ Press any key to return ]"
		var hint_size := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		draw_string(font, Vector2(640 - hint_size.x * 0.5, 660), hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.4, 0.4, 0.45, return_hint_alpha))
