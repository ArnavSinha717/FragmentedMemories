extends Control

## Boss Fight — GUILT. 3 escalating phases. Anti-spam sync cooldown.
## Tendril sweeps, shotgun bursts, shockwaves, darkness pulses.
## Boss drifts toward players and grows larger as it weakens.

@onready var dialogue: Node = $DialogueSystem
@onready var charge_bar: ProgressBar = $HUD/ChargeBar
@onready var charge_label: Label = $HUD/ChargeLabel
@onready var boss_health_bar: ProgressBar = $HUD/BossHealthBar
@onready var hint_label: Label = $HUD/HintLabel

const PLAYER_SPEED := 280.0
const BOSS_MAX_HEALTH := 150.0
const CHARGE_PER_HIT := 10.0
const DAMAGE_PER_SYNC := 6.0
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

# --- Boss ---
var boss_pos := Vector2(640, 250)
var boss_vel := Vector2.ZERO
var boss_health := BOSS_MAX_HEALTH
var boss_attack_timer := 2.5
var boss_attacks: Array[Dictionary] = []  # {pos, vel, lifetime, size, type}
# type: 0=projectile, 1=shockwave(expanding ring), 2=tracking

# --- Tendril sweep ---
var tendril_sweep_active := false
var tendril_sweep_angle := 0.0
var tendril_sweep_speed := 1.5
var tendril_sweep_length := 350.0
var tendril_sweep_timer := 0.0

# --- Shockwave ---
var shockwaves: Array[Dictionary] = []  # {center, radius, max_radius, width}

# --- Darkness pulse ---
var darkness_active := false
var darkness_timer := 0.0
const DARKNESS_DURATION := 2.5

# --- Sync attack ---
var p1_press_time := -10.0
var p2_press_time := -10.0
var sync_flash := 0.0
var sync_cooldown := 0.0  # Anti-spam: must wait before next sync registers
const SYNC_COOLDOWN_DURATION := 1.5
var desync_punish_flash := 0.0  # Flash when players press out of sync

# --- Charge ---
var charge := 0.0
var charge_full := false

# --- Visual ---
var world_color := 1.0
var pulse_time := 0.0
var boss_tendrils: Array[float] = [0, 0.5, 1.0, 1.5, 2.0, 2.5]
var screen_shake := 0.0
var phase: int = 0  # 0=fighting, 1=fatality_prompt, 2=done

# --- Boss phase (difficulty) ---
var boss_phase := 0  # 0=easy, 1=medium, 2=hard


func _ready() -> void:
	charge_bar.max_value = GameManager.BOSS_CHARGE_MAX
	charge_bar.value = 0
	boss_health_bar.max_value = BOSS_MAX_HEALTH
	boss_health_bar.value = BOSS_MAX_HEALTH
	charge_label.text = "CHARGE"
	hint_label.text = "Attack together — in sync!"
	hint_label.modulate.a = 0.5
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
	sync_cooldown = maxf(0.0, sync_cooldown - delta)

	if phase == 2:
		GameManager.advance_phase()
		return

	# Update boss phase based on health
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

	# Attack input
	if Input.is_action_just_pressed("p1_attack"):
		p1_press_time = pulse_time
		_check_sync()
	if Input.is_action_just_pressed("p2_attack"):
		p2_press_time = pulse_time
		_check_sync()

	# Desync punishment: if one pressed but other didn't within window
	_check_desync()

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
	# Boss drifts toward closer player (faster in later phases)
	var closer: Vector2 = p1_pos if boss_pos.distance_to(p1_pos) < boss_pos.distance_to(p2_pos) else p2_pos
	var drift_speed: float = 20.0 + float(boss_phase) * 25.0
	var drift_dir: Vector2 = (closer - boss_pos).normalized()
	boss_pos += drift_dir * drift_speed * delta

	# Vertical hover
	boss_pos.y = clampf(boss_pos.y, ARENA_TOP + 20, ARENA_BOTTOM - 100)
	boss_pos.x = clampf(boss_pos.x, ARENA_LEFT + 80, ARENA_RIGHT - 80)

	# Add hover bob
	boss_pos.y += sin(pulse_time * 0.6) * 15.0 * delta

	# Update tendril angles
	var tendril_count: int = 6 + boss_phase * 2  # 6, 8, 10 tendrils
	while boss_tendrils.size() < tendril_count:
		boss_tendrils.append(randf() * TAU)
	for i in range(boss_tendrils.size()):
		boss_tendrils[i] += delta * (0.3 + float(i) * 0.04)

	# Boss attacks on timer
	boss_attack_timer -= delta
	var interval: float = lerpf(2.5, 0.8, 1.0 - boss_health / BOSS_MAX_HEALTH)
	if boss_attack_timer <= 0:
		boss_attack_timer = interval
		_boss_attack()


func _boss_attack() -> void:
	var target: Vector2 = p1_pos if boss_pos.distance_to(p1_pos) < boss_pos.distance_to(p2_pos) else p2_pos
	var other: Vector2 = p2_pos if target == p1_pos else p1_pos

	match boss_phase:
		0:  # Phase 1: single aimed + occasional tendril sweep
			var dir: Vector2 = (target - boss_pos).normalized()
			_spawn_projectile(boss_pos + dir * 60, dir * 220.0, 12.0, 0)
			# Tendril sweep every 3rd attack
			if randi() % 3 == 0:
				_start_tendril_sweep()

		1:  # Phase 2: shotgun bursts + shockwave
			var dir: Vector2 = (target - boss_pos).normalized()
			# Shotgun: 4 projectiles in a spread
			for i in range(4):
				var spread: float = (float(i) - 1.5) * 0.2
				var shot_dir: Vector2 = dir.rotated(spread)
				_spawn_projectile(boss_pos + shot_dir * 55, shot_dir * 250.0, 10.0, 0)
			# Also aim at other player
			var dir2: Vector2 = (other - boss_pos).normalized()
			_spawn_projectile(boss_pos + dir2 * 55, dir2 * 200.0, 11.0, 0)
			# Shockwave every 2nd attack
			if randi() % 2 == 0:
				_spawn_shockwave(boss_pos)
			# Tendril sweep
			if randi() % 2 == 0:
				_start_tendril_sweep()

		2:  # Phase 3: everything + tracking projectiles + darkness
			var dir: Vector2 = (target - boss_pos).normalized()
			# Shotgun burst at both players
			for t_pos in [target, other]:
				var d: Vector2 = (t_pos - boss_pos).normalized()
				for i in range(3):
					var spread: float = (float(i) - 1.0) * 0.25
					var shot_dir: Vector2 = d.rotated(spread)
					_spawn_projectile(boss_pos + shot_dir * 50, shot_dir * 280.0, 9.0, 0)
			# Tracking projectile
			_spawn_projectile(boss_pos + dir * 60, dir * 150.0, 14.0, 2)
			# Shockwave
			if randi() % 2 == 0:
				_spawn_shockwave(boss_pos)
			# Tendril sweep (faster)
			_start_tendril_sweep()
			# Darkness pulse every 3rd attack
			if randi() % 3 == 0 and not darkness_active:
				darkness_active = true
				darkness_timer = 0.0


func _spawn_projectile(pos: Vector2, vel: Vector2, size: float, type: int) -> void:
	boss_attacks.append({"pos": pos, "vel": vel, "lifetime": 5.0, "size": size, "type": type})


func _spawn_shockwave(center: Vector2) -> void:
	shockwaves.append({"center": center, "radius": 30.0, "max_radius": 400.0, "width": 18.0})
	screen_shake = 0.4


func _start_tendril_sweep() -> void:
	if tendril_sweep_active:
		return
	tendril_sweep_active = true
	tendril_sweep_angle = atan2(p1_pos.y - boss_pos.y, p1_pos.x - boss_pos.x) - PI * 0.5
	tendril_sweep_timer = 0.0
	var base_speed: float = 1.5 + float(boss_phase) * 0.8
	tendril_sweep_speed = base_speed * (1.0 if randf() > 0.5 else -1.0)
	tendril_sweep_length = 300.0 + float(boss_phase) * 50.0


func _process_tendril_sweep(delta: float) -> void:
	if not tendril_sweep_active:
		return
	tendril_sweep_timer += delta
	tendril_sweep_angle += tendril_sweep_speed * delta

	# Check if sweep hits players
	var sweep_end: Vector2 = boss_pos + Vector2(cos(tendril_sweep_angle), sin(tendril_sweep_angle)) * tendril_sweep_length
	# Simple line-point distance check
	if _point_near_line(p1_pos, boss_pos, sweep_end, 25.0):
		p1_hit_flash = 1.0
		world_color = maxf(0.1, world_color - 0.06)
		screen_shake = 0.5
		var push: Vector2 = (p1_pos - boss_pos).normalized() * 150.0
		p1_pos += push
		p1_pos.x = clampf(p1_pos.x, ARENA_LEFT, ARENA_RIGHT)
		p1_pos.y = clampf(p1_pos.y, ARENA_TOP, ARENA_BOTTOM)

	if _point_near_line(p2_pos, boss_pos, sweep_end, 25.0):
		p2_hit_flash = 1.0
		world_color = maxf(0.1, world_color - 0.06)
		screen_shake = 0.5
		var push: Vector2 = (p2_pos - boss_pos).normalized() * 150.0
		p2_pos += push
		p2_pos.x = clampf(p2_pos.x, ARENA_LEFT, ARENA_RIGHT)
		p2_pos.y = clampf(p2_pos.y, ARENA_TOP, ARENA_BOTTOM)

	# Sweep lasts ~PI radians (half rotation)
	if tendril_sweep_timer > PI / absf(tendril_sweep_speed):
		tendril_sweep_active = false


func _point_near_line(point: Vector2, line_a: Vector2, line_b: Vector2, threshold: float) -> bool:
	var ab: Vector2 = line_b - line_a
	var ap: Vector2 = point - line_a
	var t: float = clampf(ap.dot(ab) / maxf(ab.dot(ab), 0.001), 0.0, 1.0)
	var closest: Vector2 = line_a + ab * t
	return point.distance_to(closest) < threshold


func _process_shockwaves(delta: float) -> void:
	for i in range(shockwaves.size() - 1, -1, -1):
		var sw: Dictionary = shockwaves[i]
		sw.radius = (sw.radius as float) + 250.0 * delta

		# Check player hits (hit if player is near the ring edge)
		var r: float = sw.radius
		var w: float = sw.width
		var sc: Vector2 = sw.center
		var d1: float = absf(p1_pos.distance_to(sc) - r)
		var d2: float = absf(p2_pos.distance_to(sc) - r)
		if d1 < w * 0.5 + 15.0:
			p1_hit_flash = 1.0
			world_color = maxf(0.1, world_color - 0.05)
			screen_shake = 0.4
		if d2 < w * 0.5 + 15.0:
			p2_hit_flash = 1.0
			world_color = maxf(0.1, world_color - 0.05)
			screen_shake = 0.4

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
		var atype: int = atk.type

		# Tracking projectiles home slightly toward closer player
		if atype == 2:
			var closer: Vector2 = p1_pos if (atk.pos as Vector2).distance_to(p1_pos) < (atk.pos as Vector2).distance_to(p2_pos) else p2_pos
			var track_dir: Vector2 = (closer - (atk.pos as Vector2)).normalized()
			atk.vel = ((atk.vel as Vector2) + track_dir * 120.0 * delta).limit_length(200.0)

		atk.pos = (atk.pos as Vector2) + (atk.vel as Vector2) * delta
		atk.lifetime = (atk.lifetime as float) - delta

		var ap: Vector2 = atk.pos
		var hit_range: float = (atk.size as float) + 18.0

		if ap.distance_to(p1_pos) < hit_range:
			p1_hit_flash = 1.0
			world_color = maxf(0.1, world_color - 0.05)
			screen_shake = 0.5
			boss_attacks.remove_at(i)
			continue
		if ap.distance_to(p2_pos) < hit_range:
			p2_hit_flash = 1.0
			world_color = maxf(0.1, world_color - 0.05)
			screen_shake = 0.5
			boss_attacks.remove_at(i)
			continue

		if (atk.lifetime as float) <= 0 or ap.x < -50 or ap.x > 1330 or ap.y < -50 or ap.y > 770:
			boss_attacks.remove_at(i)


func _check_sync() -> void:
	if sync_cooldown > 0:
		return  # Anti-spam: can't sync during cooldown

	var diff: float = absf(p1_press_time - p2_press_time)
	# Sync window tightens with boss phase
	var window: float = 0.35 - float(boss_phase) * 0.07  # 0.35 → 0.28 → 0.21

	if diff <= window and diff >= 0:
		# Sync hit!
		boss_health -= DAMAGE_PER_SYNC
		charge += CHARGE_PER_HIT
		sync_flash = 1.0
		screen_shake = 0.35
		world_color = minf(1.0, world_color + 0.06)
		sync_cooldown = SYNC_COOLDOWN_DURATION  # Prevent spam

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


func _check_desync() -> void:
	# If one player pressed but other didn't within the window → punish
	if sync_cooldown > 0:
		return
	var now: float = pulse_time
	var window: float = 0.35 - float(boss_phase) * 0.07
	var p1_stale: bool = p1_press_time > 0 and (now - p1_press_time) > window + 0.1
	var p2_stale: bool = p2_press_time > 0 and (now - p2_press_time) > window + 0.1

	if p1_stale and not p2_stale and p2_press_time < 0:
		# P1 pressed alone — punish
		p1_press_time = -10.0
		desync_punish_flash = 1.0
		screen_shake = 0.2
		var push: Vector2 = (p1_pos - boss_pos).normalized() * 80.0
		p1_pos += push
		p1_pos.x = clampf(p1_pos.x, ARENA_LEFT, ARENA_RIGHT)
		p1_pos.y = clampf(p1_pos.y, ARENA_TOP, ARENA_BOTTOM)

	if p2_stale and not p1_stale and p1_press_time < 0:
		p2_press_time = -10.0
		desync_punish_flash = 1.0
		screen_shake = 0.2
		var push: Vector2 = (p2_pos - boss_pos).normalized() * 80.0
		p2_pos += push
		p2_pos.x = clampf(p2_pos.x, ARENA_LEFT, ARENA_RIGHT)
		p2_pos.y = clampf(p2_pos.y, ARENA_TOP, ARENA_BOTTOM)


func _show_fatality_prompt() -> void:
	hint_label.text = "BOTH PRESS NOW!"
	hint_label.modulate.a = 1.0
	phase = 2


# ═══════════════════════════════════════════════════════════════════════════
func _draw() -> void:
	var shake_offset := Vector2.ZERO
	if screen_shake > 0:
		shake_offset = Vector2(randf_range(-3, 3), randf_range(-3, 3)) * screen_shake * 6.0

	# Arena border (pulses red in phase 2+)
	var border_col := Color(0.15, 0.12, 0.18, 0.3)
	if boss_phase >= 2:
		border_col = Color(0.3, 0.1, 0.15, 0.3 + sin(pulse_time * 3.0) * 0.1)
	draw_rect(Rect2(ARENA_LEFT - 5 + shake_offset.x, ARENA_TOP - 5 + shake_offset.y,
		ARENA_RIGHT - ARENA_LEFT + 10, ARENA_BOTTOM - ARENA_TOP + 10), border_col, false, 2.0)

	# --- Boss body (grows with damage) ---
	var bp: Vector2 = boss_pos + shake_offset
	var boss_size: float = 70.0 + (1.0 - boss_health / BOSS_MAX_HEALTH) * 40.0 + sin(pulse_time) * 5.0
	draw_circle(bp, boss_size, Color(0.08, 0.06, 0.1, 0.9))
	draw_circle(bp, boss_size * 0.65, Color(0.12, 0.08, 0.15, 0.6))
	# Inner pulsing core
	var core_pulse: float = sin(pulse_time * 2.0) * 0.15 + 0.3
	draw_circle(bp, boss_size * 0.3, Color(0.25, 0.08, 0.12, core_pulse))

	# --- Tendrils ---
	for i in range(boss_tendrils.size()):
		var angle: float = boss_tendrils[i]
		var length: float = (100.0 + float(boss_phase) * 30.0 + sin(pulse_time + float(i)) * 25.0)
		var tendril_end: Vector2 = bp + Vector2(cos(angle), sin(angle)) * length
		var tendril_col := Color(0.15, 0.1, 0.18, 0.5)
		draw_line(bp, tendril_end, tendril_col, 2.5 + float(boss_phase) * 0.5)
		draw_circle(tendril_end, 4 + boss_phase, Color(0.2, 0.12, 0.22, 0.4))

	# --- Tendril sweep (thick dangerous line) ---
	if tendril_sweep_active:
		var sweep_end: Vector2 = bp + Vector2(cos(tendril_sweep_angle), sin(tendril_sweep_angle)) * tendril_sweep_length
		var sweep_col := Color(0.6, 0.15, 0.2, 0.7)
		draw_line(bp, sweep_end, sweep_col, 5.0)
		# Warning glow
		draw_line(bp, sweep_end, Color(0.8, 0.2, 0.25, 0.3), 12.0)

	# --- Eyes (glow more intensely in later phases) ---
	var eye_intensity: float = 0.6 + float(boss_phase) * 0.15 + sin(pulse_time * 2.5) * 0.1
	var eye_size: float = 10.0 + float(boss_phase) * 3.0
	draw_circle(bp + Vector2(-22, -12), eye_size, Color(0.5, 0.1, 0.12, eye_intensity))
	draw_circle(bp + Vector2(22, -12), eye_size, Color(0.5, 0.1, 0.12, eye_intensity))
	draw_circle(bp + Vector2(-22, -12), eye_size * 0.4, Color(0.9, 0.2, 0.2, eye_intensity))
	draw_circle(bp + Vector2(22, -12), eye_size * 0.4, Color(0.9, 0.2, 0.2, eye_intensity))

	# --- Projectiles ---
	for atk: Dictionary in boss_attacks:
		var ap: Vector2 = (atk.pos as Vector2) + shake_offset
		var sz: float = atk.size
		var atype: int = atk.type
		if atype == 2:
			# Tracking — purple with tendrils
			draw_circle(ap, sz, Color(0.35, 0.12, 0.4, 0.8))
			draw_circle(ap, sz * 0.5, Color(0.5, 0.2, 0.5, 0.5))
			for j in range(3):
				var ta: float = pulse_time * 3.0 + float(j) * TAU / 3.0
				draw_line(ap, ap + Vector2(cos(ta), sin(ta)) * sz * 1.5, Color(0.4, 0.15, 0.45, 0.3), 1.5)
		else:
			draw_circle(ap, sz, Color(0.3, 0.1, 0.15, 0.8))
			draw_circle(ap, sz * 0.5, Color(0.5, 0.15, 0.2, 0.5))

	# --- Shockwaves ---
	for sw: Dictionary in shockwaves:
		var sc: Vector2 = (sw.center as Vector2) + shake_offset
		var r: float = sw.radius
		var alpha: float = 1.0 - r / (sw.max_radius as float)
		draw_arc(sc, r, 0, TAU, 48, Color(0.5, 0.15, 0.2, alpha * 0.6), (sw.width as float) * alpha)

	# --- Players ---
	var blame_col := GameManager.get_blame_color()
	if p1_hit_flash > 0:
		blame_col = blame_col.lerp(Color(0.8, 0.2, 0.2), p1_hit_flash * 0.6)
	var p1: Vector2 = p1_pos + shake_offset
	draw_rect(Rect2(p1 - Vector2(22, 22), Vector2(44, 44)), blame_col)
	draw_rect(Rect2(p1 - Vector2(13, 13), Vector2(26, 26)), Color(GameManager.get_blame_color_light(), 0.3))

	var denial_col := GameManager.get_denial_color()
	if p2_hit_flash > 0:
		denial_col = denial_col.lerp(Color(0.8, 0.2, 0.2), p2_hit_flash * 0.6)
	var p2: Vector2 = p2_pos + shake_offset
	draw_circle(p2, 24, denial_col)
	draw_circle(p2, 14, Color(GameManager.get_denial_color_light(), 0.3))

	# --- Sync flash ---
	if sync_flash > 0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0.9, 0.85, 0.3, sync_flash * 0.2))
		draw_line(p1, bp, Color(0.9, 0.8, 0.3, sync_flash * 0.5), 2.0)
		draw_line(p2, bp, Color(0.9, 0.8, 0.3, sync_flash * 0.5), 2.0)

	# --- Desync punish flash ---
	if desync_punish_flash > 0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0.6, 0.1, 0.1, desync_punish_flash * 0.15))

	# --- Sync cooldown indicator ---
	if sync_cooldown > 0:
		var cd_alpha: float = sync_cooldown / SYNC_COOLDOWN_DURATION * 0.4
		var mid: Vector2 = (p1_pos + p2_pos) * 0.5 + shake_offset
		draw_arc(mid, 20, -PI * 0.5, -PI * 0.5 + TAU * (sync_cooldown / SYNC_COOLDOWN_DURATION), 24, Color(0.5, 0.5, 0.6, cd_alpha), 2.0)

	# --- Color drain overlay ---
	if world_color < 0.9:
		draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0.05, 0.05, 0.05, (1.0 - world_color) * 0.6))

	# --- Darkness pulse (screen goes nearly black) ---
	if darkness_active:
		var dark_strength: float = 0.85
		if darkness_timer < 0.3:
			dark_strength = darkness_timer / 0.3 * 0.85  # Fade in
		elif darkness_timer > DARKNESS_DURATION - 0.5:
			dark_strength = (DARKNESS_DURATION - darkness_timer) / 0.5 * 0.85  # Fade out
		draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0.0, 0.0, 0.02, dark_strength))
		# Players glow faintly during darkness
		draw_circle(p1, 35, Color(GameManager.get_blame_color_light(), 0.08))
		draw_circle(p2, 35, Color(GameManager.get_denial_color_light(), 0.08))

	# --- Charge glow when full ---
	if charge_full:
		var glow: float = sin(pulse_time * 4.0) * 0.15 + 0.3
		draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0.9, 0.8, 0.2, glow))

	# --- Phase indicator text ---
	if boss_phase >= 1:
		var warn_alpha: float = sin(pulse_time * 2.0) * 0.1 + 0.15
		var font := ThemeDB.fallback_font
		if boss_phase == 2:
			draw_string(font, Vector2(560, ARENA_TOP - 15), "GUILT ENRAGES", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.2, 0.2, warn_alpha))


func _on_dialogue_done() -> void:
	pass
