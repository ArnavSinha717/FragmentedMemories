extends Control

## Cooperative Minigame 1 — Multi-Block Platformer Puzzle.
## 3 colored blocks must be pushed to 3 matching target zones.
## Both players must push a block simultaneously for it to move.
## Features gravity, jumping, and multi-level platforms.

@onready var dialogue: Node = $DialogueSystem
@onready var hint_label: Label = $HintLabel
@onready var timer_label: Label = $TimerLabel

# Physics constants
const GRAVITY := 900.0
const JUMP_SPEED := -450.0
const PLAYER_SPEED := 280.0
const PUSH_FORCE := 120.0
const BLOCK_SIZE := Vector2(50, 50)
const PLAYER_W := 40.0
const PLAYER_H := 40.0
const PLAYER_RADIUS := 22.0

# Timer
const TIME_LIMIT := 60.0
var time_remaining: float = TIME_LIMIT

# Phase: 0=playing, 1=success_dialogue, 2=done
var phase: int = 0
var pulse_time: float = 0.0
var hint_shown: bool = false
var no_progress_timer: float = 0.0

# Player state
var p1_pos := Vector2(300, 580)
var p1_vel := Vector2.ZERO
var p1_on_ground: bool = false

var p2_pos := Vector2(500, 580)
var p2_vel := Vector2.ZERO
var p2_on_ground: bool = false

# Block data: position, velocity, target, locked
var block_positions: Array[Vector2] = [
	Vector2(250, 595),   # Block A on ground (bottom of 50px block = 620)
	Vector2(1000, 595),  # Block B on ground
	Vector2(640, 425),   # Block C on mid platform
]
var block_velocities: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var block_targets: Array[Vector2] = [
	Vector2(950, 425),   # A target: right mid-platform
	Vector2(550, 275),   # B target: high platform center
	Vector2(200, 595),   # C target: ground left
]
var block_locked: Array[bool] = [false, false, false]
var block_flash_timers: Array[float] = [0.0, 0.0, 0.0]

# Platform data: Rect2 for each platform
var platforms: Array[Rect2] = []

# Stepping stone platforms to connect levels
var stepping_stones: Array[Rect2] = []


func _ready() -> void:
	hint_label.text = "Both push from the same side..."
	hint_label.modulate.a = 0.0
	timer_label.text = "60"
	dialogue.dialogue_finished.connect(_on_dialogue_done)

	# Build platforms
	# Ground floor
	platforms.append(Rect2(0, 620, 1280, 100))
	# Mid-platform left
	platforms.append(Rect2(150, 450, 250, 20))
	# Mid-platform right
	platforms.append(Rect2(880, 450, 250, 20))
	# High platform center
	platforms.append(Rect2(450, 300, 380, 20))

	# Stepping stones to connect areas
	# Left ground -> left mid-platform
	stepping_stones.append(Rect2(80, 545, 80, 14))
	stepping_stones.append(Rect2(200, 500, 80, 14))
	# Right ground -> right mid-platform
	stepping_stones.append(Rect2(1120, 545, 80, 14))
	stepping_stones.append(Rect2(1000, 500, 80, 14))
	# Mid-platforms -> high platform
	stepping_stones.append(Rect2(370, 380, 80, 14))
	stepping_stones.append(Rect2(830, 380, 80, 14))


func _process(delta: float) -> void:
	pulse_time += delta

	if phase == 2:
		GameManager.advance_phase()
		return
	if phase == 1:
		queue_redraw()
		return

	# Timer countdown
	time_remaining -= delta
	if time_remaining < 0.0:
		time_remaining = 0.0
	timer_label.text = str(ceili(time_remaining))

	# Player input and physics
	_update_player_1(delta)
	_update_player_2(delta)

	# Block physics
	for i: int in range(3):
		if block_locked[i]:
			block_flash_timers[i] = maxf(block_flash_timers[i] - delta, 0.0)
			continue
		_update_block(i, delta)

	# Check cooperative pushing for each block
	for i: int in range(3):
		if block_locked[i]:
			continue
		_check_push(i, delta)

	# Player-block collision (push players out of blocks, allow standing on top)
	for i: int in range(3):
		_collide_player_with_block(true, i)
		_collide_player_with_block(false, i)

	# Check if blocks reached targets
	var all_locked: bool = true
	for i: int in range(3):
		if block_locked[i]:
			continue
		all_locked = false
		var dist: float = block_positions[i].distance_to(block_targets[i])
		if dist < 40.0:
			block_locked[i] = true
			block_positions[i] = block_targets[i]
			block_velocities[i] = Vector2.ZERO
			block_flash_timers[i] = 0.6

	if all_locked:
		phase = 1
		_show_dialogue()

	# Time ran out — still advance
	if time_remaining <= 0.0 and phase == 0:
		phase = 1
		_show_dialogue()

	# Hint system
	no_progress_timer += delta
	if no_progress_timer > 10.0 and not hint_shown:
		hint_shown = true
		hint_label.modulate.a = 0.6

	queue_redraw()


func _update_player_1(delta: float) -> void:
	var dir_x: float = 0.0
	if Input.is_action_pressed("p1_left"):
		dir_x -= 1.0
	if Input.is_action_pressed("p1_right"):
		dir_x += 1.0

	p1_vel.x = dir_x * PLAYER_SPEED
	p1_vel.y += GRAVITY * delta

	# Jump
	if p1_on_ground and Input.is_action_just_pressed("p1_up"):
		p1_vel.y = JUMP_SPEED

	p1_pos += p1_vel * delta

	# Platform collision
	p1_on_ground = false
	p1_on_ground = _resolve_platform_collision_player(true)

	# Screen bounds
	p1_pos.x = clampf(p1_pos.x, 20.0, 1260.0)
	if p1_pos.y > 600.0:
		p1_pos.y = 600.0
		p1_vel.y = 0.0
		p1_on_ground = true


func _update_player_2(delta: float) -> void:
	var dir_x: float = 0.0
	if Input.is_action_pressed("p2_left"):
		dir_x -= 1.0
	if Input.is_action_pressed("p2_right"):
		dir_x += 1.0

	p2_vel.x = dir_x * PLAYER_SPEED
	p2_vel.y += GRAVITY * delta

	# Jump
	if p2_on_ground and Input.is_action_just_pressed("p2_up"):
		p2_vel.y = JUMP_SPEED

	p2_pos += p2_vel * delta

	# Platform collision
	p2_on_ground = false
	p2_on_ground = _resolve_platform_collision_player(false)

	# Screen bounds
	p2_pos.x = clampf(p2_pos.x, 20.0, 1260.0)
	if p2_pos.y > 600.0:
		p2_pos.y = 600.0
		p2_vel.y = 0.0
		p2_on_ground = true


func _resolve_platform_collision_player(is_p1: bool) -> bool:
	var pos: Vector2 = p1_pos if is_p1 else p2_pos
	var vel: Vector2 = p1_vel if is_p1 else p2_vel
	var half_w: float = PLAYER_W * 0.5
	var half_h: float = PLAYER_H * 0.5
	var on_ground: bool = false

	var all_plats: Array[Rect2] = []
	for p: Rect2 in platforms:
		all_plats.append(p)
	for s: Rect2 in stepping_stones:
		all_plats.append(s)

	for plat: Rect2 in all_plats:
		# Only land on top if falling downward
		var player_bottom: float = pos.y + half_h
		var player_top: float = pos.y - half_h
		var player_left: float = pos.x - half_w
		var player_right: float = pos.x + half_w

		# Check horizontal overlap
		if player_right > plat.position.x and player_left < plat.position.x + plat.size.x:
			# Landing on top
			if player_bottom >= plat.position.y and player_bottom <= plat.position.y + plat.size.y + 10 and vel.y >= 0:
				pos.y = plat.position.y - half_h
				vel.y = 0.0
				on_ground = true

	if is_p1:
		p1_pos = pos
		p1_vel = vel
	else:
		p2_pos = pos
		p2_vel = vel

	return on_ground


func _update_block(index: int, delta: float) -> void:
	# Apply gravity to block
	block_velocities[index].y += GRAVITY * delta

	# Apply friction to horizontal velocity
	block_velocities[index].x *= 0.90

	block_positions[index] += block_velocities[index] * delta

	# Platform collision for block
	var bpos: Vector2 = block_positions[index]
	var bvel: Vector2 = block_velocities[index]
	var half: float = BLOCK_SIZE.x * 0.5

	var all_plats: Array[Rect2] = []
	for p: Rect2 in platforms:
		all_plats.append(p)
	for s: Rect2 in stepping_stones:
		all_plats.append(s)

	for plat: Rect2 in all_plats:
		var block_bottom: float = bpos.y + half
		var block_left: float = bpos.x - half
		var block_right: float = bpos.x + half

		if block_right > plat.position.x and block_left < plat.position.x + plat.size.x:
			if block_bottom >= plat.position.y and block_bottom <= plat.position.y + plat.size.y + 10 and bvel.y >= 0:
				bpos.y = plat.position.y - half
				bvel.y = 0.0

	# Screen bounds
	bpos.x = clampf(bpos.x, half, 1280.0 - half)

	block_positions[index] = bpos
	block_velocities[index] = bvel


func _check_push(index: int, delta: float) -> void:
	var bpos: Vector2 = block_positions[index]
	var half: float = BLOCK_SIZE.x * 0.5
	var push_range: float = 35.0

	var block_rect: Rect2 = Rect2(bpos.x - half, bpos.y - half, BLOCK_SIZE.x, BLOCK_SIZE.y)

	var p1_side: String = _get_push_side(p1_pos, PLAYER_W * 0.5, PLAYER_H * 0.5, block_rect, push_range)
	var p2_side: String = _get_push_side(p2_pos, PLAYER_RADIUS, PLAYER_RADIUS, block_rect, push_range)

	# Both on same side = cooperative push
	if p1_side != "" and p2_side != "" and p1_side == p2_side:
		var push_dir: Vector2 = Vector2.ZERO
		match p1_side:
			"left":
				push_dir = Vector2.RIGHT
			"right":
				push_dir = Vector2.LEFT
		block_velocities[index] += push_dir * PUSH_FORCE * delta
		no_progress_timer = 0.0


func _get_push_side(pos: Vector2, half_w: float, half_h: float, block_rect: Rect2, push_range: float) -> String:
	var player_bottom: float = pos.y + half_h
	var player_top: float = pos.y - half_h

	# Check vertical overlap (must be roughly at same height as block)
	if player_bottom < block_rect.position.y - 5 or player_top > block_rect.end.y + 5:
		return ""

	# Check left side
	if pos.x < block_rect.position.x and absf(pos.x + half_w - block_rect.position.x) < push_range:
		return "left"

	# Check right side
	if pos.x > block_rect.end.x and absf(pos.x - half_w - block_rect.end.x) < push_range:
		return "right"

	return ""


func _collide_player_with_block(is_p1: bool, block_index: int) -> void:
	var pos: Vector2 = p1_pos if is_p1 else p2_pos
	var vel: Vector2 = p1_vel if is_p1 else p2_vel
	var half_w: float = PLAYER_W * 0.5 if is_p1 else PLAYER_RADIUS
	var half_h: float = PLAYER_H * 0.5 if is_p1 else PLAYER_RADIUS

	var bpos: Vector2 = block_positions[block_index]
	var bhalf: float = BLOCK_SIZE.x * 0.5

	var block_rect: Rect2 = Rect2(bpos.x - bhalf, bpos.y - bhalf, BLOCK_SIZE.x, BLOCK_SIZE.y)
	var player_rect: Rect2 = Rect2(pos.x - half_w, pos.y - half_h, half_w * 2, half_h * 2)

	if not block_rect.intersects(player_rect):
		return

	# Calculate overlap on each axis
	var overlap_x: float = minf(player_rect.end.x - block_rect.position.x, block_rect.end.x - player_rect.position.x)
	var overlap_y: float = minf(player_rect.end.y - block_rect.position.y, block_rect.end.y - player_rect.position.y)

	if overlap_y < overlap_x:
		# Vertical resolution
		if pos.y < bpos.y:
			# Player is above block — stand on it
			pos.y = block_rect.position.y - half_h
			vel.y = 0.0
			if is_p1:
				p1_on_ground = true
			else:
				p2_on_ground = true
		else:
			# Player is below block — push down
			pos.y = block_rect.end.y + half_h
			if vel.y < 0.0:
				vel.y = 0.0
	else:
		# Horizontal resolution
		if pos.x < bpos.x:
			pos.x = block_rect.position.x - half_w
		else:
			pos.x = block_rect.end.x + half_w

	if is_p1:
		p1_pos = pos
		p1_vel = vel
	else:
		p2_pos = pos
		p2_vel = vel


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.07, 0.07, 0.1))

	# Draw platforms
	var plat_color := Color(0.18, 0.18, 0.22)
	var plat_edge_color := Color(0.3, 0.3, 0.35, 0.6)
	for plat: Rect2 in platforms:
		draw_rect(plat, plat_color)
		draw_rect(plat, plat_edge_color, false, 1.5)

	# Draw stepping stones
	var stone_color := Color(0.15, 0.15, 0.2)
	var stone_edge := Color(0.25, 0.25, 0.32, 0.5)
	for stone: Rect2 in stepping_stones:
		draw_rect(stone, stone_color)
		draw_rect(stone, stone_edge, false, 1.0)

	# Draw target zones (pulsing)
	var target_labels: Array[String] = ["A", "B", "C"]
	for i: int in range(3):
		var tpos: Vector2 = block_targets[i]
		var alpha: float = 0.15 + sin(pulse_time * 2.0 + float(i) * 1.5) * 0.08
		var target_size: Vector2 = BLOCK_SIZE + Vector2(16, 16)
		var target_rect: Rect2 = Rect2(tpos - target_size * 0.5, target_size)

		if block_locked[i]:
			# Locked — solid glow
			draw_rect(target_rect, Color(0.3, 0.8, 0.3, 0.25))
		else:
			draw_rect(target_rect, Color(0.4, 0.8, 0.4, alpha))
			draw_rect(target_rect, Color(0.5, 0.9, 0.5, 0.3), false, 2.0)
			# Crosshair
			draw_line(tpos + Vector2(-18, 0), tpos + Vector2(18, 0), Color(0.5, 0.8, 0.5, 0.3), 1.0)
			draw_line(tpos + Vector2(0, -18), tpos + Vector2(0, 18), Color(0.5, 0.8, 0.5, 0.3), 1.0)

	# Draw blocks
	for i: int in range(3):
		var bpos: Vector2 = block_positions[i]
		var bhalf: float = BLOCK_SIZE.x * 0.5
		var brect: Rect2 = Rect2(bpos - Vector2(bhalf, bhalf), BLOCK_SIZE)

		var block_col: Color = Color(0.4, 0.38, 0.45)
		if block_locked[i] and block_flash_timers[i] > 0.0:
			# Flash white when locking
			var flash: float = block_flash_timers[i] / 0.6
			block_col = block_col.lerp(Color(1, 1, 1), flash * 0.6)

		draw_rect(brect, block_col)
		draw_rect(brect, Color(0.5, 0.48, 0.55, 0.5), false, 2.0)

		# Inner cross pattern
		draw_line(bpos + Vector2(-15, 0), bpos + Vector2(15, 0), Color(0.5, 0.5, 0.55, 0.3), 1.5)
		draw_line(bpos + Vector2(0, -15), bpos + Vector2(0, 15), Color(0.5, 0.5, 0.55, 0.3), 1.5)

	# P1 Blame (rectangle)
	draw_rect(Rect2(p1_pos - Vector2(20, 20), Vector2(40, 40)), GameManager.get_blame_color())
	draw_rect(Rect2(p1_pos - Vector2(12, 12), Vector2(24, 24)), Color(GameManager.get_blame_color_light(), 0.3))

	# P2 Denial (circle)
	draw_circle(p2_pos, 22, GameManager.get_denial_color())
	draw_circle(p2_pos, 13, Color(GameManager.get_denial_color_light(), 0.3))

	# Timer bar at top
	if phase == 0:
		var bar_width: float = (time_remaining / TIME_LIMIT) * 200.0
		var bar_color: Color = Color(0.5, 0.7, 0.5, 0.4)
		if time_remaining < 15.0:
			bar_color = Color(0.8, 0.3, 0.3, 0.5)
		draw_rect(Rect2(540, 18, bar_width, 8), bar_color)
		draw_rect(Rect2(540, 18, 200, 8), Color(0.3, 0.3, 0.35, 0.3), false, 1.0)

	# Block progress indicator
	var locked_count: int = 0
	for i: int in range(3):
		if block_locked[i]:
			locked_count += 1
	if locked_count > 0 and phase == 0:
		var indicator_text: String = str(locked_count) + "/3"
		draw_string(ThemeDB.fallback_font, Vector2(620, 55), indicator_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color(0.5, 0.8, 0.5, 0.6))


func _show_dialogue() -> void:
	var lines: Array[Dictionary] = [
		{"speaker": "Blame", "text": "So she wasn't a random stranger. We weren't each other's burden. We were each other's reason.", "color": GameManager.get_blame_color_light()},
		{"speaker": "Denial", "text": "But she trusted me. She loved us so much.", "color": GameManager.get_denial_color_light()},
	]
	dialogue.play_dialogue(lines)


func _on_dialogue_done() -> void:
	phase = 2
