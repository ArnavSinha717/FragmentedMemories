extends Control

## Boss Fight — GUILT. 3 phases. You MUST dodge to survive.
## GUILT heals when it hits you. Sync attacks only work during vulnerability windows.
## Standing still = death. Cooperation under pressure.

@onready var dialogue: Node = $DialogueSystem
@onready var charge_bar: ProgressBar = $HUD/ChargeBar
@onready var charge_label: Label = $HUD/ChargeLabel
@onready var boss_health_bar: ProgressBar = $HUD/BossHealthBar
@onready var hint_label: Label = $HUD/HintLabel

const PLAYER_SPEED := 290.0
const BOSS_MAX_HEALTH := 120.0
const CHARGE_PER_HIT := 22.0     # Charge fills fast
const DAMAGE_PER_SYNC := 2.0     # Regular sync hits = chip damage
const BURST_DAMAGE := 30.0       # Full charge burst = big damage
const ARENA_LEFT := 100.0
const ARENA_RIGHT := 1180.0
const ARENA_TOP := 180.0
const ARENA_BOTTOM := 640.0

# --- Players ---
var p1_pos := Vector2(400, 520)
var p2_pos := Vector2(880, 520)
var p1_vel := Vector2.ZERO
var p2_vel := Vector2.ZERO
var p1_hit_flash := 0.0
var p2_hit_flash := 0.0
var p1_stun := 0.0  # Can't move or attack while stunned
var p2_stun := 0.0

# --- Boss ---
var boss_pos := Vector2(640, 280)
var boss_health := BOSS_MAX_HEALTH
var boss_attack_timer := 2.0
var boss_attacks: Array[Dictionary] = []

# --- Tendril sweep ---
var tendril_sweep_active := false
var tendril_sweep_angle := 0.0
var tendril_sweep_speed := 2.0
var tendril_sweep_length := 380.0
var tendril_sweep_timer := 0.0

# --- Shockwaves ---
var shockwaves: Array[Dictionary] = []

# --- Darkness ---
var darkness_active := false
var darkness_timer := 0.0
const DARKNESS_DURATION := 2.5

# --- Vulnerability Window ---
# Boss is only damageable during short windows after attack patterns
var vulnerable := false
var vulnerable_timer := 0.0
const VULNERABLE_DURATION := 2.5  # Seconds the window stays open
var attacks_since_vulnerable := 0
const ATTACKS_PER_WINDOW := 3  # Boss attacks 3 times, then opens up

# --- Sync ---
var p1_press_time := -10.0
var p2_press_time := -10.0
var sync_flash := 0.0
var sync_cooldown := 0.0
const SYNC_COOLDOWN_DURATION := 0.8
var desync_punish_flash := 0.0

# --- Boss heals on hit ---
const BOSS_HEAL_ON_HIT := 3.0  # Heals when it damages a player

# --- Charge ---
var charge := 0.0
var charge_full := false
var burst_flash := 0.0  # Visual flash when burst lands
var burst_count := 0     # How many bursts landed so far

# --- Visual ---
var world_color := 1.0
var pulse_time := 0.0
var boss_tendrils: Array[float] = [0, 0.5, 1.0, 1.5, 2.0, 2.5]
var screen_shake := 0.0
var phase: int = 0  # 0=fighting, 1=fatality, 2=done
var boss_phase := 0

# --- Slam attack (boss charges at a player) ---
var slam_active := false
var slam_target := Vector2.ZERO
var slam_timer := 0.0
var slam_warned := false
const SLAM_WARN_TIME := 0.8  # Warning before slam lands
const SLAM_DAMAGE_RADIUS := 90.0


func _ready() -> void:
	charge_bar.max_value = GameManager.BOSS_CHARGE_MAX
	charge_bar.value = 0
	boss_health_bar.max_value = BOSS_MAX_HEALTH
	boss_health_bar.value = BOSS_MAX_HEALTH
	charge_label.text = "CHARGE"
	hint_label.text = "Dodge attacks — strike when it's vulnerable!"
	hint_label.modulate.a = 0.6
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
	sync_flash = maxf(0.0, sync_flash - delta * 3.0)
	desync_punish_flash = maxf(0.0, desync_punish_flash - delta * 3.0)
	screen_shake = maxf(0.0, screen_shake - delta * 4.0)
	p1_hit_flash = maxf(0.0, p1_hit_flash - delta * 4.0)
	p2_hit_flash = maxf(0.0, p2_hit_flash - delta * 4.0)
	p1_stun = maxf(0.0, p1_stun - delta)
	p2_stun = maxf(0.0, p2_stun - delta)
	sync_cooldown = maxf(0.0, sync_cooldown - delta)
	burst_flash = maxf(0.0, burst_flash - delta * 2.0)

	if phase == 2:
		GameManager.advance_phase()
		return

	var hp_ratio: float = boss_health / BOSS_MAX_HEALTH
	if hp_ratio > 0.6:
		boss_phase = 0
	elif hp_ratio > 0.3:
		boss_phase = 1
	else:
		boss_phase = 2

	_move_players(delta)
	_process_boss(delta)
	_process_tendril_sweep(delta)
	_process_shockwaves(delta)
	_process_darkness(delta)
	_process_projectiles(delta)
	_process_slam(delta)
	_process_vulnerability(delta)

	# Attack input — only during vulnerability window
	if vulnerable and p1_stun <= 0:
		if Input.is_action_just_pressed("p1_attack"):
			p1_press_time = pulse_time
			_check_sync()
	if vulnerable and p2_stun <= 0:
		if Input.is_action_just_pressed("p2_attack"):
			p2_press_time = pulse_time
			_check_sync()

	# Pressing outside vulnerability = nothing (no punishment, just wasted)

	_check_desync()

	charge_bar.value = charge
	boss_health_bar.value = boss_health

	# Update hint
	if vulnerable:
		hint_label.text = "NOW! Attack together!"
		hint_label.modulate.a = 0.8 + sin(pulse_time * 6.0) * 0.2
	else:
		hint_label.text = "Dodge! Wait for opening..."
		hint_label.modulate.a = 0.4

	queue_redraw()


func _move_players(delta: float) -> void:
	# P1
	if p1_stun <= 0:
		var p1_dir := Vector2.ZERO
		if Input.is_action_pressed("p1_up"): p1_dir.y -= 1
		if Input.is_action_pressed("p1_down"): p1_dir.y += 1
		if Input.is_action_pressed("p1_left"): p1_dir.x -= 1
		if Input.is_action_pressed("p1_right"): p1_dir.x += 1
		if p1_dir.length() > 0:
			p1_vel = p1_dir.normalized() * PLAYER_SPEED
		else:
			p1_vel = p1_vel.lerp(Vector2.ZERO, 8.0 * delta)
	else:
		p1_vel = p1_vel.lerp(Vector2.ZERO, 3.0 * delta)
	p1_pos += p1_vel * delta
	p1_pos.x = clampf(p1_pos.x, ARENA_LEFT, ARENA_RIGHT)
	p1_pos.y = clampf(p1_pos.y, ARENA_TOP, ARENA_BOTTOM)

	# P2
	if p2_stun <= 0:
		var p2_dir := Vector2.ZERO
		if Input.is_action_pressed("p2_up"): p2_dir.y -= 1
		if Input.is_action_pressed("p2_down"): p2_dir.y += 1
		if Input.is_action_pressed("p2_left"): p2_dir.x -= 1
		if Input.is_action_pressed("p2_right"): p2_dir.x += 1
		if p2_dir.length() > 0:
			p2_vel = p2_dir.normalized() * PLAYER_SPEED
		else:
			p2_vel = p2_vel.lerp(Vector2.ZERO, 8.0 * delta)
	else:
		p2_vel = p2_vel.lerp(Vector2.ZERO, 3.0 * delta)
	p2_pos += p2_vel * delta
	p2_pos.x = clampf(p2_pos.x, ARENA_LEFT, ARENA_RIGHT)
	p2_pos.y = clampf(p2_pos.y, ARENA_TOP, ARENA_BOTTOM)


func _process_boss(delta: float) -> void:
	# Drift toward midpoint between players
	var mid: Vector2 = (p1_pos + p2_pos) * 0.5
	var drift_speed: float = 30.0 + float(boss_phase) * 20.0
	boss_pos += (mid - boss_pos).normalized() * drift_speed * delta
	boss_pos.y = clampf(boss_pos.y, ARENA_TOP + 30, ARENA_BOTTOM - 120)
	boss_pos.x = clampf(boss_pos.x, ARENA_LEFT + 80, ARENA_RIGHT - 80)

	# Tendrils
	var tendril_count: int = 6 + boss_phase * 2
	while boss_tendrils.size() < tendril_count:
		boss_tendrils.append(randf() * TAU)
	for i in range(boss_tendrils.size()):
		boss_tendrils[i] += delta * (0.3 + float(i) * 0.04)

	# Don't attack during vulnerability window
	if vulnerable:
		return

	boss_attack_timer -= delta
	var interval: float = lerpf(2.0, 0.9, 1.0 - boss_health / BOSS_MAX_HEALTH)
	if boss_attack_timer <= 0:
		boss_attack_timer = interval
		_boss_attack()
		attacks_since_vulnerable += 1


func _boss_attack() -> void:
	var target: Vector2 = p1_pos if boss_pos.distance_to(p1_pos) < boss_pos.distance_to(p2_pos) else p2_pos
	var other: Vector2 = p2_pos if target == p1_pos else p1_pos

	match boss_phase:
		0:
			# Single aimed + occasional sweep
			var dir: Vector2 = (target - boss_pos).normalized()
			_spawn_proj(boss_pos + dir * 55, dir * 240.0, 12.0, 0)
			if attacks_since_vulnerable >= 2:
				_start_tendril_sweep()

		1:
			# Shotgun + shockwave + slam
			var dir: Vector2 = (target - boss_pos).normalized()
			for i in range(3):
				var spread: float = (float(i) - 1.0) * 0.22
				_spawn_proj(boss_pos + dir.rotated(spread) * 50, dir.rotated(spread) * 270.0, 10.0, 0)
			# Also at other player
			var dir2: Vector2 = (other - boss_pos).normalized()
			_spawn_proj(boss_pos + dir2 * 50, dir2 * 230.0, 11.0, 0)

			if randi() % 2 == 0:
				_spawn_shockwave(boss_pos)
			if attacks_since_vulnerable >= 2:
				_start_tendril_sweep()
				_start_slam(target)

		2:
			# Everything: shotgun both, tracking, shockwave, slam, darkness
			for t_pos in [target, other]:
				var d: Vector2 = (t_pos - boss_pos).normalized()
				for i in range(3):
					_spawn_proj(boss_pos + d.rotated((float(i) - 1.0) * 0.25) * 45, d.rotated((float(i) - 1.0) * 0.25) * 300.0, 9.0, 0)
			# Tracking
			var dir: Vector2 = (target - boss_pos).normalized()
			_spawn_proj(boss_pos + dir * 55, dir * 160.0, 14.0, 2)
			# Shockwave
			_spawn_shockwave(boss_pos)
			# Sweep
			_start_tendril_sweep()
			# Slam every other attack
			if attacks_since_vulnerable % 2 == 0:
				_start_slam(other)
			# Darkness
			if randi() % 3 == 0 and not darkness_active:
				darkness_active = true
				darkness_timer = 0.0


func _spawn_proj(pos: Vector2, vel: Vector2, size: float, type: int) -> void:
	boss_attacks.append({"pos": pos, "vel": vel, "lifetime": 5.0, "size": size, "type": type})


func _spawn_shockwave(center: Vector2) -> void:
	shockwaves.append({"center": center, "radius": 20.0, "max_radius": 420.0, "width": 20.0})
	screen_shake = 0.4


func _start_tendril_sweep() -> void:
	if tendril_sweep_active:
		return
	tendril_sweep_active = true
	tendril_sweep_angle = atan2(p1_pos.y - boss_pos.y, p1_pos.x - boss_pos.x) - PI * 0.4
	tendril_sweep_timer = 0.0
	tendril_sweep_speed = (2.0 + float(boss_phase) * 0.6) * (1.0 if randf() > 0.5 else -1.0)
	tendril_sweep_length = 350.0 + float(boss_phase) * 40.0


func _start_slam(target: Vector2) -> void:
	if slam_active:
		return
	slam_active = true
	slam_target = target
	slam_timer = 0.0
	slam_warned = false


func _process_slam(delta: float) -> void:
	if not slam_active:
		return
	slam_timer += delta

	if not slam_warned and slam_timer >= SLAM_WARN_TIME:
		slam_warned = true
		screen_shake = 0.6
		# Damage players near the slam zone
		if p1_pos.distance_to(slam_target) < SLAM_DAMAGE_RADIUS:
			_hit_player(true, (p1_pos - slam_target).normalized() * 250.0)
		if p2_pos.distance_to(slam_target) < SLAM_DAMAGE_RADIUS:
			_hit_player(false, (p2_pos - slam_target).normalized() * 250.0)

	if slam_timer > SLAM_WARN_TIME + 0.5:
		slam_active = false


func _process_vulnerability(delta: float) -> void:
	if vulnerable:
		vulnerable_timer -= delta
		if vulnerable_timer <= 0:
			vulnerable = false
			attacks_since_vulnerable = 0
			boss_attack_timer = 0.5  # Resume attacking quickly
	else:
		# Open window after enough attacks
		var threshold: int = ATTACKS_PER_WINDOW - boss_phase  # 3, 2, 1 attacks per window
		if attacks_since_vulnerable >= maxi(threshold, 1):
			vulnerable = true
			vulnerable_timer = VULNERABLE_DURATION - float(boss_phase) * 0.4  # 2.5, 2.1, 1.7s


func _process_tendril_sweep(delta: float) -> void:
	if not tendril_sweep_active:
		return
	tendril_sweep_timer += delta
	tendril_sweep_angle += tendril_sweep_speed * delta

	var sweep_end: Vector2 = boss_pos + Vector2(cos(tendril_sweep_angle), sin(tendril_sweep_angle)) * tendril_sweep_length
	if _point_near_line(p1_pos, boss_pos, sweep_end, 28.0) and p1_stun <= 0:
		_hit_player(true, (p1_pos - boss_pos).normalized() * 180.0)
	if _point_near_line(p2_pos, boss_pos, sweep_end, 28.0) and p2_stun <= 0:
		_hit_player(false, (p2_pos - boss_pos).normalized() * 180.0)

	if tendril_sweep_timer > PI / absf(tendril_sweep_speed):
		tendril_sweep_active = false


func _point_near_line(point: Vector2, line_a: Vector2, line_b: Vector2, threshold: float) -> bool:
	var ab: Vector2 = line_b - line_a
	var ap: Vector2 = point - line_a
	var t: float = clampf(ap.dot(ab) / maxf(ab.dot(ab), 0.001), 0.0, 1.0)
	return point.distance_to(line_a + ab * t) < threshold


func _process_shockwaves(delta: float) -> void:
	for i in range(shockwaves.size() - 1, -1, -1):
		var sw: Dictionary = shockwaves[i]
		sw.radius = (sw.radius as float) + 280.0 * delta
		var r: float = sw.radius
		var w: float = sw.width
		var sc: Vector2 = sw.center

		if absf(p1_pos.distance_to(sc) - r) < w * 0.5 + 16.0 and p1_stun <= 0:
			_hit_player(true, (p1_pos - sc).normalized() * 120.0)
		if absf(p2_pos.distance_to(sc) - r) < w * 0.5 + 16.0 and p2_stun <= 0:
			_hit_player(false, (p2_pos - sc).normalized() * 120.0)

		if (sw.radius as float) > (sw.max_radius as float):
			shockwaves.remove_at(i)


func _process_darkness(delta: float) -> void:
	if not darkness_active:
		return
	darkness_timer += delta
	if darkness_timer > DARKNESS_DURATION:
		darkness_active = false


func _process_projectiles(delta: float) -> void:
	for i in range(boss_attacks.size() - 1, -1, -1):
		var atk: Dictionary = boss_attacks[i]
		if (atk.type as int) == 2:
			var closer: Vector2 = p1_pos if (atk.pos as Vector2).distance_to(p1_pos) < (atk.pos as Vector2).distance_to(p2_pos) else p2_pos
			atk.vel = ((atk.vel as Vector2) + (closer - (atk.pos as Vector2)).normalized() * 140.0 * delta).limit_length(220.0)

		atk.pos = (atk.pos as Vector2) + (atk.vel as Vector2) * delta
		atk.lifetime = (atk.lifetime as float) - delta
		var ap: Vector2 = atk.pos
		var hit_r: float = (atk.size as float) + 18.0

		if ap.distance_to(p1_pos) < hit_r and p1_stun <= 0:
			_hit_player(true, (p1_pos - ap).normalized() * 100.0)
			boss_attacks.remove_at(i)
			continue
		if ap.distance_to(p2_pos) < hit_r and p2_stun <= 0:
			_hit_player(false, (p2_pos - ap).normalized() * 100.0)
			boss_attacks.remove_at(i)
			continue
		if (atk.lifetime as float) <= 0 or ap.x < -50 or ap.x > 1330 or ap.y < -50 or ap.y > 770:
			boss_attacks.remove_at(i)


func _hit_player(is_p1: bool, knockback: Vector2) -> void:
	if is_p1:
		p1_hit_flash = 1.0
		p1_stun = 0.6  # Stunned — can't move or attack
		p1_vel = knockback
		p1_pos.x = clampf(p1_pos.x, ARENA_LEFT, ARENA_RIGHT)
		p1_pos.y = clampf(p1_pos.y, ARENA_TOP, ARENA_BOTTOM)
	else:
		p2_hit_flash = 1.0
		p2_stun = 0.6
		p2_vel = knockback
		p2_pos.x = clampf(p2_pos.x, ARENA_LEFT, ARENA_RIGHT)
		p2_pos.y = clampf(p2_pos.y, ARENA_TOP, ARENA_BOTTOM)

	world_color = maxf(0.1, world_color - 0.06)
	screen_shake = 0.5
	# GUILT heals when it hurts you
	boss_health = minf(boss_health + BOSS_HEAL_ON_HIT, BOSS_MAX_HEALTH)
	boss_health_bar.value = boss_health


func _check_sync() -> void:
	if sync_cooldown > 0 or not vulnerable:
		return

	var diff: float = absf(p1_press_time - p2_press_time)
	var window: float = 0.35 - float(boss_phase) * 0.05

	if diff <= window and diff >= 0:
		sync_flash = 1.0
		sync_cooldown = SYNC_COOLDOWN_DURATION
		p1_press_time = -10.0
		p2_press_time = -10.0

		if charge_full:
			# BURST ATTACK — both press while charge is full = massive damage
			boss_health -= BURST_DAMAGE
			charge = 0.0
			charge_full = false
			burst_flash = 1.0
			burst_count += 1
			screen_shake = 0.8
			world_color = minf(1.0, world_color + 0.2)

			if boss_health <= 0:
				boss_health = 0
				phase = 1
				_show_fatality_prompt()
				return

			# After burst, close vulnerability — boss gets angry
			vulnerable = false
			vulnerable_timer = 0.0
			attacks_since_vulnerable = 0
			boss_attack_timer = 0.3
			hint_label.text = "BURST! " + str(int(boss_health)) + " HP left!"
		else:
			# Regular sync hit — chip damage + charge buildup
			boss_health -= DAMAGE_PER_SYNC
			charge += CHARGE_PER_HIT
			screen_shake = 0.3
			world_color = minf(1.0, world_color + 0.06)

			if boss_health <= 0:
				boss_health = 0
				phase = 1
				_show_fatality_prompt()
				return

			if charge >= GameManager.BOSS_CHARGE_MAX:
				charge = GameManager.BOSS_CHARGE_MAX
				charge_full = true
				hint_label.text = "CHARGE FULL! Both attack NOW!"
				hint_label.modulate.a = 1.0


func _check_desync() -> void:
	if sync_cooldown > 0 or not vulnerable:
		return
	var now: float = pulse_time
	var window: float = 0.35 - float(boss_phase) * 0.05
	if p1_press_time > 0 and (now - p1_press_time) > window + 0.15 and p2_press_time < 0:
		p1_press_time = -10.0
		desync_punish_flash = 1.0
		screen_shake = 0.2
		p1_vel += (p1_pos - boss_pos).normalized() * 100.0
	if p2_press_time > 0 and (now - p2_press_time) > window + 0.15 and p1_press_time < 0:
		p2_press_time = -10.0
		desync_punish_flash = 1.0
		screen_shake = 0.2
		p2_vel += (p2_pos - boss_pos).normalized() * 100.0


func _show_fatality_prompt() -> void:
	hint_label.text = "GUILT FALLS!"
	hint_label.modulate.a = 1.0
	# Short delay then advance
	phase = 2


# ═══════════════════════════════════════════════════════════════════════════
func _draw() -> void:
	var shake := Vector2.ZERO
	if screen_shake > 0:
		shake = Vector2(randf_range(-3, 3), randf_range(-3, 3)) * screen_shake * 6.0

	# Arena border
	var border_col := Color(0.15, 0.12, 0.18, 0.3)
	if boss_phase >= 2:
		border_col = Color(0.3, 0.1, 0.15, 0.3 + sin(pulse_time * 3.0) * 0.1)
	draw_rect(Rect2(ARENA_LEFT - 5 + shake.x, ARENA_TOP - 5 + shake.y,
		ARENA_RIGHT - ARENA_LEFT + 10, ARENA_BOTTOM - ARENA_TOP + 10), border_col, false, 2.0)

	# --- Slam warning zone ---
	if slam_active and not slam_warned:
		var warn_alpha: float = 0.15 + sin(pulse_time * 10.0) * 0.1
		draw_circle(slam_target + shake, SLAM_DAMAGE_RADIUS, Color(0.7, 0.15, 0.15, warn_alpha))
		draw_arc(slam_target + shake, SLAM_DAMAGE_RADIUS, 0, TAU, 32, Color(0.9, 0.2, 0.2, warn_alpha + 0.2), 3.0)

	# --- Boss body ---
	var bp: Vector2 = boss_pos + shake
	var boss_size: float = 70.0 + (1.0 - boss_health / BOSS_MAX_HEALTH) * 35.0 + sin(pulse_time) * 4.0

	# Vulnerability glow
	if vulnerable:
		var vglow: float = 0.15 + sin(pulse_time * 5.0) * 0.08
		draw_circle(bp, boss_size + 20, Color(0.9, 0.8, 0.2, vglow))

	draw_circle(bp, boss_size, Color(0.08, 0.06, 0.1, 0.9))
	draw_circle(bp, boss_size * 0.65, Color(0.12, 0.08, 0.15, 0.6))
	draw_circle(bp, boss_size * 0.3, Color(0.25, 0.08, 0.12, sin(pulse_time * 2.0) * 0.15 + 0.3))

	# --- Tendrils ---
	for i in range(boss_tendrils.size()):
		var angle: float = boss_tendrils[i]
		var length: float = 100.0 + float(boss_phase) * 25.0 + sin(pulse_time + float(i)) * 20.0
		var tend_end: Vector2 = bp + Vector2(cos(angle), sin(angle)) * length
		draw_line(bp, tend_end, Color(0.15, 0.1, 0.18, 0.5), 2.5)

	# --- Tendril sweep ---
	if tendril_sweep_active:
		var sweep_end: Vector2 = bp + Vector2(cos(tendril_sweep_angle), sin(tendril_sweep_angle)) * tendril_sweep_length
		draw_line(bp, sweep_end, Color(0.6, 0.15, 0.2, 0.7), 5.0)
		draw_line(bp, sweep_end, Color(0.8, 0.2, 0.25, 0.3), 14.0)

	# --- Eyes ---
	var eye_i: float = 0.6 + float(boss_phase) * 0.12 + sin(pulse_time * 2.5) * 0.1
	var eye_sz: float = 10.0 + float(boss_phase) * 2.0
	draw_circle(bp + Vector2(-22, -12), eye_sz, Color(0.5, 0.1, 0.12, eye_i))
	draw_circle(bp + Vector2(22, -12), eye_sz, Color(0.5, 0.1, 0.12, eye_i))
	draw_circle(bp + Vector2(-22, -12), eye_sz * 0.4, Color(0.9, 0.2, 0.2, eye_i))
	draw_circle(bp + Vector2(22, -12), eye_sz * 0.4, Color(0.9, 0.2, 0.2, eye_i))

	# --- Projectiles ---
	for atk: Dictionary in boss_attacks:
		var ap: Vector2 = (atk.pos as Vector2) + shake
		var sz: float = atk.size
		if (atk.type as int) == 2:
			draw_circle(ap, sz, Color(0.35, 0.12, 0.4, 0.8))
			for j in range(3):
				var ta: float = pulse_time * 3.0 + float(j) * TAU / 3.0
				draw_line(ap, ap + Vector2(cos(ta), sin(ta)) * sz * 1.5, Color(0.4, 0.15, 0.45, 0.3), 1.5)
		else:
			draw_circle(ap, sz, Color(0.3, 0.1, 0.15, 0.8))
			draw_circle(ap, sz * 0.5, Color(0.5, 0.15, 0.2, 0.5))

	# --- Shockwaves ---
	for sw: Dictionary in shockwaves:
		var sc: Vector2 = (sw.center as Vector2) + shake
		var r: float = sw.radius
		var alpha: float = 1.0 - r / (sw.max_radius as float)
		draw_arc(sc, r, 0, TAU, 48, Color(0.5, 0.15, 0.2, alpha * 0.6), (sw.width as float) * alpha)

	# --- Players ---
	# P1 Blame
	var p1_mod := Color.WHITE
	if p1_hit_flash > 0:
		p1_mod = Color(1, 0.5, 0.5, 1).lerp(Color.WHITE, 1.0 - p1_hit_flash)
	if p1_stun > 0:
		p1_mod.a = 0.5
	var p1d: Vector2 = p1_pos + shake
	var p1_facing_dir: bool = p1d.x > bp.x  # face toward boss
	var g_row: int = 5 if absf(p1_vel.x) < 30 else 6
	var g_frame: int = GameManager.anim_frame(pulse_time, 4 if g_row == 5 else 6, 8.0)
	GameManager.draw_blame_sprite(self, p1d + Vector2(0, 22), g_frame, g_row, 1.4, p1_facing_dir, p1_mod)

	# P2 Denial
	var p2_mod := Color.WHITE
	if p2_hit_flash > 0:
		p2_mod = Color(1, 0.5, 0.5, 1).lerp(Color.WHITE, 1.0 - p2_hit_flash)
	if p2_stun > 0:
		p2_mod.a = 0.5
	var p2d: Vector2 = p2_pos + shake
	var p2_facing_dir: bool = p2d.x > bp.x
	var r_row: int = 0 if absf(p2_vel.x) < 30 else 1
	var r_frame: int = GameManager.anim_frame(pulse_time, 2 if r_row == 0 else 4, 6.0)
	GameManager.draw_denial_sprite(self, p2d + Vector2(0, 24), r_frame, r_row, 2.2, p2_facing_dir, p2_mod)

	# --- Sync flash ---
	if sync_flash > 0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0.9, 0.85, 0.3, sync_flash * 0.2))
		draw_line(p1d, bp, Color(0.9, 0.8, 0.3, sync_flash * 0.5), 2.0)
		draw_line(p2d, bp, Color(0.9, 0.8, 0.3, sync_flash * 0.5), 2.0)

	# --- Desync flash ---
	if desync_punish_flash > 0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0.6, 0.1, 0.1, desync_punish_flash * 0.15))

	# --- Color drain ---
	if world_color < 0.9:
		draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0.05, 0.05, 0.05, (1.0 - world_color) * 0.6))

	# --- Darkness ---
	if darkness_active:
		var ds: float = 0.85
		if darkness_timer < 0.3:
			ds = darkness_timer / 0.3 * 0.85
		elif darkness_timer > DARKNESS_DURATION - 0.5:
			ds = (DARKNESS_DURATION - darkness_timer) / 0.5 * 0.85
		draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0.0, 0.0, 0.02, ds))
		draw_circle(p1d, 35, Color(GameManager.get_blame_color_light(), 0.08))
		draw_circle(p2d, 35, Color(GameManager.get_denial_color_light(), 0.08))

	# --- Charge glow when full (pulsing gold) ---
	if charge_full:
		draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0.9, 0.8, 0.2, sin(pulse_time * 5.0) * 0.12 + 0.2))
		# Glow around both players
		draw_circle(p1d, 35, Color(0.9, 0.8, 0.2, sin(pulse_time * 5.0) * 0.1 + 0.15))
		draw_circle(p2d, 35, Color(0.9, 0.8, 0.2, sin(pulse_time * 5.0) * 0.1 + 0.15))

	# --- Burst flash (big white flash when burst lands) ---
	if burst_flash > 0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(1.0, 0.95, 0.8, burst_flash * 0.4))
		# Damage line from players to boss
		draw_line(p1d, bp, Color(1.0, 0.9, 0.3, burst_flash * 0.8), 4.0)
		draw_line(p2d, bp, Color(1.0, 0.9, 0.3, burst_flash * 0.8), 4.0)

	# --- Phase text ---
	if boss_phase >= 2:
		draw_string(ThemeDB.fallback_font, Vector2(555, ARENA_TOP - 12), "GUILT ENRAGES",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.2, 0.2, sin(pulse_time * 2.0) * 0.1 + 0.15))


func _on_dialogue_done() -> void:
	pass
