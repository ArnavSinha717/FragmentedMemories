extends Control

## Competitive Minigame 2 — Catch the Falling Memories.
## Memory fragments rain from the sky. Players jump between platforms to catch them.
## Blame (P1) catches DARK/COLD fragments, Denial (P2) catches WARM/BRIGHT fragments.
## Catching your own color = +1, wrong color = -1 and fragment shatters.

@onready var dialogue: Node = $DialogueSystem
@onready var timer_label: Label = $HUD/TimerLabel
@onready var p1_score_label: Label = $HUD/P1Score
@onready var p2_score_label: Label = $HUD/P2Score

# --- Physics ---
const GRAVITY := 900.0
const JUMP_FORCE := -460.0
const PLAYER_SPEED := 280.0
const MATCH_TIME := 35.0
const GROUND_Y := 640.0
const LEFT_WALL := 40.0
const RIGHT_WALL := 1240.0
const CEILING := 40.0

# --- Platforms (x, y, width) ---
var platforms: Array[Dictionary] = [
	{"x": 160.0, "y": 460.0, "w": 220.0},   # Left high
	{"x": 530.0, "y": 380.0, "w": 220.0},   # Center highest
	{"x": 900.0, "y": 460.0, "w": 220.0},   # Right high
]

# --- Fragment spawning ---
const SPAWN_MIN_INTERVAL := 0.5
const SPAWN_MAX_INTERVAL := 0.8
const FRAGMENT_FALL_MIN := 120.0
const FRAGMENT_FALL_MAX := 220.0
const FRAGMENT_DRIFT_MAX := 30.0
const FRAGMENT_SIZE := 18.0
const CATCH_RADIUS := 42.0

# Fragment types: 0 = cold (blame), 1 = warm (denial)
# Shapes: 0 = circle, 1 = triangle, 2 = rectangle
var fragments: Array[Dictionary] = []
var shatter_particles: Array[Dictionary] = []
var catch_flashes: Array[Dictionary] = []
var spawn_timer := 0.0

# --- Players ---
var p1_pos := Vector2(300, GROUND_Y)
var p1_vel := Vector2.ZERO
var p1_on_ground := true
var p1_facing := 1.0
var p1_score := 0

var p2_pos := Vector2(980, GROUND_Y)
var p2_vel := Vector2.ZERO
var p2_on_ground := true
var p2_facing := -1.0
var p2_score := 0

# --- State ---
var match_timer := MATCH_TIME
var match_over := false
var blame_won := false
var phase: int = 0 # 0=playing, 1=result_dialogue, 2=done


func _ready() -> void:
	p1_score_label.add_theme_color_override("font_color", GameManager.get_blame_color_light())
	p2_score_label.add_theme_color_override("font_color", GameManager.get_denial_color_light())
	p1_score_label.text = "BLAME: 0"
	p2_score_label.text = "DENIAL: 0"

	dialogue.dialogue_finished.connect(_on_dialogue_done)
	spawn_timer = 0.3


func _process(delta: float) -> void:
	if phase == 2:
		GameManager.advance_phase()
		return
	if phase == 1:
		# Still update shatter particles during dialogue
		_update_shatter_particles(delta)
		_update_catch_flashes(delta)
		queue_redraw()
		return

	if match_over:
		return

	# Timer
	match_timer -= delta
	timer_label.text = str(ceili(match_timer))
	if match_timer <= 0:
		match_timer = 0
		_end_match()
		return

	# --- Spawn fragments ---
	spawn_timer -= delta
	if spawn_timer <= 0:
		spawn_timer = randf_range(SPAWN_MIN_INTERVAL, SPAWN_MAX_INTERVAL)
		_spawn_fragment()

	# --- P1 (Blame) movement ---
	var p1_dir: float = 0.0
	if Input.is_action_pressed("p1_left"): p1_dir -= 1.0
	if Input.is_action_pressed("p1_right"): p1_dir += 1.0
	if p1_dir != 0.0: p1_facing = p1_dir
	p1_vel.x = lerpf(p1_vel.x, p1_dir * PLAYER_SPEED, 12.0 * delta)

	if p1_on_ground and Input.is_action_just_pressed("p1_up"):
		p1_vel.y = JUMP_FORCE
		p1_on_ground = false

	p1_vel.y += GRAVITY * delta
	p1_pos += p1_vel * delta
	_resolve_player_collision_p1()

	# --- P2 (Denial) movement ---
	var p2_dir: float = 0.0
	if Input.is_action_pressed("p2_left"): p2_dir -= 1.0
	if Input.is_action_pressed("p2_right"): p2_dir += 1.0
	if p2_dir != 0.0: p2_facing = p2_dir
	p2_vel.x = lerpf(p2_vel.x, p2_dir * PLAYER_SPEED, 12.0 * delta)

	if p2_on_ground and Input.is_action_just_pressed("p2_up"):
		p2_vel.y = JUMP_FORCE
		p2_on_ground = false

	p2_vel.y += GRAVITY * delta
	p2_pos += p2_vel * delta
	_resolve_player_collision_p2()

	# --- Update fragments ---
	_update_fragments(delta)

	# --- Check catches ---
	if Input.is_action_just_pressed("p1_attack"):
		_try_catch(1)
	if Input.is_action_just_pressed("p2_attack"):
		_try_catch(2)

	# --- Update particles ---
	_update_shatter_particles(delta)
	_update_catch_flashes(delta)

	# --- Update scores display ---
	p1_score_label.text = "BLAME: " + str(p1_score)
	p2_score_label.text = "DENIAL: " + str(p2_score)

	# --- Update hue ---
	var total: float = float(absf(float(p1_score)) + absf(float(p2_score)) + 1.0)
	var target_hue: float = 0.5 + float(p2_score - p1_score) / (total * 2.0)
	target_hue = clampf(target_hue, 0.0, 1.0)
	GameManager.set_hue(lerpf(GameManager.hue_value, target_hue, 2.0 * delta))

	queue_redraw()


# --- Platform collision for P1 ---
func _resolve_player_collision_p1() -> void:
	p1_on_ground = false
	# Ground
	if p1_pos.y >= GROUND_Y:
		p1_pos.y = GROUND_Y
		p1_vel.y = 0.0
		p1_on_ground = true
	# Platforms (only when falling)
	if p1_vel.y >= 0:
		for plat: Dictionary in platforms:
			var px: float = plat.x
			var py: float = plat.y
			var pw: float = plat.w
			if p1_pos.x >= px and p1_pos.x <= px + pw:
				if p1_pos.y >= py and p1_pos.y <= py + 20:
					p1_pos.y = py
					p1_vel.y = 0.0
					p1_on_ground = true
	p1_pos.y = maxf(p1_pos.y, CEILING)
	p1_pos.x = clampf(p1_pos.x, LEFT_WALL, RIGHT_WALL)


# --- Platform collision for P2 ---
func _resolve_player_collision_p2() -> void:
	p2_on_ground = false
	# Ground
	if p2_pos.y >= GROUND_Y:
		p2_pos.y = GROUND_Y
		p2_vel.y = 0.0
		p2_on_ground = true
	# Platforms (only when falling)
	if p2_vel.y >= 0:
		for plat: Dictionary in platforms:
			var px: float = plat.x
			var py: float = plat.y
			var pw: float = plat.w
			if p2_pos.x >= px and p2_pos.x <= px + pw:
				if p2_pos.y >= py and p2_pos.y <= py + 20:
					p2_pos.y = py
					p2_vel.y = 0.0
					p2_on_ground = true
	p2_pos.y = maxf(p2_pos.y, CEILING)
	p2_pos.x = clampf(p2_pos.x, LEFT_WALL, RIGHT_WALL)


# --- Fragment spawning ---
func _spawn_fragment() -> void:
	var frag_type: int = 0 if randf() < 0.5 else 1 # 0=cold/blame, 1=warm/denial
	var shape: int = randi() % 3 # 0=circle, 1=triangle, 2=rectangle
	var x_pos: float = randf_range(80.0, 1200.0)
	var fall_speed: float = randf_range(FRAGMENT_FALL_MIN, FRAGMENT_FALL_MAX)
	var drift: float = randf_range(-FRAGMENT_DRIFT_MAX, FRAGMENT_DRIFT_MAX)

	var col: Color
	if frag_type == 0:
		# Cold/dark: blue-purple tints
		col = Color(
			randf_range(0.15, 0.35),
			randf_range(0.18, 0.35),
			randf_range(0.5, 0.8),
			0.9
		)
	else:
		# Warm/bright: orange tints
		col = Color(
			randf_range(0.8, 0.98),
			randf_range(0.4, 0.65),
			randf_range(0.15, 0.35),
			0.9
		)

	var frag_size: float = randf_range(FRAGMENT_SIZE * 0.8, FRAGMENT_SIZE * 1.3)

	fragments.append({
		"pos": Vector2(x_pos, -30.0),
		"vel": Vector2(drift, fall_speed),
		"type": frag_type,
		"shape": shape,
		"color": col,
		"size": frag_size,
		"rotation": randf_range(0, TAU),
		"rot_speed": randf_range(-2.0, 2.0),
	})


# --- Fragment updating ---
func _update_fragments(delta: float) -> void:
	for i in range(fragments.size() - 1, -1, -1):
		var frag: Dictionary = fragments[i]
		frag.pos = (frag.pos as Vector2) + (frag.vel as Vector2) * delta
		frag.rotation = (frag.rotation as float) + (frag.rot_speed as float) * delta
		# Add slight horizontal wave
		frag.vel = Vector2((frag.vel as Vector2).x, (frag.vel as Vector2).y)

		var frag_pos: Vector2 = frag.pos
		# Hit ground — shatter and remove
		if frag_pos.y > GROUND_Y + 10:
			_spawn_shatter(frag_pos, frag.color as Color, false)
			fragments.remove_at(i)


# --- Catching ---
func _try_catch(player_id: int) -> void:
	var player_pos: Vector2 = p1_pos if player_id == 1 else p2_pos
	# Check body area (slightly above the pos since pos is at feet)
	var catch_center := Vector2(player_pos.x, player_pos.y - 35.0)

	var best_idx: int = -1
	var best_dist: float = CATCH_RADIUS + 1.0

	for i in range(fragments.size()):
		var frag: Dictionary = fragments[i]
		var frag_pos: Vector2 = frag.pos
		var dist: float = catch_center.distance_to(frag_pos)
		if dist < CATCH_RADIUS and dist < best_dist:
			best_dist = dist
			best_idx = i

	if best_idx < 0:
		return

	var caught_frag: Dictionary = fragments[best_idx]
	var frag_type: int = caught_frag.type
	var frag_pos: Vector2 = caught_frag.pos
	var frag_col: Color = caught_frag.color

	# Determine if correct match
	# Player 1 (Blame) should catch type 0 (cold)
	# Player 2 (Denial) should catch type 1 (warm)
	var correct: bool = (player_id == 1 and frag_type == 0) or (player_id == 2 and frag_type == 1)

	if correct:
		# +1 point, absorb flash
		if player_id == 1:
			p1_score += 1
		else:
			p2_score += 1
		_spawn_catch_flash(player_pos, frag_col, true)
	else:
		# -1 point, shatter effect
		if player_id == 1:
			p1_score -= 1
		else:
			p2_score -= 1
		_spawn_shatter(frag_pos, frag_col, true)
		_spawn_catch_flash(player_pos, Color(1.0, 0.2, 0.2, 0.8), false)

	fragments.remove_at(best_idx)


# --- Shatter particles ---
func _spawn_shatter(pos: Vector2, col: Color, is_wrong_catch: bool) -> void:
	var count: int = 8 if is_wrong_catch else 5
	for i in range(count):
		var angle: float = randf_range(0, TAU)
		var speed: float = randf_range(60.0, 180.0)
		var vel := Vector2(cos(angle) * speed, sin(angle) * speed - 50.0)
		shatter_particles.append({
			"pos": Vector2(pos.x, pos.y),
			"vel": vel,
			"alpha": 1.0,
			"color": col,
			"size": randf_range(2.0, 6.0),
			"shape": randi() % 3,
		})


func _spawn_catch_flash(pos: Vector2, col: Color, success: bool) -> void:
	catch_flashes.append({
		"pos": Vector2(pos.x, pos.y - 30.0),
		"alpha": 1.0,
		"color": col,
		"radius": 10.0 if success else 15.0,
		"success": success,
	})


func _update_shatter_particles(delta: float) -> void:
	for i in range(shatter_particles.size() - 1, -1, -1):
		var p: Dictionary = shatter_particles[i]
		p.vel = (p.vel as Vector2) + Vector2(0, 300.0) * delta
		p.pos = (p.pos as Vector2) + (p.vel as Vector2) * delta
		p.alpha = (p.alpha as float) - delta * 1.5
		if (p.alpha as float) <= 0:
			shatter_particles.remove_at(i)


func _update_catch_flashes(delta: float) -> void:
	for i in range(catch_flashes.size() - 1, -1, -1):
		var f: Dictionary = catch_flashes[i]
		f.alpha = (f.alpha as float) - delta * 3.0
		f.radius = (f.radius as float) + delta * 80.0
		if (f.alpha as float) <= 0:
			catch_flashes.remove_at(i)


# --- Drawing ---
func _draw() -> void:
	# --- Platforms ---
	for plat: Dictionary in platforms:
		var px: float = plat.x
		var py: float = plat.y
		var pw: float = plat.w
		# Platform body
		draw_rect(Rect2(px, py, pw, 14), Color(0.22, 0.22, 0.28, 0.85))
		# Top edge highlight
		draw_line(Vector2(px, py), Vector2(px + pw, py), Color(0.4, 0.4, 0.5, 0.6), 2.0)
		# Bottom shadow
		draw_rect(Rect2(px, py + 14, pw, 4), Color(0.12, 0.12, 0.16, 0.6))

	# --- Ground ---
	draw_rect(Rect2(0, GROUND_Y, 1280, 80), Color(0.15, 0.15, 0.2, 0.9))
	draw_line(Vector2(0, GROUND_Y), Vector2(1280, GROUND_Y), Color(0.35, 0.35, 0.42, 0.6), 2.0)

	# --- Fragments ---
	for frag: Dictionary in fragments:
		_draw_fragment(frag)

	# --- Shatter particles ---
	for p: Dictionary in shatter_particles:
		var col: Color = p.color
		col.a = p.alpha as float
		var sz: float = p.size
		var pp: Vector2 = p.pos
		var shp: int = p.shape
		if shp == 0:
			draw_circle(pp, sz, col)
		elif shp == 1:
			var pts := PackedVector2Array([
				pp + Vector2(0, -sz),
				pp + Vector2(-sz, sz),
				pp + Vector2(sz, sz),
			])
			draw_colored_polygon(pts, col)
		else:
			draw_rect(Rect2(pp.x - sz, pp.y - sz, sz * 2, sz * 2), col)

	# --- Catch flashes ---
	for f: Dictionary in catch_flashes:
		var col: Color = f.color
		col.a = (f.alpha as float) * 0.5
		draw_circle(f.pos as Vector2, f.radius as float, col)
		if f.success:
			# Inner bright ring
			col.a = (f.alpha as float) * 0.8
			draw_arc(f.pos as Vector2, (f.radius as float) * 0.7, 0, TAU, 24, col, 2.0)

	# --- Characters ---
	_draw_blame(p1_pos, p1_facing)
	_draw_denial(p2_pos, p2_facing)


func _draw_fragment(frag: Dictionary) -> void:
	var pos: Vector2 = frag.pos
	var col: Color = frag.color
	var sz: float = frag.size
	var shape: int = frag.shape
	var rot: float = frag.rotation

	# Glow effect underneath
	var glow_col := Color(col.r, col.g, col.b, 0.2)
	draw_circle(pos, sz + 4.0, glow_col)

	if shape == 0:
		# Circle
		draw_circle(pos, sz, col)
		# Inner highlight
		draw_circle(pos + Vector2(-sz * 0.2, -sz * 0.2), sz * 0.4, Color(1, 1, 1, 0.15))
	elif shape == 1:
		# Triangle (rotated)
		var pts := PackedVector2Array()
		for i in range(3):
			var angle: float = rot + float(i) * TAU / 3.0
			pts.append(pos + Vector2(cos(angle), sin(angle)) * sz)
		draw_colored_polygon(pts, col)
		# Edge highlight
		for i in range(3):
			draw_line(pts[i], pts[(i + 1) % 3], Color(1, 1, 1, 0.12), 1.0)
	else:
		# Rectangle (rotated)
		var pts := PackedVector2Array()
		for i in range(4):
			var angle: float = rot + float(i) * TAU / 4.0 + TAU / 8.0
			pts.append(pos + Vector2(cos(angle), sin(angle)) * sz)
		draw_colored_polygon(pts, col)
		for i in range(4):
			draw_line(pts[i], pts[(i + 1) % 4], Color(1, 1, 1, 0.1), 1.0)


func _draw_blame(pos: Vector2, facing: float) -> void:
	var c := GameManager.get_blame_color()
	var cl := GameManager.get_blame_color_light()

	# Legs
	draw_rect(Rect2(pos.x - 13, pos.y - 24, 8, 24), c)
	draw_rect(Rect2(pos.x + 5, pos.y - 24, 8, 24), c)
	# Body
	draw_rect(Rect2(pos.x - 14, pos.y - 56, 28, 34), c)
	draw_rect(Rect2(pos.x - 9, pos.y - 50, 18, 22), Color(cl.r, cl.g, cl.b, 0.25))
	# Head
	draw_rect(Rect2(pos.x - 11, pos.y - 74, 22, 20), c)
	# Eyes
	var eye_x: float = pos.x + facing * 3
	draw_rect(Rect2(eye_x - 6, pos.y - 69, 4, 4), Color(0.7, 0.75, 0.9, 0.8))
	draw_rect(Rect2(eye_x + 2, pos.y - 69, 4, 4), Color(0.7, 0.75, 0.9, 0.8))
	# Arms (reaching up to catch)
	draw_rect(Rect2(pos.x - 20, pos.y - 52, 8, 6), Color(c.r, c.g, c.b, 0.7))
	draw_rect(Rect2(pos.x + 12, pos.y - 52, 8, 6), Color(c.r, c.g, c.b, 0.7))


func _draw_denial(pos: Vector2, facing: float) -> void:
	var c := GameManager.get_denial_color()
	var cl := GameManager.get_denial_color_light()

	# Legs
	draw_circle(Vector2(pos.x - 7, pos.y - 8), 6, c)
	draw_circle(Vector2(pos.x + 7, pos.y - 8), 6, c)
	draw_circle(Vector2(pos.x - 7, pos.y - 18), 5, c)
	draw_circle(Vector2(pos.x + 7, pos.y - 18), 5, c)
	# Body
	draw_circle(Vector2(pos.x, pos.y - 40), 18, c)
	draw_circle(Vector2(pos.x, pos.y - 40), 11, Color(cl.r, cl.g, cl.b, 0.25))
	# Head
	draw_circle(Vector2(pos.x, pos.y - 65), 13, c)
	# Eyes
	var eye_x: float = pos.x + facing * 4
	draw_circle(Vector2(eye_x - 4, pos.y - 67), 2.5, Color(0.95, 0.85, 0.7, 0.8))
	draw_circle(Vector2(eye_x + 4, pos.y - 67), 2.5, Color(0.95, 0.85, 0.7, 0.8))
	# Arms (reaching up)
	draw_circle(Vector2(pos.x - 18, pos.y - 44), 5, Color(c.r, c.g, c.b, 0.7))
	draw_circle(Vector2(pos.x + 18, pos.y - 44), 5, Color(c.r, c.g, c.b, 0.7))


# --- End match ---
func _end_match() -> void:
	match_over = true

	if p1_score > p2_score:
		blame_won = true
	elif p2_score > p1_score:
		blame_won = false
	else:
		blame_won = randf() > 0.5

	GameManager.register_competitive_win(blame_won)
	phase = 1
	_show_result_dialogue()


func _show_result_dialogue() -> void:
	var frag_id := GameManager.get_current_fragment_id()
	var lines: Array[Dictionary] = []

	if frag_id == GameManager.BAD_2:
		# The accident — heavy silence first
		lines = [
			{"speaker": "", "text": "The fragments fall like rain... like that night.", "color": Color(0.5, 0.5, 0.55)},
			{"speaker": "", "text": "...", "color": Color(0.4, 0.4, 0.45)},
		]
	elif frag_id == GameManager.GOOD_2:
		lines = [
			{"speaker": "", "text": "Each fragment held a sliver of warmth. A promise, spoken softly.", "color": Color(0.85, 0.65, 0.45)},
		]
	else:
		lines = [
			{"speaker": "", "text": "The memories scatter... but some pieces cling to us.", "color": Color(0.6, 0.6, 0.65)},
		]

	# Realisation dialogue — they are the same person
	lines.append_array([
		{"speaker": "Denial", "text": "Wait... I feel what you feel.", "color": GameManager.get_denial_color_light()},
		{"speaker": "Blame", "text": "Because we ARE the same.", "color": GameManager.get_blame_color_light()},
		{"speaker": "Denial", "text": "Two halves. One mind.", "color": GameManager.get_denial_color_light()},
		{"speaker": "Blame", "text": "Fighting ourselves this whole time.", "color": GameManager.get_blame_color_light()},
	])

	dialogue.play_dialogue(lines)


func _on_dialogue_done() -> void:
	phase = 2
