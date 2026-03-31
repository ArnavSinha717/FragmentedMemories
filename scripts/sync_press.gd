extends Control

## Cooperative Minigame 2 — Walk Through the Fog Together (Expanded).
## Dark screen, shared light. GUILT sends projectiles from the shadows.
## Cold Shards (blue) = only Denial blocks. Warm Embers (orange) = only Blame blocks.
## Shadow Orbs = both must be near. Guilt Walls = both stand near to dissolve.
## Memory Wisps = both touch for a burst of light. Path splits at forks.
## Players start separated by a maze and must navigate to a merge point.

@onready var dialogue: Node = $DialogueSystem

# --- Player ---
var p1_pos := Vector2(100, 100)
var p2_pos := Vector2(100, 600)
const PLAYER_SPEED := 180.0
const SLOW_SPEED_MULT := 0.6

# --- Light ---
const LIGHT_RADIUS_SOLO := 120.0
const LIGHT_RADIUS_COMBINED := 220.0
const CLOSE_DIST := 150.0
const FAR_DIST := 250.0

# --- Path ---
var waypoints: Array[Dictionary] = []
# Each waypoint: {pos, color_hint} — color_hint: 0=neutral, 1=cold(blame fork), 2=warm(denial fork)

# --- Maze ---
var maze_walls: Array[Rect2] = []

# --- Projectiles ---
var projectiles: Array[Dictionary] = []
# {pos, vel, type, radius, alive}
# type: 0=cold_shard, 1=warm_ember, 2=shadow_orb
const PROJECTILE_SPEED := 120.0
const BLOCK_RANGE := 55.0
const SHADOW_ORB_DISSOLVE_DIST := 70.0
var projectile_timer := 0.0

# --- Guilt Walls ---
var guilt_walls: Array[Dictionary] = []
# {pos, width, height, hp, max_hp, active}
const WALL_DISSOLVE_RANGE := 80.0

# --- Memory Wisps ---
var wisps: Array[Dictionary] = []
# {pos, collected, orbit_center, orbit_radius, orbit_speed, orbit_offset}
const WISP_COLLECT_RANGE := 50.0
var wisp_flash_timer := 0.0
var wisp_flash_pos := Vector2.ZERO

# --- Hazards (original dark shapes, kept) ---
var hazards: Array[Dictionary] = []

# --- State ---
var phase: int = -1  # -1=instructions, 0=playing, 1=guilt_flash, 2=reveal_anim, 3=dialogue, 4=done
var time_elapsed := 0.0
var reveal_progress := 0.0
var dim_timer_p1 := 0.0
var dim_timer_p2 := 0.0
var pulse_time := 0.0
var p1_at_goal := false
var p2_at_goal := false
var guilt_flash_timer := 0.0  # GUILT appears briefly at the end
var game_phase := 0  # 0=gentle, 1=projectiles, 2=intense
var goal_pos := Vector2(1180, 360)
const GOAL_RADIUS := 80.0

# --- Block feedback ---
var block_flash_p1 := 0.0
var block_flash_p2 := 0.0
var block_flash_pos_p1 := Vector2.ZERO
var block_flash_pos_p2 := Vector2.ZERO


func _ready() -> void:
	dialogue.dialogue_finished.connect(_on_dialogue_done)
	_build_path()
	_build_obstacles()
	goal_pos = waypoints[waypoints.size() - 1].pos


func _build_path() -> void:
	waypoints.clear()
	maze_walls.clear()

	# --- Maze walls (left third, x=0 to x=450) ---
	# These form two separate corridors: top-left for P1, bottom-left for P2,
	# merging around x=400-450.

	# Main horizontal divider splitting top and bottom halves
	maze_walls.append(Rect2(50, 340, 300, 20))

	# Top half walls (P1's corridor from top-left heading right)
	maze_walls.append(Rect2(160, 40, 20, 140))     # vertical wall forcing P1 down
	maze_walls.append(Rect2(160, 180, 120, 20))     # horizontal shelf
	maze_walls.append(Rect2(260, 100, 20, 100))     # vertical creating a turn
	maze_walls.append(Rect2(260, 100, 100, 20))     # top horizontal
	maze_walls.append(Rect2(340, 100, 20, 120))     # vertical dead-end wall
	maze_walls.append(Rect2(200, 260, 130, 20))     # lower shelf in top half
	maze_walls.append(Rect2(360, 200, 20, 160))     # vertical near merge, top side

	# Bottom half walls (P2's corridor from bottom-left heading right)
	maze_walls.append(Rect2(120, 480, 20, 140))     # vertical forcing P2 up
	maze_walls.append(Rect2(120, 480, 140, 20))     # horizontal shelf
	maze_walls.append(Rect2(240, 420, 20, 80))      # vertical creating a turn
	maze_walls.append(Rect2(240, 560, 120, 20))     # lower horizontal
	maze_walls.append(Rect2(340, 460, 20, 120))     # vertical dead-end wall
	maze_walls.append(Rect2(180, 620, 150, 20))     # bottom shelf
	maze_walls.append(Rect2(360, 400, 20, 80))      # vertical near merge, bottom side

	# Merge area walls — funnel both paths to a single opening around x=400-450
	maze_walls.append(Rect2(400, 200, 50, 20))      # narrowing top
	maze_walls.append(Rect2(400, 500, 50, 20))      # narrowing bottom
	# Opening between y=340 and y=400 allows both players through

	# --- Waypoints from merge point onward ---
	var path_points: Array[Dictionary] = [
		{"pos": Vector2(450, 370), "color_hint": 0},  # merge point
		{"pos": Vector2(520, 320), "color_hint": 0},
		{"pos": Vector2(580, 400), "color_hint": 0},
		# Fork 1 — paths split
		{"pos": Vector2(640, 350), "color_hint": 0},  # convergence before split
		{"pos": Vector2(680, 260), "color_hint": 1},  # cold fork (blame takes this)
		{"pos": Vector2(680, 460), "color_hint": 2},  # warm fork (denial takes this)
		{"pos": Vector2(740, 220), "color_hint": 1},
		{"pos": Vector2(740, 500), "color_hint": 2},
		{"pos": Vector2(800, 360), "color_hint": 0},  # rejoin
		# Phase 2 — projectiles begin
		{"pos": Vector2(860, 300), "color_hint": 0},
		{"pos": Vector2(920, 400), "color_hint": 0},
		# Fork 2
		{"pos": Vector2(970, 350), "color_hint": 0},
		{"pos": Vector2(1010, 240), "color_hint": 1},
		{"pos": Vector2(1010, 470), "color_hint": 2},
		{"pos": Vector2(1060, 200), "color_hint": 1},
		{"pos": Vector2(1060, 510), "color_hint": 2},
		{"pos": Vector2(1100, 360), "color_hint": 0},  # rejoin
		# Phase 3 — intense final stretch
		{"pos": Vector2(1140, 300), "color_hint": 0},
		{"pos": Vector2(1160, 400), "color_hint": 0},
		{"pos": Vector2(1180, 360), "color_hint": 0},  # goal
	]
	waypoints = path_points


func _build_obstacles() -> void:
	# Guilt Walls — block the path, need both players to dissolve (5 total)
	guilt_walls = [
		{"pos": Vector2(300, 200), "width": 50.0, "height": 90.0, "hp": 2.0, "max_hp": 2.0, "active": true},
		{"pos": Vector2(300, 520), "width": 50.0, "height": 90.0, "hp": 2.0, "max_hp": 2.0, "active": true},
		{"pos": Vector2(570, 370), "width": 60.0, "height": 100.0, "hp": 2.5, "max_hp": 2.5, "active": true},
		{"pos": Vector2(860, 340), "width": 55.0, "height": 110.0, "hp": 2.0, "max_hp": 2.0, "active": true},
		{"pos": Vector2(1110, 350), "width": 70.0, "height": 120.0, "hp": 1.8, "max_hp": 1.8, "active": true},
	]

	# Memory Wisps — golden collectibles
	wisps = [
		{"pos": Vector2(460, 360), "collected": false, "orbit_center": Vector2(460, 360), "orbit_radius": 25.0, "orbit_speed": 1.2, "orbit_offset": 0.0},
		{"pos": Vector2(800, 360), "collected": false, "orbit_center": Vector2(800, 360), "orbit_radius": 20.0, "orbit_speed": 0.9, "orbit_offset": 1.5},
		{"pos": Vector2(970, 320), "collected": false, "orbit_center": Vector2(970, 320), "orbit_radius": 22.0, "orbit_speed": 1.1, "orbit_offset": 3.0},
		{"pos": Vector2(1160, 380), "collected": false, "orbit_center": Vector2(1160, 380), "orbit_radius": 18.0, "orbit_speed": 1.4, "orbit_offset": 4.5},
	]

	# Drifting hazards (dark shapes) — 10 total, spread evenly
	hazards = [
		_make_hazard(Vector2(200, 150), 0.5, 30.0),
		_make_hazard(Vector2(250, 550), 0.45, 28.0),
		_make_hazard(Vector2(420, 300), 0.55, 32.0),
		_make_hazard(Vector2(500, 450), 0.6, 35.0),
		_make_hazard(Vector2(650, 310), 0.5, 30.0),
		_make_hazard(Vector2(750, 480), 0.4, 28.0),
		_make_hazard(Vector2(880, 240), 0.55, 32.0),
		_make_hazard(Vector2(950, 450), 0.45, 30.0),
		_make_hazard(Vector2(1050, 280), 0.5, 25.0),
		_make_hazard(Vector2(1150, 440), 0.6, 30.0),
	]


func _make_hazard(pos: Vector2, spd: float, rad: float) -> Dictionary:
	return {
		"pos": pos, "base_pos": pos,
		"drift_offset": randf() * TAU, "drift_speed": spd,
		"drift_radius": rad, "pulse_offset": randf() * TAU,
	}


func _process(delta: float) -> void:
	time_elapsed += delta
	pulse_time += delta
	dim_timer_p1 = maxf(0.0, dim_timer_p1 - delta)
	dim_timer_p2 = maxf(0.0, dim_timer_p2 - delta)
	block_flash_p1 = maxf(0.0, block_flash_p1 - delta * 4.0)
	block_flash_p2 = maxf(0.0, block_flash_p2 - delta * 4.0)
	wisp_flash_timer = maxf(0.0, wisp_flash_timer - delta * 2.0)

	match phase:
		-1:
			if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("p1_attack") or Input.is_action_just_pressed("p2_attack"):
				phase = 0
			queue_redraw()
			return
		0:
			_update_game_phase()
			_update_players(delta)
			_update_hazards()
			_update_projectiles(delta)
			_update_guilt_walls(delta)
			_update_wisps()
			_check_hazard_collisions()
			_check_projectile_collisions()
			_check_block_input()
			_check_wisp_collection()
			_check_goal()
		1:  # GUILT flash at the end
			guilt_flash_timer += delta
			if guilt_flash_timer > 3.0:
				phase = 2
				reveal_progress = 0.0
		2:  # Reveal
			reveal_progress = minf(reveal_progress + delta * 0.6, 1.0)
			if reveal_progress >= 1.0:
				phase = 3
				_show_dialogue()
		3: pass
		4: GameManager.advance_phase()

	queue_redraw()


func _update_game_phase() -> void:
	# Determine escalation based on player progress (average X position)
	var avg_x: float = (p1_pos.x + p2_pos.x) * 0.5
	if avg_x < 300:
		game_phase = 0  # Gentle
	elif avg_x < 700:
		game_phase = 1  # Projectiles start
	else:
		game_phase = 2  # Intense


func _update_players(delta: float) -> void:
	var dist: float = p1_pos.distance_to(p2_pos)
	var speed_mult := 1.0
	if dist > FAR_DIST:
		speed_mult = SLOW_SPEED_MULT
	elif dist > CLOSE_DIST:
		speed_mult = lerpf(1.0, SLOW_SPEED_MULT, (dist - CLOSE_DIST) / (FAR_DIST - CLOSE_DIST))

	var speed: float = PLAYER_SPEED * speed_mult * delta

	var p1_dir := Vector2.ZERO
	if Input.is_action_pressed("p1_up"): p1_dir.y -= 1.0
	if Input.is_action_pressed("p1_down"): p1_dir.y += 1.0
	if Input.is_action_pressed("p1_left"): p1_dir.x -= 1.0
	if Input.is_action_pressed("p1_right"): p1_dir.x += 1.0
	if p1_dir.length() > 0.0:
		p1_pos += p1_dir.normalized() * speed
	p1_pos.x = clampf(p1_pos.x, 20.0, 1260.0)
	p1_pos.y = clampf(p1_pos.y, 20.0, 700.0)
	p1_pos = _push_out_of_maze(p1_pos)

	var p2_dir := Vector2.ZERO
	if Input.is_action_pressed("p2_up"): p2_dir.y -= 1.0
	if Input.is_action_pressed("p2_down"): p2_dir.y += 1.0
	if Input.is_action_pressed("p2_left"): p2_dir.x -= 1.0
	if Input.is_action_pressed("p2_right"): p2_dir.x += 1.0
	if p2_dir.length() > 0.0:
		p2_pos += p2_dir.normalized() * speed
	p2_pos.x = clampf(p2_pos.x, 20.0, 1260.0)
	p2_pos.y = clampf(p2_pos.y, 20.0, 700.0)
	p2_pos = _push_out_of_maze(p2_pos)

	# Collision with active guilt walls
	for wall: Dictionary in guilt_walls:
		if not (wall.active as bool):
			continue
		var wr := Rect2(
			(wall.pos as Vector2).x - (wall.width as float) * 0.5,
			(wall.pos as Vector2).y - (wall.height as float) * 0.5,
			wall.width as float, wall.height as float
		)
		if wr.has_point(p1_pos):
			var push: Vector2 = (p1_pos - (wall.pos as Vector2)).normalized() * 5.0
			p1_pos += push
		if wr.has_point(p2_pos):
			var push: Vector2 = (p2_pos - (wall.pos as Vector2)).normalized() * 5.0
			p2_pos += push



func _push_out_of_maze(pos: Vector2) -> Vector2:
	# Push a point out of all maze walls, returning the corrected position.
	for wall: Rect2 in maze_walls:
		if wall.has_point(pos):
			# Find nearest edge to push to
			var left_dist: float = absf(pos.x - wall.position.x)
			var right_dist: float = absf(pos.x - (wall.position.x + wall.size.x))
			var top_dist: float = absf(pos.y - wall.position.y)
			var bottom_dist: float = absf(pos.y - (wall.position.y + wall.size.y))

			var min_dist: float = minf(minf(left_dist, right_dist), minf(top_dist, bottom_dist))

			if min_dist == left_dist:
				pos.x = wall.position.x - 1.0
			elif min_dist == right_dist:
				pos.x = wall.position.x + wall.size.x + 1.0
			elif min_dist == top_dist:
				pos.y = wall.position.y - 1.0
			else:
				pos.y = wall.position.y + wall.size.y + 1.0
	return pos


func _update_hazards() -> void:
	for h: Dictionary in hazards:
		var bp: Vector2 = h.base_pos
		var off: float = h.drift_offset
		var spd: float = h.drift_speed
		var rad: float = h.drift_radius
		h.pos = bp + Vector2(
			cos(time_elapsed * spd + off) * rad,
			sin(time_elapsed * spd * 0.7 + off + 1.0) * rad
		)


func _update_projectiles(delta: float) -> void:
	# Phase 0: gentle — spawn slowly, only cold/warm shards
	# Phase 1: mid — spawn at medium rate, all types
	# Phase 2: intense — fast spawns, faster projectiles
	var spawn_interval: float
	match game_phase:
		0: spawn_interval = 3.0
		1: spawn_interval = 1.5
		_: spawn_interval = 0.8

	projectile_timer -= delta
	if projectile_timer <= 0:
		projectile_timer = spawn_interval + randf_range(-0.3, 0.4)
		_spawn_projectile()

	# Move projectiles
	for i in range(projectiles.size() - 1, -1, -1):
		var p: Dictionary = projectiles[i]
		if not (p.alive as bool):
			projectiles.remove_at(i)
			continue
		p.pos = (p.pos as Vector2) + (p.vel as Vector2) * delta
		# Remove if off screen
		var pp: Vector2 = p.pos
		if pp.x < -50 or pp.x > 1330 or pp.y < -50 or pp.y > 770:
			projectiles.remove_at(i)

	# Shadow orbs: check if both players are near
	for p: Dictionary in projectiles:
		if (p.type as int) == 2 and (p.alive as bool):
			var pp: Vector2 = p.pos
			if p1_pos.distance_to(pp) < SHADOW_ORB_DISSOLVE_DIST and p2_pos.distance_to(pp) < SHADOW_ORB_DISSOLVE_DIST:
				p.alive = false
				wisp_flash_timer = 1.0
				wisp_flash_pos = pp


func _spawn_projectile() -> void:
	# Choose type based on game phase
	var proj_type: int
	if game_phase == 0:
		proj_type = randi() % 2  # cold or warm only
	elif game_phase == 1:
		var roll: float = randf()
		if roll < 0.35:
			proj_type = 0  # cold shard
		elif roll < 0.7:
			proj_type = 1  # warm ember
		else:
			proj_type = 2  # shadow orb
	else:
		var roll: float = randf()
		if roll < 0.35:
			proj_type = 0
		elif roll < 0.7:
			proj_type = 1
		else:
			proj_type = 2

	# Spawn from screen edges, aimed toward the path/players
	var target: Vector2 = (p1_pos + p2_pos) * 0.5 + Vector2(randf_range(-80, 80), randf_range(-80, 80))
	var spawn_pos: Vector2
	var side: int = randi() % 4
	match side:
		0: spawn_pos = Vector2(randf_range(0, 1280), -30)      # top
		1: spawn_pos = Vector2(randf_range(0, 1280), 750)      # bottom
		2: spawn_pos = Vector2(-30, randf_range(0, 720))        # left
		3: spawn_pos = Vector2(1310, randf_range(0, 720))       # right

	var speed_mult: float = 1.0
	if game_phase == 2:
		speed_mult = 1.4

	var vel: Vector2 = (target - spawn_pos).normalized() * PROJECTILE_SPEED * speed_mult
	# Shadow orbs move slower
	if proj_type == 2:
		vel *= 0.6

	var rad: float = 12.0 if proj_type != 2 else 18.0

	projectiles.append({
		"pos": spawn_pos, "vel": vel, "type": proj_type,
		"radius": rad, "alive": true
	})


func _check_projectile_collisions() -> void:
	for p: Dictionary in projectiles:
		if not (p.alive as bool):
			continue
		var pp: Vector2 = p.pos
		var pt: int = p.type
		var hit_range: float = (p.radius as float) + 16.0

		# Hit P1?
		if p1_pos.distance_to(pp) < hit_range:
			p.alive = false
			dim_timer_p1 = 2.0
			var push_dir: Vector2 = (p1_pos - pp).normalized()
			p1_pos += push_dir * 60.0
			p1_pos.x = clampf(p1_pos.x, 20.0, 1260.0)
			p1_pos.y = clampf(p1_pos.y, 20.0, 700.0)

		# Hit P2?
		if p2_pos.distance_to(pp) < hit_range:
			p.alive = false
			dim_timer_p2 = 2.0
			var push_dir: Vector2 = (p2_pos - pp).normalized()
			p2_pos += push_dir * 60.0
			p2_pos.x = clampf(p2_pos.x, 20.0, 1260.0)
			p2_pos.y = clampf(p2_pos.y, 20.0, 700.0)


func _check_block_input() -> void:
	# Blame (P1) blocks warm embers with attack
	if Input.is_action_just_pressed("p1_attack"):
		for p: Dictionary in projectiles:
			if not (p.alive as bool):
				continue
			if (p.type as int) == 1:  # warm ember
				if p1_pos.distance_to(p.pos as Vector2) < BLOCK_RANGE:
					p.alive = false
					block_flash_p1 = 1.0
					block_flash_pos_p1 = p.pos
					break

	# Denial (P2) blocks cold shards with attack
	if Input.is_action_just_pressed("p2_attack"):
		for p: Dictionary in projectiles:
			if not (p.alive as bool):
				continue
			if (p.type as int) == 0:  # cold shard
				if p2_pos.distance_to(p.pos as Vector2) < BLOCK_RANGE:
					p.alive = false
					block_flash_p2 = 1.0
					block_flash_pos_p2 = p.pos
					break


func _update_guilt_walls(delta: float) -> void:
	for wall: Dictionary in guilt_walls:
		if not (wall.active as bool):
			continue
		var wp: Vector2 = wall.pos
		var both_near: bool = p1_pos.distance_to(wp) < WALL_DISSOLVE_RANGE and p2_pos.distance_to(wp) < WALL_DISSOLVE_RANGE
		if both_near:
			wall.hp = (wall.hp as float) - delta
			if (wall.hp as float) <= 0:
				wall.active = false


func _update_wisps() -> void:
	for w: Dictionary in wisps:
		if w.collected as bool:
			continue
		var oc: Vector2 = w.orbit_center
		var orad: float = w.orbit_radius
		var ospd: float = w.orbit_speed
		var ooff: float = w.orbit_offset
		w.pos = oc + Vector2(cos(time_elapsed * ospd + ooff), sin(time_elapsed * ospd * 0.8 + ooff)) * orad


func _check_wisp_collection() -> void:
	for w: Dictionary in wisps:
		if w.collected as bool:
			continue
		var wp: Vector2 = w.pos
		if p1_pos.distance_to(wp) < WISP_COLLECT_RANGE and p2_pos.distance_to(wp) < WISP_COLLECT_RANGE:
			w.collected = true
			wisp_flash_timer = 1.5
			wisp_flash_pos = wp


func _check_hazard_collisions() -> void:
	for h: Dictionary in hazards:
		var hp: Vector2 = h.pos
		if p1_pos.distance_to(hp) < 42.0:
			var push_dir: Vector2 = (p1_pos - hp).normalized()
			p1_pos += push_dir * 100.0
			p1_pos.x = clampf(p1_pos.x, 20.0, 1260.0)
			p1_pos.y = clampf(p1_pos.y, 20.0, 700.0)
			dim_timer_p1 = 1.2
		if p2_pos.distance_to(hp) < 42.0:
			var push_dir: Vector2 = (p2_pos - hp).normalized()
			p2_pos += push_dir * 100.0
			p2_pos.x = clampf(p2_pos.x, 20.0, 1260.0)
			p2_pos.y = clampf(p2_pos.y, 20.0, 700.0)
			dim_timer_p2 = 1.2


func _check_goal() -> void:
	p1_at_goal = p1_pos.distance_to(goal_pos) < GOAL_RADIUS
	p2_at_goal = p2_pos.distance_to(goal_pos) < GOAL_RADIUS
	if p1_at_goal and p2_at_goal:
		phase = 1  # GUILT flash first
		guilt_flash_timer = 0.0


func _get_visibility(world_pos: Vector2) -> float:
	var dist_p1: float = world_pos.distance_to(p1_pos)
	var dist_p2: float = world_pos.distance_to(p2_pos)
	var player_dist: float = p1_pos.distance_to(p2_pos)

	var r1: float = LIGHT_RADIUS_SOLO
	var r2: float = LIGHT_RADIUS_SOLO
	if player_dist < CLOSE_DIST:
		var closeness: float = 1.0 - (player_dist / CLOSE_DIST)
		r1 = lerpf(LIGHT_RADIUS_SOLO, LIGHT_RADIUS_COMBINED, closeness)
		r2 = r1
	if dim_timer_p1 > 0.0: r1 *= 0.5
	if dim_timer_p2 > 0.0: r2 *= 0.5

	# Wisp flash boosts visibility everywhere briefly
	var wisp_bonus: float = 0.0
	if wisp_flash_timer > 0.0:
		var flash_dist: float = world_pos.distance_to(wisp_flash_pos)
		var flash_radius: float = 350.0 * wisp_flash_timer
		if flash_dist < flash_radius:
			wisp_bonus = (1.0 - flash_dist / flash_radius) * wisp_flash_timer * 0.6

	var vis1 := 0.0
	if dist_p1 < r1:
		vis1 = (1.0 - dist_p1 / r1)
		vis1 *= vis1
	var vis2 := 0.0
	if dist_p2 < r2:
		vis2 = (1.0 - dist_p2 / r2)
		vis2 *= vis2

	return minf(vis1 + vis2 + wisp_bonus, 1.0)


# === DRAWING ===

func _draw() -> void:
	if phase == -1:
		_draw_instructions()
		return
	if phase == 1:
		_draw_guilt_flash()
		return
	if phase >= 2:
		_draw_revealed()
		return

	_draw_path_markers()
	_draw_maze_walls()
	_draw_guilt_walls()
	_draw_wisps()
	_draw_hazards()
	_draw_projectiles()
	_draw_goal()
	_draw_players()
	_draw_player_glow()
	_draw_block_flashes()
	_draw_separation_indicator()
	_draw_wisp_flash()
	_draw_phase_indicator()


func _draw_instructions() -> void:
	var font := ThemeDB.fallback_font
	var ca: float = 0.65 + sin(pulse_time * 3.0) * 0.12
	var cc := Color(0.65, 0.65, 0.75, ca)
	var hl := Color(0.5, 0.5, 0.65, ca * 0.6)
	# Title
	draw_string(font, Vector2(450, 120), "INTO THE FOG", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(0.7, 0.7, 0.85, ca))
	draw_string(font, Vector2(470, 150), "Find each other. Escape together.", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.55, 0.55, 0.65, ca * 0.7))
	# P1
	draw_string(font, Vector2(80, 220), "BLAME", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(GameManager.get_blame_color_light(), ca))
	draw_line(Vector2(80, 227), Vector2(230, 227), Color(GameManager.get_blame_color(), ca * 0.3), 1.0)
	draw_string(font, Vector2(80, 250), "Move: WASD / Stick", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, hl)
	draw_string(font, Vector2(80, 270), "F / X : Block warm embers", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, cc)
	# P2
	draw_string(font, Vector2(740, 220), "DENIAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(GameManager.get_denial_color_light(), ca))
	draw_line(Vector2(740, 227), Vector2(900, 227), Color(GameManager.get_denial_color(), ca * 0.3), 1.0)
	draw_string(font, Vector2(740, 250), "Move: Arrows / Stick", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, hl)
	draw_string(font, Vector2(740, 270), "Enter / X : Block cold shards", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, cc)
	# Shared tips
	draw_string(font, Vector2(330, 360), "Stay close for a bigger shared light", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 0.6, 0.7, ca * 0.8))
	draw_string(font, Vector2(330, 385), "Stand near guilt walls to dissolve them", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 0.6, 0.7, ca * 0.8))
	draw_string(font, Vector2(330, 410), "Touch memory wisps together for light", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 0.6, 0.7, ca * 0.8))
	# Start prompt
	var ct_a: float = 0.5 + sin(pulse_time * 2.0) * 0.2
	draw_string(font, Vector2(440, 500), "Press SPACE / X to Start", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.8, 0.8, 0.9, ct_a))


func _draw_guilt_flash() -> void:
	# GUILT appears as a massive dark shape before vanishing
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.02, 0.02, 0.03))

	var t: float = guilt_flash_timer
	var appear: float = clampf(t / 1.0, 0.0, 1.0)  # fade in over 1s
	var fade: float = clampf((t - 2.0) / 1.0, 0.0, 1.0)  # fade out 2-3s
	var alpha: float = appear * (1.0 - fade)

	var center := Vector2(640, 360)
	# Massive dark body
	draw_circle(center, 150.0 * alpha, Color(0.06, 0.04, 0.08, alpha * 0.85))
	draw_circle(center, 100.0 * alpha, Color(0.08, 0.05, 0.1, alpha * 0.6))
	# Tendrils
	for i in range(8):
		var angle: float = (float(i) / 8.0) * TAU + t * 0.2
		var length: float = (180.0 + sin(t * 1.5 + float(i)) * 40.0) * alpha
		var end_pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * length
		draw_line(center, end_pos, Color(0.12, 0.06, 0.15, alpha * 0.5), 4.0)
	# Eyes
	draw_circle(center + Vector2(-30, -15), 14.0 * alpha, Color(0.5, 0.1, 0.12, alpha * 0.8))
	draw_circle(center + Vector2(30, -15), 14.0 * alpha, Color(0.5, 0.1, 0.12, alpha * 0.8))
	draw_circle(center + Vector2(-30, -15), 6.0 * alpha, Color(0.8, 0.2, 0.2, alpha))
	draw_circle(center + Vector2(30, -15), 6.0 * alpha, Color(0.8, 0.2, 0.2, alpha))

	# Players visible, watching
	_draw_players()

	# Text
	if t > 1.0 and t < 2.5:
		var text_alpha: float = minf((t - 1.0) / 0.5, 1.0) * (1.0 - clampf((t - 2.0) / 0.5, 0.0, 1.0))
		var font := ThemeDB.fallback_font
		var txt := "It was always there..."
		var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(font, Vector2(640 - tw * 0.5, 580), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.5, 0.3, 0.35, text_alpha))


func _draw_revealed() -> void:
	var t: float = reveal_progress
	var warm := Color(0.95, 0.65, 0.5, t * 0.15)
	var cool := Color(0.35, 0.4, 0.65, t * 0.15)
	draw_rect(Rect2(0, 0, 640, 720), cool)
	draw_rect(Rect2(640, 0, 640, 720), warm)

	for wp: Dictionary in waypoints:
		draw_circle(wp.pos as Vector2, 5.0, Color(0.7, 0.7, 0.6, 0.5 + t * 0.5))

	var goal_col := Color(1.0, 0.9, 0.7, 0.5 + t * 0.5)
	draw_circle(goal_pos, 30.0 + t * 15.0, goal_col)

	_draw_players()

	var center: Vector2 = (p1_pos + p2_pos) * 0.5
	var ring_r: float = t * 600.0
	draw_arc(center, ring_r, 0, TAU, 48, Color(1.0, 0.95, 0.85, (1.0 - t) * 0.3), 3.0)


func _draw_path_markers() -> void:
	for wp: Dictionary in waypoints:
		var pos: Vector2 = wp.pos
		var hint: int = wp.color_hint
		var vis: float = _get_visibility(pos)
		var base_alpha := 0.05
		var lit_alpha: float = lerpf(base_alpha, 0.7, vis)

		var col: Color
		match hint:
			1: col = Color(0.35, 0.45, 0.8, lit_alpha)   # cold/blame fork
			2: col = Color(0.9, 0.55, 0.4, lit_alpha)     # warm/denial fork
			_: col = Color(0.6, 0.6, 0.5, lit_alpha)       # neutral

		draw_circle(pos, 4.0, col)
		if vis > 0.1:
			draw_arc(pos, 8.0, 0, TAU, 12, Color(col.r, col.g, col.b, vis * 0.25), 1.0)


func _draw_maze_walls() -> void:
	for wall: Rect2 in maze_walls:
		var vis: float = _get_visibility(wall.get_center())
		if vis > 0.05:
			# Dark wall body
			draw_rect(wall, Color(0.15, 0.12, 0.18, vis * 0.9))
			# Top edge highlight
			draw_line(wall.position, wall.position + Vector2(wall.size.x, 0), Color(0.25, 0.2, 0.3, vis * 0.5), 1.5)
			# Bottom edge shadow
			draw_line(
				wall.position + Vector2(0, wall.size.y),
				wall.position + Vector2(wall.size.x, wall.size.y),
				Color(0.08, 0.06, 0.1, vis * 0.4), 1.0
			)


func _draw_guilt_walls() -> void:
	for wall: Dictionary in guilt_walls:
		if not (wall.active as bool):
			continue
		var wp: Vector2 = wall.pos
		var vis: float = _get_visibility(wp)
		var w: float = wall.width
		var h: float = wall.height
		var hp_ratio: float = (wall.hp as float) / (wall.max_hp as float)
		var alpha: float = lerpf(0.03, 0.7, vis) * hp_ratio

		# Dark barrier
		draw_rect(Rect2(wp.x - w * 0.5, wp.y - h * 0.5, w, h), Color(0.08, 0.05, 0.1, alpha))
		draw_rect(Rect2(wp.x - w * 0.5, wp.y - h * 0.5, w, h), Color(0.2, 0.12, 0.2, alpha * 0.6), false, 2.0)

		# Dissolve indicator when both near
		var both_near: bool = p1_pos.distance_to(wp) < WALL_DISSOLVE_RANGE and p2_pos.distance_to(wp) < WALL_DISSOLVE_RANGE
		if both_near and vis > 0.1:
			var pulse: float = sin(pulse_time * 4.0) * 0.2 + 0.5
			draw_rect(Rect2(wp.x - w * 0.5 - 3, wp.y - h * 0.5 - 3, w + 6, h + 6),
				Color(0.6, 0.5, 0.4, pulse * vis), false, 2.0)


func _draw_wisps() -> void:
	for w: Dictionary in wisps:
		if w.collected as bool:
			continue
		var wp: Vector2 = w.pos
		var vis: float = _get_visibility(wp)
		var glow: float = sin(pulse_time * 2.0 + (w.orbit_offset as float)) * 0.2 + 0.6
		var alpha: float = lerpf(0.04, glow, vis)
		# Golden shape
		draw_circle(wp, 8.0, Color(1.0, 0.9, 0.5, alpha))
		draw_circle(wp, 4.0, Color(1.0, 0.95, 0.75, alpha * 1.2))
		if vis > 0.15:
			draw_arc(wp, 12.0, 0, TAU, 16, Color(1.0, 0.85, 0.5, vis * 0.2), 1.0)


func _draw_hazards() -> void:
	for h: Dictionary in hazards:
		var hp: Vector2 = h.pos
		var vis: float = _get_visibility(hp)
		var pulse: float = (sin(pulse_time * 2.5 + (h.pulse_offset as float)) + 1.0) * 0.5
		var alpha: float = lerpf(0.04, 0.6 + pulse * 0.3, vis)
		var sz: float = 28.0 + pulse * 6.0
		var pts := PackedVector2Array([
			hp + Vector2(0, -sz), hp + Vector2(sz * 0.9, sz * 0.6), hp + Vector2(-sz * 0.9, sz * 0.6)
		])
		draw_colored_polygon(pts, Color(0.5, 0.15, 0.2, alpha))
		if vis > 0.15:
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]),
				Color(0.7, 0.2, 0.25, vis * 0.4), 1.5)


func _draw_projectiles() -> void:
	for p: Dictionary in projectiles:
		if not (p.alive as bool):
			continue
		var pp: Vector2 = p.pos
		var vis: float = _get_visibility(pp)
		var alpha: float = lerpf(0.08, 0.9, vis)
		var r: float = p.radius
		var pt: int = p.type

		match pt:
			0:  # Cold shard — blue triangle
				var tri := PackedVector2Array([
					pp + Vector2(0, -r), pp + Vector2(r * 0.8, r * 0.5), pp + Vector2(-r * 0.8, r * 0.5)
				])
				draw_colored_polygon(tri, Color(0.3, 0.4, 0.85, alpha))
				if vis > 0.1:
					draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]),
						Color(0.5, 0.6, 1.0, vis * 0.5), 1.0)
			1:  # Warm ember — orange circle
				draw_circle(pp, r, Color(0.95, 0.5, 0.25, alpha))
				draw_circle(pp, r * 0.5, Color(1.0, 0.75, 0.4, alpha * 0.6))
			2:  # Shadow orb — dark purple, larger
				draw_circle(pp, r, Color(0.25, 0.1, 0.3, alpha))
				draw_circle(pp, r * 0.6, Color(0.35, 0.15, 0.4, alpha * 0.5))
				# Faint tendrils
				for i in range(4):
					var angle: float = (float(i) / 4.0) * TAU + pulse_time * 0.5
					var tend_end: Vector2 = pp + Vector2(cos(angle), sin(angle)) * r * 1.5
					draw_line(pp, tend_end, Color(0.3, 0.12, 0.35, alpha * 0.3), 1.5)


func _draw_goal() -> void:
	var vis: float = _get_visibility(goal_pos)
	var pulse: float = (sin(pulse_time * 1.5) + 1.0) * 0.5
	var alpha: float = lerpf(0.08, 0.9, vis)
	draw_circle(goal_pos, 20.0 + pulse * 5.0, Color(1.0, 0.85, 0.6, alpha * (0.6 + pulse * 0.4)))
	draw_arc(goal_pos, 30.0 + pulse * 8.0, 0, TAU, 24, Color(1.0, 0.9, 0.7, alpha * 0.4), 2.0)
	if vis > 0.2:
		draw_arc(goal_pos, 45.0 + pulse * 10.0, 0, TAU, 24, Color(1.0, 0.9, 0.7, vis * 0.15), 1.0)


func _draw_players() -> void:
	var dist: float = p1_pos.distance_to(p2_pos)
	var closeness: float = 1.0 - clampf((dist - CLOSE_DIST) / (FAR_DIST - CLOSE_DIST), 0.0, 1.0)

	var p1_bright: float = 0.6 + closeness * 0.4
	if dim_timer_p1 > 0.0: p1_bright *= 0.4
	var g_frame: int = GameManager.anim_frame(pulse_time, 4, 6.0)
	GameManager.draw_blame_sprite(self, p1_pos + Vector2(0, 12), g_frame, 5, 0.7, false, Color(1, 1, 1, p1_bright))

	var p2_bright: float = 0.6 + closeness * 0.4
	if dim_timer_p2 > 0.0: p2_bright *= 0.4
	var r_frame: int = GameManager.anim_frame(pulse_time, 2, 3.0)
	GameManager.draw_denial_sprite(self, p2_pos + Vector2(0, 14), r_frame, 0, 1.1, false, Color(1, 1, 1, p2_bright))


func _draw_player_glow() -> void:
	var dist: float = p1_pos.distance_to(p2_pos)
	var closeness: float = 1.0 - clampf((dist - CLOSE_DIST) / (FAR_DIST - CLOSE_DIST), 0.0, 1.0)
	var r1: float = LIGHT_RADIUS_SOLO
	var r2: float = LIGHT_RADIUS_SOLO
	if dist < CLOSE_DIST:
		var t: float = 1.0 - (dist / CLOSE_DIST)
		r1 = lerpf(LIGHT_RADIUS_SOLO, LIGHT_RADIUS_COMBINED, t)
		r2 = r1
	if dim_timer_p1 > 0.0: r1 *= 0.5
	if dim_timer_p2 > 0.0: r2 *= 0.5

	var ga1: float = 0.06 + closeness * 0.06
	if dim_timer_p1 > 0.0: ga1 *= 0.4
	for i in range(4):
		var frac: float = (float(i) + 1.0) / 4.0
		draw_arc(p1_pos, r1 * frac, 0, TAU, 32, Color(0.3, 0.4, 0.8, ga1 * (1.0 - frac * 0.7)), 1.5)

	var ga2: float = 0.06 + closeness * 0.06
	if dim_timer_p2 > 0.0: ga2 *= 0.4
	for i in range(4):
		var frac: float = (float(i) + 1.0) / 4.0
		draw_arc(p2_pos, r2 * frac, 0, TAU, 32, Color(0.9, 0.55, 0.4, ga2 * (1.0 - frac * 0.7)), 1.5)

	if dist < CLOSE_DIST:
		var mid: Vector2 = (p1_pos + p2_pos) * 0.5
		draw_arc(mid, r1 * 0.5, 0, TAU, 32, Color(0.7, 0.6, 0.55, closeness * 0.05), 2.0)


func _draw_block_flashes() -> void:
	if block_flash_p1 > 0:
		draw_circle(block_flash_pos_p1 as Vector2, 25.0 * block_flash_p1, Color(0.3, 0.5, 0.9, block_flash_p1 * 0.4))
	if block_flash_p2 > 0:
		draw_circle(block_flash_pos_p2 as Vector2, 25.0 * block_flash_p2, Color(0.95, 0.6, 0.3, block_flash_p2 * 0.4))


func _draw_separation_indicator() -> void:
	var dist: float = p1_pos.distance_to(p2_pos)
	if dist > FAR_DIST:
		var warn_pulse: float = (sin(pulse_time * 5.0) + 1.0) * 0.5
		draw_line(p1_pos, p2_pos, Color(0.5, 0.2, 0.2, 0.08 + warn_pulse * 0.08), 1.0)


func _draw_wisp_flash() -> void:
	if wisp_flash_timer > 0:
		var r: float = 350.0 * (1.5 - wisp_flash_timer)
		draw_arc(wisp_flash_pos, r, 0, TAU, 48, Color(1.0, 0.9, 0.6, wisp_flash_timer * 0.15), 3.0)


func _draw_phase_indicator() -> void:
	# Subtle edge warning in intense phase
	if game_phase >= 2:
		var edge_pulse: float = sin(pulse_time * 2.0) * 0.03 + 0.05
		draw_rect(Rect2(0, 0, 1280, 720), Color(0.3, 0.1, 0.15, edge_pulse), false, 6.0)


func _show_dialogue() -> void:
	var lines: Array[Dictionary] = [
		{"speaker": "", "text": "Through the darkness, neither could see alone.", "color": Color(0.5, 0.5, 0.6)},
		{"speaker": "", "text": "But together, the fog lifted... and the path became clear.", "color": Color(0.8, 0.75, 0.6)},
		{"speaker": "", "text": "Something watched from behind. It always had.", "color": Color(0.4, 0.3, 0.35)},
	]
	dialogue.play_dialogue(lines)


func _on_dialogue_done() -> void:
	phase = 4
