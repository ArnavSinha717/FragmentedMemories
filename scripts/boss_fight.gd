extends Control

## Boss Fight — GUILT.
## Neither player can damage it alone. Both press attack simultaneously (~0.3s) = damage.
## Shared charge meter builds with each sync hit. Guilt attacks drain color.

@onready var dialogue: Node = $DialogueSystem
@onready var charge_bar: ProgressBar = $HUD/ChargeBar
@onready var charge_label: Label = $HUD/ChargeLabel
@onready var boss_health_bar: ProgressBar = $HUD/BossHealthBar
@onready var hint_label: Label = $HUD/HintLabel

const PLAYER_SPEED := 280.0
const SYNC_WINDOW := 0.35
const CHARGE_PER_HIT := 12.0
const BOSS_MAX_HEALTH := 100.0
const DAMAGE_PER_SYNC := 8.0
const ARENA_LEFT := 100.0
const ARENA_RIGHT := 1180.0
const ARENA_TOP := 200.0
const ARENA_BOTTOM := 620.0

# Players
var p1_pos := Vector2(400, 500)
var p2_pos := Vector2(880, 500)
var p1_vel := Vector2.ZERO
var p2_vel := Vector2.ZERO
var p1_hit_flash := 0.0
var p2_hit_flash := 0.0

# Boss
var boss_pos := Vector2(640, 250)
var boss_health := BOSS_MAX_HEALTH
var boss_phase := 0 # Gets more aggressive as health drops
var boss_attack_timer := 3.0
var boss_attacks: Array[Dictionary] = [] # Active attack projectiles

# Sync attack
var p1_press_time := -10.0
var p2_press_time := -10.0
var sync_flash := 0.0
var sync_fail_flash := 0.0

# Charge
var charge := 0.0
var charge_full := false

# Visual
var world_color := 1.0
var pulse_time := 0.0
var boss_tendrils: Array[float] = [0, 0.7, 1.4, 2.1, 2.8, 3.5] # angles
var screen_shake := 0.0
var phase: int = 0 # 0=fighting, 1=charge_full (waiting for fatality), 2=done


func _ready() -> void:
	charge_bar.max_value = GameManager.BOSS_CHARGE_MAX
	charge_bar.value = 0
	boss_health_bar.max_value = BOSS_MAX_HEALTH
	boss_health_bar.value = BOSS_MAX_HEALTH
	charge_label.text = "CHARGE"
	hint_label.text = "Attack together!"
	hint_label.modulate.a = 0.5

	# Style bars
	_style_bar(charge_bar, Color(0.9, 0.8, 0.2))
	_style_bar(boss_health_bar, Color(0.5, 0.15, 0.2))

	dialogue.dialogue_finished.connect(_on_dialogue_done)


func _style_bar(bar: ProgressBar, col: Color) -> void:
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.08, 0.12)
	bg_style.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg_style)
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)


func _process(delta: float) -> void:
	pulse_time += delta
	sync_flash = max(0, sync_flash - delta * 3.0)
	sync_fail_flash = max(0, sync_fail_flash - delta * 3.0)
	screen_shake = max(0, screen_shake - delta * 5.0)
	p1_hit_flash = max(0, p1_hit_flash - delta * 4.0)
	p2_hit_flash = max(0, p2_hit_flash - delta * 4.0)

	if phase == 2:
		GameManager.advance_phase()
		return

	# Player movement
	_move_players(delta)

	# Boss AI
	_process_boss(delta)

	# Attack input
	if Input.is_action_just_pressed("p1_attack"):
		p1_press_time = pulse_time
		_check_sync()
	if Input.is_action_just_pressed("p2_attack"):
		p2_press_time = pulse_time
		_check_sync()

	# Update bars
	charge_bar.value = charge
	boss_health_bar.value = boss_health

	queue_redraw()


func _move_players(delta: float) -> void:
	var p1_dir := Vector2.ZERO
	if Input.is_action_pressed("p1_up"): p1_dir.y -= 1
	if Input.is_action_pressed("p1_down"): p1_dir.y += 1
	if Input.is_action_pressed("p1_left"): p1_dir.x -= 1
	if Input.is_action_pressed("p1_right"): p1_dir.x += 1
	if p1_dir.length() > 0:
		p1_vel = p1_dir.normalized() * PLAYER_SPEED
	else:
		p1_vel = p1_vel.lerp(Vector2.ZERO, 8.0 * delta)
	p1_pos += p1_vel * delta
	p1_pos.x = clampf(p1_pos.x, ARENA_LEFT, ARENA_RIGHT)
	p1_pos.y = clampf(p1_pos.y, ARENA_TOP, ARENA_BOTTOM)

	var p2_dir := Vector2.ZERO
	if Input.is_action_pressed("p2_up"): p2_dir.y -= 1
	if Input.is_action_pressed("p2_down"): p2_dir.y += 1
	if Input.is_action_pressed("p2_left"): p2_dir.x -= 1
	if Input.is_action_pressed("p2_right"): p2_dir.x += 1
	if p2_dir.length() > 0:
		p2_vel = p2_dir.normalized() * PLAYER_SPEED
	else:
		p2_vel = p2_vel.lerp(Vector2.ZERO, 8.0 * delta)
	p2_pos += p2_vel * delta
	p2_pos.x = clampf(p2_pos.x, ARENA_LEFT, ARENA_RIGHT)
	p2_pos.y = clampf(p2_pos.y, ARENA_TOP, ARENA_BOTTOM)


func _process_boss(delta: float) -> void:
	# Boss hovers and pulses
	boss_pos.y = 250 + sin(pulse_time * 0.5) * 20

	# Update tendrils
	for i in range(boss_tendrils.size()):
		boss_tendrils[i] += delta * (0.3 + float(i) * 0.05)

	# Boss attacks
	boss_attack_timer -= delta
	var attack_interval := lerpf(3.0, 1.2, 1.0 - boss_health / BOSS_MAX_HEALTH)
	if boss_attack_timer <= 0:
		boss_attack_timer = attack_interval
		_boss_attack()

	# Update projectiles
	for i in range(boss_attacks.size() - 1, -1, -1):
		var atk: Dictionary = boss_attacks[i]
		atk.pos += atk.vel * delta
		atk.lifetime -= delta

		# Check hit on players
		if atk.pos.distance_to(p1_pos) < 35:
			p1_hit_flash = 1.0
			world_color = max(0.15, world_color - 0.04)
			screen_shake = 0.5
			boss_attacks.remove_at(i)
			continue
		if atk.pos.distance_to(p2_pos) < 35:
			p2_hit_flash = 1.0
			world_color = max(0.15, world_color - 0.04)
			screen_shake = 0.5
			boss_attacks.remove_at(i)
			continue

		if atk.lifetime <= 0 or atk.pos.x < -50 or atk.pos.x > 1330 or atk.pos.y > 750:
			boss_attacks.remove_at(i)


func _boss_attack() -> void:
	# Aim at closer player
	var target := p1_pos if boss_pos.distance_to(p1_pos) < boss_pos.distance_to(p2_pos) else p2_pos
	var dir := (target - boss_pos).normalized()
	boss_attacks.append({
		"pos": boss_pos + dir * 60,
		"vel": dir * 200,
		"lifetime": 4.0,
		"size": 12.0
	})
	# Second projectile at other player if boss is hurt
	if boss_health < BOSS_MAX_HEALTH * 0.5:
		var other := p2_pos if target == p1_pos else p1_pos
		var dir2 := (other - boss_pos).normalized()
		boss_attacks.append({
			"pos": boss_pos + dir2 * 60,
			"vel": dir2 * 180,
			"lifetime": 4.0,
			"size": 10.0
		})


func _check_sync() -> void:
	var diff: float = absf(p1_press_time - p2_press_time)
	if diff <= SYNC_WINDOW and diff >= 0:
		# Sync hit!
		boss_health -= DAMAGE_PER_SYNC
		charge += CHARGE_PER_HIT
		sync_flash = 1.0
		screen_shake = 0.3
		world_color = min(1.0, world_color + 0.05) # Restore color on sync

		# Reset press times so same pair doesn't re-trigger
		p1_press_time = -10.0
		p2_press_time = -10.0

		if boss_health <= 0:
			boss_health = 0
			charge = GameManager.BOSS_CHARGE_MAX
			phase = 1
			charge_full = true
			_show_fatality_prompt()
			return

		if charge >= GameManager.BOSS_CHARGE_MAX:
			charge = GameManager.BOSS_CHARGE_MAX
			charge_full = true
			_show_fatality_prompt()


func _show_fatality_prompt() -> void:
	hint_label.text = "BOTH PRESS NOW!"
	hint_label.modulate.a = 1.0
	# Wait for both to press simultaneously for fatality
	# (handled in _process — next sync triggers advance)
	phase = 2


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.03, 0.03, 0.05).lerp(Color(0.03, 0.03, 0.03), 1.0 - world_color))
	# Screen shake offset
	var shake_offset := Vector2.ZERO
	if screen_shake > 0:
		shake_offset = Vector2(randf_range(-3, 3), randf_range(-3, 3)) * screen_shake * 5.0

	# Arena border
	draw_rect(Rect2(ARENA_LEFT - 5 + shake_offset.x, ARENA_TOP - 5 + shake_offset.y,
		ARENA_RIGHT - ARENA_LEFT + 10, ARENA_BOTTOM - ARENA_TOP + 10),
		Color(0.15, 0.12, 0.18, 0.3), false, 2.0)

	# Boss — GUILT (massive dark shape)
	var bp := boss_pos + shake_offset
	var boss_size := 70.0 + sin(pulse_time) * 5.0
	# Main body
	draw_circle(bp, boss_size, Color(0.08, 0.06, 0.1, 0.9))
	draw_circle(bp, boss_size * 0.7, Color(0.12, 0.08, 0.15, 0.6))
	# Tendrils
	for i in range(boss_tendrils.size()):
		var angle: float = boss_tendrils[i]
		var length := 100 + sin(pulse_time + float(i)) * 30
		var tendril_end := bp + Vector2(cos(angle), sin(angle)) * length
		draw_line(bp, tendril_end, Color(0.15, 0.1, 0.18, 0.5), 3.0)
		draw_circle(tendril_end, 5, Color(0.2, 0.12, 0.22, 0.4))
	# Eyes
	var eye_glow := sin(pulse_time * 2) * 0.15 + 0.6
	draw_circle(bp + Vector2(-22, -12), 10, Color(0.5, 0.1, 0.12, eye_glow))
	draw_circle(bp + Vector2(22, -12), 10, Color(0.5, 0.1, 0.12, eye_glow))
	draw_circle(bp + Vector2(-22, -12), 4, Color(0.8, 0.2, 0.2, eye_glow))
	draw_circle(bp + Vector2(22, -12), 4, Color(0.8, 0.2, 0.2, eye_glow))

	# Boss projectiles
	for atk: Dictionary in boss_attacks:
		var ap: Vector2 = atk.pos + shake_offset
		draw_circle(ap, atk.size, Color(0.3, 0.1, 0.15, 0.8))
		draw_circle(ap, atk.size * 0.5, Color(0.5, 0.15, 0.2, 0.5))

	# P1 Blame
	var blame_col := GameManager.get_blame_color()
	if p1_hit_flash > 0:
		blame_col = blame_col.lerp(Color(0.8, 0.2, 0.2), p1_hit_flash * 0.6)
	var p1 := p1_pos + shake_offset
	draw_rect(Rect2(p1 - Vector2(22, 22), Vector2(44, 44)), blame_col)
	draw_rect(Rect2(p1 - Vector2(13, 13), Vector2(26, 26)), Color(GameManager.get_blame_color_light(), 0.3))

	# P2 Denial
	var denial_col := GameManager.get_denial_color()
	if p2_hit_flash > 0:
		denial_col = denial_col.lerp(Color(0.8, 0.2, 0.2), p2_hit_flash * 0.6)
	var p2 := p2_pos + shake_offset
	draw_circle(p2, 24, denial_col)
	draw_circle(p2, 14, Color(GameManager.get_denial_color_light(), 0.3))

	# Sync flash
	if sync_flash > 0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0.9, 0.85, 0.3, sync_flash * 0.2))
		# Line connecting both players through boss
		draw_line(p1, bp, Color(0.9, 0.8, 0.3, sync_flash * 0.5), 2.0)
		draw_line(p2, bp, Color(0.9, 0.8, 0.3, sync_flash * 0.5), 2.0)

	# Color drain overlay
	if world_color < 0.9:
		draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0.05, 0.05, 0.05, (1.0 - world_color) * 0.5))

	# Charge glow when full
	if charge_full:
		var glow := sin(pulse_time * 4.0) * 0.15 + 0.3
		draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0.9, 0.8, 0.2, glow))


func _on_dialogue_done() -> void:
	pass
