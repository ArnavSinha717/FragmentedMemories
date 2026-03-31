extends Control

## Competitive Minigame 2 — Gravity Run: Catch the Memories.
## Both players start on the floor. Press jump to flip gravity and fly to the ceiling.
## Memory fragments scroll right→left through the middle band of the screen.
## Catch your colour while mid-flight. Pits scroll right→left on floor/ceiling — step in = -1pt.
## Catching the wrong colour = -1pt.

@onready var dialogue: Node = $DialogueSystem
@onready var timer_label: Label = $HUD/TimerLabel
@onready var p1_score_label: Label = $HUD/P1Score
@onready var p2_score_label: Label = $HUD/P2Score

# ── Layout ──────────────────────────────────────────────────────────────────
const SCREEN_W    := 1280.0
const SCREEN_H    :=  720.0
const FLOOR_Y     :=  670.0   # y of floor surface (player feet rest here)
const CEILING_Y   :=   50.0   # y of ceiling surface (player head touches here)
const FLOOR_THICK :=   40.0
const CEIL_THICK  :=   40.0
const PLAYER_H    :=   44.0   # visual height

# Fragment travel band (vertical middle of screen)
const FRAG_BAND_TOP := 220.0
const FRAG_BAND_BOT := 500.0

# ── Physics ──────────────────────────────────────────────────────────────────
const GRAVITY    := 1300.0   # pixels/s²
const PLAYER_SPD :=  280.0
const MATCH_TIME :=   35.0

# ── Fragment config ───────────────────────────────────────────────────────────
const FRAG_SPD_BASE  := 230.0
const FRAG_SPD_VAR   :=  70.0
const FRAG_SIZE      :=  18.0
const CATCH_RADIUS   :=  55.0
const SPAWN_BASE     :=   0.5
const SPAWN_VAR      :=   0.3

# ── Pit config ────────────────────────────────────────────────────────────────
const PIT_W_MIN      :=  80.0
const PIT_W_MAX      := 160.0
const PIT_SPD        := 235.0
const PIT_SPAWN_INT  :=   4.0   # base interval between pits per surface
const PIT_INVINCIBLE :=   1.0   # seconds of immunity after hitting a pit

# ── Player state ──────────────────────────────────────────────────────────────
var p1_pos    := Vector2(220.0, FLOOR_Y)
var p1_vel    := Vector2.ZERO
var p1_grav   := 1.0   # +1 = pulled down (toward floor), -1 = pulled up (toward ceiling)
var p1_ground := true  # touching their current surface
var p1_flip_ready := true   # can flip gravity (resets on landing)
var p1_pit_timer  := 0.0    # pit-hit invincibility countdown
var p1_score  := 0
var p1_facing := 1.0

var p2_pos    := Vector2(400.0, FLOOR_Y)
var p2_vel    := Vector2.ZERO
var p2_grav   := 1.0
var p2_ground := true
var p2_flip_ready := true
var p2_pit_timer  := 0.0
var p2_score  := 0
var p2_facing := 1.0

# ── Fragments ─────────────────────────────────────────────────────────────────
# {pos, vel, type(0=cold/1=warm), shape(0-2), color, size, rotation, rot_speed}
var fragments: Array[Dictionary] = []
var frag_spawn_timer := 0.4

# ── Pits ──────────────────────────────────────────────────────────────────────
# {x, w, surface(FLOOR_Y or CEILING_Y), speed}
var pits: Array[Dictionary] = []
var pit_floor_timer := 1.8
var pit_ceil_timer  := 2.4

# ── Speed ramp ────────────────────────────────────────────────────────────────
var speed_mult := 1.0

# ── Visual FX ─────────────────────────────────────────────────────────────────
var shatter_fx: Array[Dictionary] = []
var catch_fx:   Array[Dictionary] = []
var pit_fx:     Array[Dictionary] = []

# ── Match state ───────────────────────────────────────────────────────────────
var match_timer := MATCH_TIME
var match_over  := false
var blame_won   := false
var phase       := -1  # -1=instructions, 0=play, 1=dialogue, 2=advance
var anim_time   := 0.0  # for sprite animation


func _ready() -> void:
	p1_score_label.add_theme_color_override("font_color", GameManager.get_blame_color_light())
	p2_score_label.add_theme_color_override("font_color", GameManager.get_denial_color_light())
	p1_score_label.text = "BLAME: 0"
	p2_score_label.text = "DENIAL: 0"
	# Dialogue no longer used — post-match reactions moved to fragment_reveal


func _process(delta: float) -> void:
	if phase == -1:
		anim_time += delta
		if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("p1_attack") or Input.is_action_just_pressed("p2_attack"):
			phase = 0
		queue_redraw()
		return
	if phase == 2:
		GameManager.advance_phase()
		return
	if phase == 1:
		_update_fx(delta)
		queue_redraw()
		return
	if match_over:
		return

	anim_time += delta
	match_timer -= delta
	timer_label.text = str(ceili(match_timer))
	if match_timer <= 0.0:
		match_timer = 0.0
		_end_match()
		return

	speed_mult = 1.0 + (1.0 - match_timer / MATCH_TIME) * 0.9

	_handle_input(delta)
	_physics(delta)
	_spawn_logic(delta)
	_update_fragments(delta)
	_update_pits(delta)
	_check_catches()
	_check_pit_falls()
	_update_fx(delta)

	p1_pit_timer = maxf(0.0, p1_pit_timer - delta)
	p2_pit_timer = maxf(0.0, p2_pit_timer - delta)

	p1_score_label.text = "BLAME: "  + str(p1_score)
	p2_score_label.text = "DENIAL: " + str(p2_score)

	var total := float(abs(p1_score) + abs(p2_score) + 1)
	var h := clampf(0.5 + float(p2_score - p1_score) / (total * 2.0), 0.0, 1.0)
	GameManager.set_hue(lerpf(GameManager.hue_value, h, 2.0 * delta))

	queue_redraw()


# ── Input ─────────────────────────────────────────────────────────────────────

func _handle_input(delta: float) -> void:
	# P1 (Blame) — left/right + jump to flip gravity
	var d1 := 0.0
	if Input.is_action_pressed("p1_left"):  d1 -= 1.0
	if Input.is_action_pressed("p1_right"): d1 += 1.0
	if d1 != 0.0: p1_facing = d1
	p1_vel.x = lerpf(p1_vel.x, d1 * PLAYER_SPD, 10.0 * delta)

	if p1_flip_ready and Input.is_action_just_pressed("p1_up"):
		p1_grav       *= -1.0   # flip gravity direction
		p1_ground      = false
		p1_flip_ready  = false  # must land before flipping again

	# P2 (Denial)
	var d2 := 0.0
	if Input.is_action_pressed("p2_left"):  d2 -= 1.0
	if Input.is_action_pressed("p2_right"): d2 += 1.0
	if d2 != 0.0: p2_facing = d2
	p2_vel.x = lerpf(p2_vel.x, d2 * PLAYER_SPD, 10.0 * delta)

	if p2_flip_ready and Input.is_action_just_pressed("p2_up"):
		p2_grav       *= -1.0
		p2_ground      = false
		p2_flip_ready  = false


# ── Physics ───────────────────────────────────────────────────────────────────

func _physics(delta: float) -> void:
	# P1
	p1_vel.y  += GRAVITY * p1_grav * delta
	p1_pos    += p1_vel * delta
	p1_pos.x   = clampf(p1_pos.x, 16.0, SCREEN_W - 16.0)
	p1_ground  = false

	if p1_grav > 0.0 and p1_pos.y >= FLOOR_Y:
		p1_pos.y = FLOOR_Y; p1_vel.y = 0.0; p1_ground = true; p1_flip_ready = true
	elif p1_grav < 0.0 and p1_pos.y <= CEILING_Y:
		p1_pos.y = CEILING_Y; p1_vel.y = 0.0; p1_ground = true; p1_flip_ready = true

	# P2
	p2_vel.y  += GRAVITY * p2_grav * delta
	p2_pos    += p2_vel * delta
	p2_pos.x   = clampf(p2_pos.x, 16.0, SCREEN_W - 16.0)
	p2_ground  = false

	if p2_grav > 0.0 and p2_pos.y >= FLOOR_Y:
		p2_pos.y = FLOOR_Y; p2_vel.y = 0.0; p2_ground = true; p2_flip_ready = true
	elif p2_grav < 0.0 and p2_pos.y <= CEILING_Y:
		p2_pos.y = CEILING_Y; p2_vel.y = 0.0; p2_ground = true; p2_flip_ready = true


# ── Spawning ──────────────────────────────────────────────────────────────────

func _spawn_logic(delta: float) -> void:
	frag_spawn_timer -= delta
	if frag_spawn_timer <= 0.0:
		frag_spawn_timer = randf_range(SPAWN_BASE - SPAWN_VAR, SPAWN_BASE + SPAWN_VAR) / speed_mult
		_spawn_fragment()

	pit_floor_timer -= delta
	if pit_floor_timer <= 0.0:
		pit_floor_timer = randf_range(PIT_SPAWN_INT * 0.7, PIT_SPAWN_INT * 1.5)
		_spawn_pit(FLOOR_Y)

	pit_ceil_timer -= delta
	if pit_ceil_timer <= 0.0:
		pit_ceil_timer = randf_range(PIT_SPAWN_INT * 0.7, PIT_SPAWN_INT * 1.5)
		_spawn_pit(CEILING_Y)


func _spawn_fragment() -> void:
	var ftype := 0 if randf() < 0.5 else 1
	var shape := randi() % 3
	var y_pos := randf_range(FRAG_BAND_TOP + 12.0, FRAG_BAND_BOT - 12.0)
	var spd   := (FRAG_SPD_BASE + randf_range(-FRAG_SPD_VAR, FRAG_SPD_VAR)) * speed_mult
	var sz    := randf_range(FRAG_SIZE * 0.8, FRAG_SIZE * 1.3)
	var col: Color
	if ftype == 0:
		# Cold / blame: blue-purple
		col = Color(randf_range(0.15, 0.35), randf_range(0.18, 0.35), randf_range(0.5, 0.8), 0.9)
	else:
		# Warm / denial: orange
		col = Color(randf_range(0.8, 0.98), randf_range(0.4, 0.65), randf_range(0.15, 0.35), 0.9)
	fragments.append({
		"pos": Vector2(SCREEN_W + 30.0, y_pos),
		"vel": Vector2(-spd, 0.0),
		"type": ftype, "shape": shape, "color": col, "size": sz,
		"rotation": randf_range(0.0, TAU), "rot_speed": randf_range(-2.5, 2.5),
	})


func _spawn_pit(surface: float) -> void:
	var w := randf_range(PIT_W_MIN, PIT_W_MAX)
	pits.append({
		"x": SCREEN_W + 10.0,
		"w": w,
		"surface": surface,
		"speed": PIT_SPD * speed_mult,
	})


# ── Update objects ────────────────────────────────────────────────────────────

func _update_fragments(delta: float) -> void:
	for i in range(fragments.size() - 1, -1, -1):
		var f: Dictionary = fragments[i]
		f.pos      = (f.pos as Vector2) + (f.vel as Vector2) * delta
		f.rotation = (f.rotation as float) + (f.rot_speed as float) * delta
		if (f.pos as Vector2).x < -50.0:
			fragments.remove_at(i)


func _update_pits(delta: float) -> void:
	for i in range(pits.size() - 1, -1, -1):
		var p: Dictionary = pits[i]
		p.x = (p.x as float) - (p.speed as float) * delta
		if (p.x as float) + (p.w as float) < -10.0:
			pits.remove_at(i)


# ── Catch detection ───────────────────────────────────────────────────────────

func _check_catches() -> void:
	for i in range(fragments.size() - 1, -1, -1):
		if i >= fragments.size():
			break
		var frag: Dictionary = fragments[i]
		var fp:    Vector2   = frag.pos
		var ftype: int       = frag.type

		# Body centre: midpoint between surface and opposite end of character
		# For floor player: centre is PLAYER_H/2 above feet → pos.y - PLAYER_H*0.5
		# For ceiling player: centre is PLAYER_H/2 below ceiling → pos.y + PLAYER_H*0.5
		# Unified formula: pos.y - grav * PLAYER_H * 0.5
		var p1c := Vector2(p1_pos.x, p1_pos.y - p1_grav * PLAYER_H * 0.5)
		var p2c := Vector2(p2_pos.x, p2_pos.y - p2_grav * PLAYER_H * 0.5)

		var d1 := p1c.distance_to(fp)
		var d2 := p2c.distance_to(fp)

		var caught_by := 0
		if d1 < CATCH_RADIUS and (d1 <= d2 or d2 >= CATCH_RADIUS):
			caught_by = 1
		elif d2 < CATCH_RADIUS:
			caught_by = 2
		if caught_by == 0:
			continue

		# Blame (P1) catches cold/type-0; Denial (P2) catches warm/type-1
		var correct := (caught_by == 1 and ftype == 0) or (caught_by == 2 and ftype == 1)
		var cpos    := p1_pos if caught_by == 1 else p2_pos

		if correct:
			if caught_by == 1: p1_score += 1
			else:              p2_score += 1
			_fx_catch(cpos, frag.color as Color, true)
		else:
			if caught_by == 1: p1_score -= 1
			else:              p2_score -= 1
			_fx_shatter(fp, frag.color as Color)
			_fx_catch(cpos, Color(1.0, 0.2, 0.2, 0.8), false)

		fragments.remove_at(i)


# ── Pit collision ─────────────────────────────────────────────────────────────

func _check_pit_falls() -> void:
	for pit in pits:
		var px: float = pit.x
		var pw: float = pit.w
		var ps: float = pit.surface

		# P1 — only check when grounded on the matching surface and not invincible
		if p1_ground and p1_pit_timer <= 0.0:
			var p1_surf := FLOOR_Y if p1_grav > 0.0 else CEILING_Y
			if absf(p1_surf - ps) < 2.0 and p1_pos.x >= px and p1_pos.x <= px + pw:
				p1_score     -= 1
				p1_pit_timer  = PIT_INVINCIBLE
				p1_ground     = false
				p1_flip_ready = true      # allow immediate re-flip to escape
				p1_grav      *= -1.0      # gravity reverses — player drifts toward opposite surface
				_fx_pit(p1_pos)

		# P2
		if p2_ground and p2_pit_timer <= 0.0:
			var p2_surf := FLOOR_Y if p2_grav > 0.0 else CEILING_Y
			if absf(p2_surf - ps) < 2.0 and p2_pos.x >= px and p2_pos.x <= px + pw:
				p2_score     -= 1
				p2_pit_timer  = PIT_INVINCIBLE
				p2_ground     = false
				p2_flip_ready = true
				p2_grav      *= -1.0
				_fx_pit(p2_pos)


# ── Visual FX helpers ─────────────────────────────────────────────────────────

func _fx_shatter(pos: Vector2, col: Color) -> void:
	for _i in range(8):
		var angle := randf_range(0.0, TAU)
		var spd   := randf_range(60.0, 190.0)
		shatter_fx.append({
			"pos":   Vector2(pos.x, pos.y),
			"vel":   Vector2(cos(angle) * spd, sin(angle) * spd),
			"alpha": 1.0, "color": col,
			"size":  randf_range(2.0, 6.0), "shape": randi() % 3,
		})


func _fx_catch(pos: Vector2, col: Color, success: bool) -> void:
	catch_fx.append({
		"pos":     Vector2(pos.x, pos.y - 20.0),
		"alpha":   1.0, "color": col,
		"radius":  8.0 if success else 12.0,
		"success": success,
	})


func _fx_pit(pos: Vector2) -> void:
	pit_fx.append({"pos": Vector2(pos.x, pos.y), "alpha": 1.0, "radius": 6.0})


func _update_fx(delta: float) -> void:
	for i in range(shatter_fx.size() - 1, -1, -1):
		var p: Dictionary = shatter_fx[i]
		p.vel   = (p.vel as Vector2)   + Vector2(0.0, 280.0) * delta
		p.pos   = (p.pos as Vector2)   + (p.vel as Vector2) * delta
		p.alpha = (p.alpha as float)   - delta * 1.5
		if (p.alpha as float) <= 0.0: shatter_fx.remove_at(i)

	for i in range(catch_fx.size() - 1, -1, -1):
		var f: Dictionary = catch_fx[i]
		f.alpha  = (f.alpha  as float) - delta * 3.0
		f.radius = (f.radius as float) + delta * 80.0
		if (f.alpha as float) <= 0.0: catch_fx.remove_at(i)

	for i in range(pit_fx.size() - 1, -1, -1):
		var f: Dictionary = pit_fx[i]
		f.alpha  = (f.alpha  as float) - delta * 2.5
		f.radius = (f.radius as float) + delta * 110.0
		if (f.alpha as float) <= 0.0: pit_fx.remove_at(i)


# ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	# Background handled by global ShardBackground autoload
	if phase == -1:
		_draw_instructions()
		return
	_draw_surfaces()
	_draw_middle_band()
	_draw_fragments()
	_draw_shatter()
	_draw_catch_fx()
	_draw_pit_fx()
	_draw_blame(p1_pos, p1_facing, p1_grav)
	_draw_denial(p2_pos, p2_facing, p2_grav)


func _draw_instructions() -> void:
	var font := ThemeDB.fallback_font
	var ca: float = 0.65 + sin(anim_time * 3.0) * 0.12
	var cc := Color(0.65, 0.65, 0.75, ca)
	var hl := Color(0.5, 0.5, 0.65, ca * 0.6)
	# Title
	draw_string(font, Vector2(420, 120), "GRAVITY RUN", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(0.7, 0.7, 0.85, ca))
	draw_string(font, Vector2(420, 150), "Catch the Memories", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.55, 0.55, 0.65, ca * 0.7))
	# P1
	draw_string(font, Vector2(80, 220), "BLAME", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(GameManager.get_blame_color_light(), ca))
	draw_line(Vector2(80, 227), Vector2(230, 227), Color(GameManager.get_blame_color(), ca * 0.3), 1.0)
	draw_string(font, Vector2(80, 250), "Move: A / D  |  Flip Gravity: W / A", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, hl)
	draw_string(font, Vector2(80, 270), "Catch BLUE fragments for +1 pt", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, cc)
	draw_string(font, Vector2(80, 290), "Wrong colour = -1 pt  |  Pits = -1 pt", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, cc)
	# P2
	draw_string(font, Vector2(740, 220), "DENIAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(GameManager.get_denial_color_light(), ca))
	draw_line(Vector2(740, 227), Vector2(900, 227), Color(GameManager.get_denial_color(), ca * 0.3), 1.0)
	draw_string(font, Vector2(740, 250), "Move: Left / Right  |  Flip: Up / A", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, hl)
	draw_string(font, Vector2(740, 270), "Catch ORANGE fragments for +1 pt", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, cc)
	draw_string(font, Vector2(740, 290), "Wrong colour = -1 pt  |  Pits = -1 pt", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, cc)
	# How to play
	draw_string(font, Vector2(350, 370), "Flip gravity mid-air to catch fragments", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 0.6, 0.7, ca * 0.8))
	draw_string(font, Vector2(370, 395), "Speed increases as time runs out!", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 0.6, 0.7, ca * 0.8))
	# Start prompt
	var ct_a: float = 0.5 + sin(anim_time * 2.0) * 0.2
	draw_string(font, Vector2(440, 480), "Press SPACE / X to Start", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.8, 0.8, 0.9, ct_a))


func _draw_surfaces() -> void:
	var surf_col := Color(0.15, 0.15, 0.2, 0.95)
	var edge_col := Color(0.35, 0.35, 0.45, 0.7)
	var pit_col  := Color(0.04, 0.04, 0.08, 1.0)
	var pit_glow := Color(0.75, 0.1, 0.1, 0.4)

	# Solid floor and ceiling bars
	draw_rect(Rect2(0.0, FLOOR_Y,   SCREEN_W, FLOOR_THICK), surf_col)
	draw_rect(Rect2(0.0, 0.0,       SCREEN_W, CEIL_THICK),  surf_col)
	draw_line(Vector2(0.0, FLOOR_Y),   Vector2(SCREEN_W, FLOOR_Y),   edge_col, 2.0)
	draw_line(Vector2(0.0, CEILING_Y), Vector2(SCREEN_W, CEILING_Y), edge_col, 2.0)

	# Draw pits as void cut-outs with a red danger glow at the lip
	for pit in pits:
		var px: float = pit.x
		var pw: float = pit.w
		var ps: float = pit.surface
		if ps == FLOOR_Y:
			draw_rect(Rect2(px, FLOOR_Y,   pw, FLOOR_THICK), pit_col)
			draw_rect(Rect2(px, FLOOR_Y,   pw, 3.0),         pit_glow)
		else:
			draw_rect(Rect2(px, 0.0,              pw, CEIL_THICK),  pit_col)
			draw_rect(Rect2(px, CEILING_Y - 3.0,  pw, 3.0),         pit_glow)


func _draw_middle_band() -> void:
	# Faint highlight so players know the catch zone
	draw_rect(
		Rect2(0.0, FRAG_BAND_TOP, SCREEN_W, FRAG_BAND_BOT - FRAG_BAND_TOP),
		Color(1.0, 1.0, 1.0, 0.03)
	)
	var guide := Color(0.3, 0.3, 0.42, 0.22)
	draw_line(Vector2(0.0, FRAG_BAND_TOP), Vector2(SCREEN_W, FRAG_BAND_TOP), guide, 1.0)
	draw_line(Vector2(0.0, FRAG_BAND_BOT), Vector2(SCREEN_W, FRAG_BAND_BOT), guide, 1.0)


func _draw_fragments() -> void:
	for frag in fragments:
		_draw_fragment(frag)


func _draw_fragment(frag: Dictionary) -> void:
	var pos:   Vector2 = frag.pos
	var col:   Color   = frag.color
	var sz:    float   = frag.size
	var shape: int     = frag.shape
	var rot:   float   = frag.rotation

	draw_circle(pos, sz + 5.0, Color(col.r, col.g, col.b, 0.18))  # soft glow

	if shape == 0:
		draw_circle(pos, sz, col)
		draw_circle(pos + Vector2(-sz * 0.2, -sz * 0.2), sz * 0.4, Color(1, 1, 1, 0.15))
	elif shape == 1:
		var pts := PackedVector2Array()
		for i in range(3):
			var a := rot + float(i) * TAU / 3.0
			pts.append(pos + Vector2(cos(a), sin(a)) * sz)
		draw_colored_polygon(pts, col)
		for i in range(3):
			draw_line(pts[i], pts[(i + 1) % 3], Color(1, 1, 1, 0.12), 1.0)
	else:
		var pts := PackedVector2Array()
		for i in range(4):
			var a := rot + float(i) * TAU / 4.0 + TAU / 8.0
			pts.append(pos + Vector2(cos(a), sin(a)) * sz)
		draw_colored_polygon(pts, col)
		for i in range(4):
			draw_line(pts[i], pts[(i + 1) % 4], Color(1, 1, 1, 0.1), 1.0)


func _draw_shatter() -> void:
	for p in shatter_fx:
		var col: Color  = p.color
		col.a = p.alpha as float
		var sz: float   = p.size
		var pp: Vector2 = p.pos
		match (p.shape as int):
			0: draw_circle(pp, sz, col)
			1:
				draw_colored_polygon(PackedVector2Array([
					pp + Vector2(0, -sz), pp + Vector2(-sz, sz), pp + Vector2(sz, sz)
				]), col)
			_: draw_rect(Rect2(pp.x - sz, pp.y - sz, sz * 2.0, sz * 2.0), col)


func _draw_catch_fx() -> void:
	for f in catch_fx:
		var col: Color = f.color
		col.a = (f.alpha as float) * 0.5
		draw_circle(f.pos as Vector2, f.radius as float, col)
		if f.success:
			col.a = (f.alpha as float) * 0.8
			draw_arc(f.pos as Vector2, (f.radius as float) * 0.7, 0.0, TAU, 24, col, 2.0)


func _draw_pit_fx() -> void:
	for f in pit_fx:
		draw_circle(f.pos as Vector2, f.radius as float,
			Color(1.0, 0.3, 0.3, (f.alpha as float) * 0.55))


# ── Character drawing ─────────────────────────────────────────────────────────
# 'd' = drawing direction from surface: -1 when on floor (draw upward), +1 when on ceiling (draw downward)
# All y-offsets use: surface_y + d * offset, with rects normalised so height is always positive.

func _draw_blame(pos: Vector2, facing: float, grav: float) -> void:
	var flip_v: bool = grav < 0.0
	var flip_h: bool = facing < 0.0
	var g_row: int = 5
	var g_frame: int = 0
	if absf(p1_vel.x) > 30:
		g_row = 6
		g_frame = GameManager.anim_frame(anim_time, 6, 10.0)
	elif not p1_ground:
		g_row = 6
		g_frame = 2
	else:
		g_row = 5
		g_frame = GameManager.anim_frame(anim_time, 4, 6.0)
	if flip_v:
		GameManager.draw_blame_sprite_flipped(self, pos, g_frame, g_row, 1.0, flip_h)
	else:
		GameManager.draw_blame_sprite(self, pos, g_frame, g_row, 1.0, flip_h)


func _draw_denial(pos: Vector2, facing: float, grav: float) -> void:
	var flip_v: bool = grav < 0.0
	var flip_h: bool = facing < 0.0
	var r_row: int = 0
	var r_frame: int = 0
	if absf(p2_vel.x) > 30:
		r_row = 1
		r_frame = GameManager.anim_frame(anim_time, 4, 10.0)
	elif not p2_ground:
		r_row = 1
		r_frame = 1
	else:
		r_row = 0
		r_frame = GameManager.anim_frame(anim_time, 2, 3.0)
	if flip_v:
		GameManager.draw_denial_sprite_flipped(self, pos, r_frame, r_row, 1.6, flip_h)
	else:
		GameManager.draw_denial_sprite(self, pos, r_frame, r_row, 1.6, flip_h)


## Draw a rect whose top-left is determined by direction d.
## d < 0 (upward): rect sits ABOVE anchor_y  → top = anchor_y - h
## d > 0 (downward): rect sits BELOW anchor_y → top = anchor_y
func _drect(x: float, anchor_y: float, w: float, h: float, d: float, col: Color) -> void:
	var top_y := anchor_y - h if d < 0.0 else anchor_y
	draw_rect(Rect2(x, top_y, w, h), col)


# ── End match ─────────────────────────────────────────────────────────────────

func _end_match() -> void:
	match_over = true
	blame_won  = p1_score > p2_score or (p1_score == p2_score and randf() > 0.5)
	GameManager.register_competitive_win(blame_won)
	# Post-match dialogue moved to fragment_reveal scene
	phase = 2
