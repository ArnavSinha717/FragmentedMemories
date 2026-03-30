extends Control

## Cooperative Minigame — "Weighing the Past"
## Blame (P1) and Denial (P2) stand on pulley-linked platforms.
## One side descends when a player stands on it, lifting the other.
## Collect all memory gems and both reach the exit platform to win.

@onready var dialogue: Node = $DialogueSystem

# ─── Physics ───────────────────────────────────────────────────────────────
const GRAVITY        := 900.0
const JUMP_SPEED     := -450.0
const PLAYER_SPEED   := 260.0
const PLAYER_W       := 40.0
const PLAYER_H       := 40.0
const PLAYER_RADIUS  := 22.0

# ─── Pulley tuning ─────────────────────────────────────────────────────────
const PULLEY_SPEED      := 130.0
const PLAYER_WEIGHT     := 1.0
const PLAT_TRAVEL_HALF  := 160.0

# ─── Time ──────────────────────────────────────────────────────────────────
const TIME_LIMIT := 90.0
var time_remaining: float = TIME_LIMIT

# ─── Game phase: 0=playing  1=win_dialogue  2=done ─────────────────────────
var phase: int = 0
var pulse_time: float = 0.0

# ─── Win condition tracking ────────────────────────────────────────────────
var exit_overlap_timer: float = 0.0
const EXIT_HOLD_TIME := 2.0

# ─── Player state ──────────────────────────────────────────────────────────
var p1_pos := Vector2(180.0, 560.0)
var p1_vel := Vector2.ZERO
var p1_on_ground: bool = false
var p1_stagger: float = 0.0

var p2_pos := Vector2(1100.0, 560.0)
var p2_vel := Vector2.ZERO
var p2_on_ground: bool = false
var p2_stagger: float = 0.0

# ─── Pulley pairs ──────────────────────────────────────────────────────────
const PLAT_W := 140.0
const PLAT_H := 16.0

var pp0_anchor_x   : float = 640.0
var pp0_left_y     : float = 520.0
var pp0_right_y    : float = 520.0
var pp0_min_y      : float = 360.0
var pp0_max_y      : float = 580.0

var pp1_anchor_x   : float = 640.0
var pp1_left_y     : float = 280.0
var pp1_right_y    : float = 280.0
var pp1_min_y      : float = 160.0
var pp1_max_y      : float = 340.0

const PP_OFFSET := 220.0

# ─── Static platforms ──────────────────────────────────────────────────────
var static_platforms: Array[Rect2] = []

# ─── Memory Gems ───────────────────────────────────────────────────────────
const GEM_RADIUS := 10.0
var gems: Array[Dictionary] = []

const COLD_COLOR  := Color(0.3, 0.5, 1.0)
const WARM_COLOR  := Color(1.0, 0.6, 0.2)
const COLD_LIGHT  := Color(0.6, 0.75, 1.0)
const WARM_LIGHT  := Color(1.0, 0.82, 0.55)

# ─── Levers & Gates ────────────────────────────────────────────────────────
var levers: Array[Dictionary] = []
var gates:  Array[Dictionary] = []
const LEVER_RADIUS := 14.0
const LEVER_RANGE  := 40.0

# ─── Shared Burden Platform ────────────────────────────────────────────────
var burden_plat_y   : float = 430.0
const BURDEN_PLAT_X : float = 490.0
const BURDEN_PLAT_W : float = 300.0
const BURDEN_PLAT_RESTING_Y : float = 430.0
const BURDEN_PLAT_LOW_Y     : float = 530.0
var burden_both_on  : bool = false

# ─── Exit platform ─────────────────────────────────────────────────────────
const EXIT_RECT := Rect2(540.0, 610.0, 200.0, 18.0)

# ─── Screen flash ──────────────────────────────────────────────────────────
var flash_timer  : float = 0.0
var flash_color  : Color = Color.WHITE

# ─── Particles ─────────────────────────────────────────────────────────────
var particles: Array[Dictionary] = []


func _ready() -> void:
	dialogue.dialogue_finished.connect(_on_dialogue_done)
	_build_level()


func _build_level() -> void:
	static_platforms.append(Rect2(0.0, 630.0, 1280.0, 90.0))
	static_platforms.append(Rect2(20.0, 480.0, 200.0, 18.0))
	static_platforms.append(Rect2(1060.0, 480.0, 200.0, 18.0))
	static_platforms.append(Rect2(60.0, 370.0, 100.0, 14.0))
	static_platforms.append(Rect2(1120.0, 370.0, 100.0, 14.0))

	_add_gem("cold", Vector2(130.0, 455.0))
	_add_gem("cold", Vector2(80.0,  345.0))
	_add_gem("cold", Vector2(350.0, 490.0))
	_add_gem("cold", Vector2(390.0, 230.0))
	_add_gem("cold", Vector2(180.0, 240.0))
	_add_gem("cold", Vector2(460.0, 350.0))

	_add_gem("warm", Vector2(1150.0, 455.0))
	_add_gem("warm", Vector2(1200.0, 345.0))
	_add_gem("warm", Vector2(930.0,  490.0))
	_add_gem("warm", Vector2(890.0,  230.0))
	_add_gem("warm", Vector2(1100.0, 240.0))
	_add_gem("warm", Vector2(820.0,  350.0))

	gates.append({"rect": Rect2(420.0, 350.0, 18.0, 120.0), "open": false})
	levers.append({"pos": Vector2(960.0, 455.0), "held": false, "gate_index": 0})
	gates.append({"rect": Rect2(842.0, 350.0, 18.0, 120.0), "open": false})
	levers.append({"pos": Vector2(320.0, 455.0), "held": false, "gate_index": 1})


func _add_gem(type: String, pos: Vector2) -> void:
	gems.append({"type": type, "pos": pos, "collected": false, "respawn_timer": 0.0})


func _process(delta: float) -> void:
	pulse_time += delta
	if phase == 2:
		GameManager.advance_phase()
		return
	if phase == 1:
		queue_redraw()
		return

	time_remaining -= delta
	if time_remaining <= 0.0:
		time_remaining = 0.0
		phase = 1
		_show_dialogue()
		return

	for lv: Dictionary in levers:
		lv["held"] = false

	_update_player(true,  delta)
	_update_player(false, delta)
	_update_pulley(delta)
	_update_burden(delta)
	_update_gems(delta)
	_update_particles(delta)
	flash_timer = maxf(flash_timer - delta, 0.0)

	for i: int in range(levers.size()):
		var lv: Dictionary = levers[i]
		gates[lv["gate_index"] as int]["open"] = lv["held"]

	var all_collected: bool = true
	for gem: Dictionary in gems:
		if not gem["collected"]:
			all_collected = false
			break

	if all_collected:
		var p1_on_exit: bool = _point_on_rect(p1_pos, EXIT_RECT, PLAYER_W * 0.5, PLAYER_H * 0.5)
		var p2_on_exit: bool = _point_on_rect(p2_pos, EXIT_RECT, PLAYER_RADIUS, PLAYER_RADIUS)
		if p1_on_exit and p2_on_exit:
			exit_overlap_timer += delta
			if exit_overlap_timer >= EXIT_HOLD_TIME:
				phase = 1
				_show_dialogue()
		else:
			exit_overlap_timer = 0.0

	queue_redraw()


func _update_player(is_p1: bool, delta: float) -> void:
	var pos: Vector2 = p1_pos if is_p1 else p2_pos
	var vel: Vector2 = p1_vel if is_p1 else p2_vel
	var stagger: float = p1_stagger if is_p1 else p2_stagger
	var on_ground: bool = false
	var half_w: float = PLAYER_W * 0.5 if is_p1 else PLAYER_RADIUS
	var half_h: float = PLAYER_H * 0.5 if is_p1 else PLAYER_RADIUS

	stagger = maxf(stagger - delta, 0.0)
	var dir_x: float = 0.0
	if stagger <= 0.0:
		if is_p1:
			if Input.is_action_pressed("p1_left"):  dir_x -= 1.0
			if Input.is_action_pressed("p1_right"): dir_x += 1.0
		else:
			if Input.is_action_pressed("p2_left"):  dir_x -= 1.0
			if Input.is_action_pressed("p2_right"): dir_x += 1.0

	vel.x = lerpf(vel.x, dir_x * PLAYER_SPEED, 10.0 * delta)
	vel.y += GRAVITY * delta
	pos += vel * delta

	var all_rects: Array[Rect2] = []
	for sp: Rect2 in static_platforms:
		all_rects.append(sp)
	all_rects.append(_pp0_left_rect())
	all_rects.append(_pp0_right_rect())
	all_rects.append(_pp1_left_rect())
	all_rects.append(_pp1_right_rect())
	all_rects.append(_burden_rect())

	for plat: Rect2 in all_rects:
		var pb: float = pos.y + half_h
		var pl: float = pos.x - half_w
		var pr: float = pos.x + half_w
		if pr > plat.position.x and pl < plat.end.x:
			if pb >= plat.position.y and pb <= plat.position.y + plat.size.y + 12.0 and vel.y >= 0.0:
				pos.y = plat.position.y - half_h
				vel.y = 0.0
				on_ground = true

	for gate: Dictionary in gates:
		if gate["open"]:
			continue
		var gr: Rect2 = gate["rect"]
		var player_rect: Rect2 = Rect2(pos.x - half_w, pos.y - half_h, half_w * 2.0, half_h * 2.0)
		if player_rect.intersects(gr):
			var ox: float = minf(player_rect.end.x - gr.position.x, gr.end.x - player_rect.position.x)
			var oy: float = minf(player_rect.end.y - gr.position.y, gr.end.y - player_rect.position.y)
			if ox < oy:
				if pos.x < gr.get_center().x:
					pos.x = gr.position.x - half_w
				else:
					pos.x = gr.end.x + half_w
			else:
				if pos.y < gr.get_center().y:
					pos.y = gr.position.y - half_h
					vel.y = 0.0
				else:
					pos.y = gr.end.y + half_h
					if vel.y < 0.0: vel.y = 0.0

	pos.x = clampf(pos.x, 20.0, 1260.0)
	if pos.y > 610.0:
		pos.y = 610.0
		vel.y = 0.0
		on_ground = true

	if on_ground and stagger <= 0.0:
		if is_p1 and Input.is_action_just_pressed("p1_up"):
			vel.y = JUMP_SPEED
			on_ground = false
		elif not is_p1 and Input.is_action_just_pressed("p2_up"):
			vel.y = JUMP_SPEED
			on_ground = false

	for lv: Dictionary in levers:
		var lpos: Vector2 = lv["pos"]
		if pos.distance_to(lpos) < LEVER_RANGE:
			var pressing: bool = false
			if is_p1 and Input.is_action_pressed("p1_attack"):
				pressing = true
			elif not is_p1 and Input.is_action_pressed("p2_attack"):
				pressing = true
			if pressing:
				lv["held"] = true

	if is_p1:
		p1_pos = pos; p1_vel = vel; p1_on_ground = on_ground; p1_stagger = stagger
	else:
		p2_pos = pos; p2_vel = vel; p2_on_ground = on_ground; p2_stagger = stagger


func _update_pulley(delta: float) -> void:
	_move_pulley_pair(delta, 0)
	_move_pulley_pair(delta, 1)


func _move_pulley_pair(delta: float, pair: int) -> void:
	var left_rect: Rect2 = _pp_left_rect(pair)
	var right_rect: Rect2 = _pp_right_rect(pair)
	var left_w: float = 0.0
	var right_w: float = 0.0

	for check_p1: bool in [true, false]:
		var ppos: Vector2 = p1_pos if check_p1 else p2_pos
		var hw: float = PLAYER_W * 0.5 if check_p1 else PLAYER_RADIUS
		var hh: float = PLAYER_H * 0.5 if check_p1 else PLAYER_RADIUS
		var pb: float = ppos.y + hh
		var pl: float = ppos.x - hw
		var pr: float = ppos.x + hw
		if absf(pb - left_rect.position.y) < 6.0 and pr > left_rect.position.x and pl < left_rect.end.x:
			left_w += PLAYER_WEIGHT
		if absf(pb - right_rect.position.y) < 6.0 and pr > right_rect.position.x and pl < right_rect.end.x:
			right_w += PLAYER_WEIGHT

	var imbalance: float = left_w - right_w
	if absf(imbalance) < 0.01:
		return
	var move: float = imbalance * PULLEY_SPEED * delta

	if pair == 0:
		pp0_left_y  = clampf(pp0_left_y  + move, pp0_min_y, pp0_max_y)
		pp0_right_y = clampf(pp0_right_y - move, pp0_min_y, pp0_max_y)
	else:
		pp1_left_y  = clampf(pp1_left_y  + move, pp1_min_y, pp1_max_y)
		pp1_right_y = clampf(pp1_right_y - move, pp1_min_y, pp1_max_y)


func _update_burden(delta: float) -> void:
	var br: Rect2 = _burden_rect()
	var p1_on: bool = _standing_on(p1_pos, PLAYER_W * 0.5, PLAYER_H * 0.5, br)
	var p2_on: bool = _standing_on(p2_pos, PLAYER_RADIUS, PLAYER_RADIUS, br)
	burden_both_on = p1_on and p2_on
	var target_y: float = BURDEN_PLAT_LOW_Y if burden_both_on else BURDEN_PLAT_RESTING_Y
	burden_plat_y = lerpf(burden_plat_y, target_y, 3.0 * delta)


func _standing_on(pos: Vector2, half_w: float, half_h: float, plat: Rect2) -> bool:
	var pb: float = pos.y + half_h
	return absf(pb - plat.position.y) < 8.0 and pos.x + half_w > plat.position.x and pos.x - half_w < plat.end.x


func _update_gems(delta: float) -> void:
	for gem: Dictionary in gems:
		if gem["collected"]:
			gem["respawn_timer"] = maxf(float(gem["respawn_timer"]) - delta, 0.0)
			if float(gem["respawn_timer"]) <= 0.0:
				gem["collected"] = false
			continue
		var gpos: Vector2 = gem["pos"]
		var gtype: String = gem["type"]
		if gtype == "cold":
			if p1_pos.distance_to(gpos) < GEM_RADIUS + PLAYER_W * 0.5:
				_collect_gem(gem, true)
			elif p2_pos.distance_to(gpos) < GEM_RADIUS + PLAYER_RADIUS:
				_wrong_gem(false, gpos)
				gem["collected"] = true
				gem["respawn_timer"] = 3.0
		elif gtype == "warm":
			if p2_pos.distance_to(gpos) < GEM_RADIUS + PLAYER_RADIUS:
				_collect_gem(gem, false)
			elif p1_pos.distance_to(gpos) < GEM_RADIUS + PLAYER_W * 0.5:
				_wrong_gem(true, gpos)
				gem["collected"] = true
				gem["respawn_timer"] = 3.0


func _collect_gem(gem: Dictionary, is_p1: bool) -> void:
	gem["collected"] = true
	gem["respawn_timer"] = 999.0
	_spawn_burst(gem["pos"], COLD_COLOR if is_p1 else WARM_COLOR, 12)


func _wrong_gem(is_p1: bool, gpos: Vector2) -> void:
	if is_p1:
		p1_stagger = 0.5
		p1_vel.x = -sign(p1_vel.x) * 200.0
	else:
		p2_stagger = 0.5
		p2_vel.x = -sign(p2_vel.x) * 200.0
	flash_timer = 0.25
	flash_color = Color(1.0, 0.2, 0.2, 0.35)
	_spawn_burst(gpos, Color(0.8, 0.2, 0.2), 8)


func _spawn_burst(pos: Vector2, col: Color, count: int) -> void:
	for _i: int in range(count):
		var angle: float = randf() * TAU
		var speed: float = randf_range(60.0, 180.0)
		particles.append({"pos": pos, "vel": Vector2(cos(angle), sin(angle)) * speed, "color": col, "life": 0.5, "max_life": 0.5})


func _update_particles(delta: float) -> void:
	var i: int = particles.size() - 1
	while i >= 0:
		var p: Dictionary = particles[i]
		p["life"] = float(p["life"]) - delta
		if float(p["life"]) <= 0.0:
			particles.remove_at(i)
		else:
			p["pos"] = Vector2(p["pos"]) + Vector2(p["vel"]) * delta
			p["vel"] = Vector2(p["vel"]) * 0.92
		i -= 1


func _pp0_left_rect() -> Rect2:
	return Rect2(pp0_anchor_x - PP_OFFSET - PLAT_W * 0.5, pp0_left_y, PLAT_W, PLAT_H)

func _pp0_right_rect() -> Rect2:
	return Rect2(pp0_anchor_x + PP_OFFSET - PLAT_W * 0.5, pp0_right_y, PLAT_W, PLAT_H)

func _pp1_left_rect() -> Rect2:
	return Rect2(pp1_anchor_x - PP_OFFSET - PLAT_W * 0.5, pp1_left_y, PLAT_W, PLAT_H)

func _pp1_right_rect() -> Rect2:
	return Rect2(pp1_anchor_x + PP_OFFSET - PLAT_W * 0.5, pp1_right_y, PLAT_W, PLAT_H)

func _pp_left_rect(pair: int) -> Rect2:
	return _pp0_left_rect() if pair == 0 else _pp1_left_rect()

func _pp_right_rect(pair: int) -> Rect2:
	return _pp0_right_rect() if pair == 0 else _pp1_right_rect()

func _burden_rect() -> Rect2:
	return Rect2(BURDEN_PLAT_X, burden_plat_y, BURDEN_PLAT_W, PLAT_H)

func _point_on_rect(pos: Vector2, rect: Rect2, half_w: float, half_h: float) -> bool:
	return pos.x + half_w > rect.position.x and pos.x - half_w < rect.end.x \
		and pos.y + half_h > rect.position.y and pos.y - half_h < rect.end.y


func _draw() -> void:
	# Background handled by global ShardBackground autoload

	var plat_col  := Color(0.18, 0.18, 0.24)
	var plat_edge := Color(0.30, 0.30, 0.38, 0.6)
	for sp: Rect2 in static_platforms:
		draw_rect(sp, plat_col)
		draw_rect(sp, plat_edge, false, 1.5)

	_draw_pulley_pair(0)
	_draw_pulley_pair(1)

	var br: Rect2 = _burden_rect()
	var burden_glow: float = 0.12 + sin(pulse_time * 3.0) * 0.06
	var burden_base: Color = Color(0.25, 0.22, 0.35)
	if burden_both_on:
		burden_base = Color(0.4, 0.35, 0.55)
		burden_glow = 0.35
	draw_rect(br, burden_base)
	draw_rect(br, Color(0.7, 0.6, 1.0, burden_glow), false, 2.5)
	draw_string(ThemeDB.fallback_font, br.get_center() + Vector2(-30.0, -6.0),
		"stand together", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.6, 1.0, 0.5))

	var all_gems_done: bool = true
	for gem: Dictionary in gems:
		if not gem["collected"]:
			all_gems_done = false
			break
	var exit_alpha: float = 0.25 + sin(pulse_time * 2.5) * 0.1 if all_gems_done else 0.12
	draw_rect(EXIT_RECT, Color(0.35, 0.75, 0.45, exit_alpha))
	draw_rect(EXIT_RECT, Color(0.4, 0.9, 0.5, 0.4 if all_gems_done else 0.15), false, 2.0)
	draw_string(ThemeDB.fallback_font, EXIT_RECT.get_center() + Vector2(-20.0, -6.0),
		"exit", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.9, 0.55, 0.6 if all_gems_done else 0.2))

	for gate: Dictionary in gates:
		var gr: Rect2 = gate["rect"]
		if gate["open"]:
			draw_rect(gr, Color(0.3, 0.3, 0.4, 0.15))
			draw_rect(gr, Color(0.4, 0.8, 0.4, 0.3), false, 1.5)
		else:
			draw_rect(gr, Color(0.22, 0.18, 0.28))
			draw_rect(gr, Color(0.6, 0.4, 0.8, 0.5), false, 2.0)
			var gc: Vector2 = gr.get_center()
			draw_line(gc + Vector2(-4.0, -40.0), gc + Vector2(4.0, 40.0), Color(0.7, 0.5, 0.9, 0.25), 1.0)

	for lv: Dictionary in levers:
		var lpos: Vector2 = lv["pos"]
		var lheld: bool = lv["held"]
		var lc: Color = Color(0.8, 0.7, 0.2) if lheld else Color(0.45, 0.42, 0.5)
		draw_circle(lpos, LEVER_RADIUS, lc)
		var stick_end: Vector2 = lpos + Vector2(0.0, -22.0) if lheld else lpos + Vector2(12.0, -18.0)
		draw_line(lpos, stick_end, Color(0.6, 0.55, 0.35), 3.0)
		draw_string(ThemeDB.fallback_font, lpos + Vector2(-10.0, 22.0),
			"[F/Enter]", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.65, 0.4, 0.55))

	for gem: Dictionary in gems:
		if gem["collected"]:
			continue
		var gpos: Vector2 = gem["pos"]
		var gtype: String = gem["type"]
		var gc: Color = COLD_COLOR if gtype == "cold" else WARM_COLOR
		var gl: Color = COLD_LIGHT if gtype == "cold" else WARM_LIGHT
		var bob: float = sin(pulse_time * 2.2 + gpos.x * 0.05) * 4.0
		var gp: Vector2 = gpos + Vector2(0.0, bob)
		var pts: PackedVector2Array = PackedVector2Array([
			gp + Vector2(0.0, -GEM_RADIUS * 1.4),
			gp + Vector2(GEM_RADIUS, 0.0),
			gp + Vector2(0.0, GEM_RADIUS * 1.4),
			gp + Vector2(-GEM_RADIUS, 0.0),
		])
		draw_colored_polygon(pts, gc)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), gl, 1.5)

	for p: Dictionary in particles:
		var a: float = float(p["life"]) / float(p["max_life"])
		var pc: Color = Color(p["color"])
		pc.a = a
		draw_circle(Vector2(p["pos"]), 3.0, pc)

	if exit_overlap_timer > 0.0:
		var prog: float = exit_overlap_timer / EXIT_HOLD_TIME
		draw_arc(EXIT_RECT.get_center() + Vector2(0.0, -30.0), 18.0,
			-PI * 0.5, -PI * 0.5 + TAU * prog, 32, Color(0.5, 0.9, 0.55, 0.8), 3.0)

	var p1_col: Color = GameManager.get_blame_color()
	if p1_stagger > 0.0:
		p1_col = p1_col.lerp(Color(1.0, 0.3, 0.3), 0.6)
	draw_rect(Rect2(p1_pos - Vector2(20.0, 20.0), Vector2(40.0, 40.0)), p1_col)
	draw_rect(Rect2(p1_pos - Vector2(12.0, 12.0), Vector2(24.0, 24.0)), Color(GameManager.get_blame_color_light(), 0.3))

	var p2_col: Color = GameManager.get_denial_color()
	if p2_stagger > 0.0:
		p2_col = p2_col.lerp(Color(1.0, 0.3, 0.3), 0.6)
	draw_circle(p2_pos, 22.0, p2_col)
	draw_circle(p2_pos, 13.0, Color(GameManager.get_denial_color_light(), 0.3))

	var bar_w: float = (time_remaining / TIME_LIMIT) * 200.0
	var bar_col: Color = Color(0.5, 0.7, 0.5, 0.4)
	if time_remaining < 20.0:
		bar_col = Color(0.8, 0.3, 0.3, 0.5)
	draw_rect(Rect2(540.0, 18.0, bar_w, 8.0), bar_col)
	draw_rect(Rect2(540.0, 18.0, 200.0, 8.0), Color(0.3, 0.3, 0.35, 0.3), false, 1.0)

	var done: int = 0
	for gem: Dictionary in gems:
		if gem["collected"]: done += 1
	draw_string(ThemeDB.fallback_font, Vector2(610.0, 50.0),
		str(done) + "/" + str(gems.size()), HORIZONTAL_ALIGNMENT_CENTER, -1, 15,
		Color(0.7, 0.7, 0.85, 0.6))

	if flash_timer > 0.0:
		var fc: Color = flash_color
		fc.a *= flash_timer / 0.25
		draw_rect(Rect2(0.0, 0.0, 1280.0, 720.0), fc)


func _draw_pulley_pair(pair: int) -> void:
	var left_rect: Rect2 = _pp_left_rect(pair)
	var right_rect: Rect2 = _pp_right_rect(pair)
	var anchor_x: float = pp0_anchor_x if pair == 0 else pp1_anchor_x
	var anchor_y: float = (pp0_min_y - 30.0) if pair == 0 else (pp1_min_y - 30.0)
	var anchor: Vector2 = Vector2(anchor_x, anchor_y)

	draw_circle(anchor, 10.0, Color(0.3, 0.3, 0.38))
	draw_circle(anchor, 10.0, Color(0.45, 0.45, 0.55, 0.6), false, 1.5)

	var rope_col := Color(0.4, 0.38, 0.45, 0.7)
	draw_line(anchor, left_rect.get_center() + Vector2(0.0, -PLAT_H * 0.5), rope_col, 1.5)
	draw_line(anchor, right_rect.get_center() + Vector2(0.0, -PLAT_H * 0.5), rope_col, 1.5)

	var plat_col := Color(0.22, 0.22, 0.30)
	var plat_edge := Color(0.38, 0.38, 0.5, 0.7)
	draw_rect(left_rect, plat_col)
	draw_rect(left_rect, plat_edge, false, 2.0)
	draw_rect(right_rect, plat_col)
	draw_rect(right_rect, plat_edge, false, 2.0)


func _show_dialogue() -> void:
	var lines: Array[Dictionary] = [
		{"speaker": "Blame", "text": "We're still holding each other up. Even now.", "color": GameManager.get_blame_color_light()},
		{"speaker": "Denial", "text": "Maybe that's the only way we ever moved forward.", "color": GameManager.get_denial_color_light()},
	]
	dialogue.play_dialogue(lines)


func _on_dialogue_done() -> void:
	phase = 2
