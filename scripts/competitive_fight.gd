extends Control

## Competitive Minigame 1 — Asymmetric Emotion-Based Fighter
## Blame: Heavy brawler (Guilt Slam, Accusation projectile, Burden Zone, Self-Punishment)
## Denial: Quick trickster (Suppress push, Deflect parry, Forget teleport, Bright Burst)
## Score = damage dealt. Shards break as visual feedback.

@onready var dialogue: Node = $DialogueSystem
@onready var timer_label: Label = $HUD/TimerLabel
@onready var p1_score_label: Label = $HUD/P1Score
@onready var p2_score_label: Label = $HUD/P2Score

# ─── Arena ─────────────────────────────────────────────────────────────────
const GRAVITY := 900.0
const JUMP_FORCE := -430.0
const GROUND_Y := 540.0
const PLATFORM_LEFT := 140.0
const PLATFORM_RIGHT := 1140.0
const CEILING := 60.0
const MATCH_TIME := 50.0

# ─── Players ───────────────────────────────────────────────────────────────
var p1_pos := Vector2(350, GROUND_Y)
var p1_vel := Vector2.ZERO
var p1_on_ground := true
var p1_facing := 1.0
var p1_damage := 0
var p1_hit_flash := 0.0
var p1_stun := 0.0
var p1_powered_up := false  # Self-Punishment buff active

var p2_pos := Vector2(930, GROUND_Y)
var p2_vel := Vector2.ZERO
var p2_on_ground := true
var p2_facing := -1.0
var p2_damage := 0
var p2_hit_flash := 0.0
var p2_stun := 0.0

# ─── Blame Abilities ──────────────────────────────────────────────────────
const BLAME_SPEED := 220.0  # Slower — heavy brawler

# Guilt Slam (Light Attack) — ground shockwave
var blame_slam_cd := 0.0
var blame_slam_anim := 0.0
const BLAME_SLAM_CD := 0.8
const BLAME_SLAM_RANGE := 350.0  # Shockwave travels this far
var blame_shockwave_active := false
var blame_shockwave_x := 0.0  # Current shockwave front position
var blame_shockwave_origin := 0.0
var blame_shockwave_dir := 1.0
const BLAME_SHOCKWAVE_SPEED := 600.0
const BLAME_SHOCKWAVE_HEIGHT := 50.0  # Must jump to avoid

# Accusation (Heavy Attack) — ranged projectile
var blame_accuse_cd := 0.0
const BLAME_ACCUSE_CD := 1.2
var blame_projectiles: Array[Dictionary] = []  # {pos, vel, size}
const BLAME_PROJ_SPEED := 450.0

# Burden Zone (Dodge) — slow field
var blame_burden_cd := 0.0
const BLAME_BURDEN_CD := 6.0
var burden_zones: Array[Dictionary] = []  # {pos, timer}
const BURDEN_DURATION := 4.5
const BURDEN_RADIUS := 80.0
const BURDEN_SLOW := 0.4  # 40% speed in zone

# Self-Punishment (Both buttons) — sacrifice score for power
var blame_punish_cd := 0.0
const BLAME_PUNISH_CD := 8.0
var blame_power_timer := 0.0
const BLAME_POWER_DURATION := 4.0

# ─── Denial Abilities ─────────────────────────────────────────────────────
const DENIAL_SPEED := 280.0  # Faster — trickster

# Suppress (Light Attack) — close-range push
var denial_suppress_cd := 0.0
var denial_suppress_anim := 0.0
const DENIAL_SUPPRESS_CD := 0.5
const DENIAL_SUPPRESS_RANGE := 90.0
const DENIAL_SUPPRESS_PUSH := 350.0

# Deflect (Heavy Attack) — parry window
var denial_deflect_cd := 0.0
var denial_deflect_active := 0.0  # Time remaining in parry window
const DENIAL_DEFLECT_CD := 1.5
const DENIAL_DEFLECT_WINDOW := 0.3
var denial_deflect_success := false  # Visual feedback

# Forget (Dodge) — teleport + decoy
var denial_forget_cd := 0.0
const DENIAL_FORGET_CD := 3.0
const DENIAL_FORGET_DIST := 170.0
var decoys: Array[Dictionary] = []  # {pos, timer}
const DECOY_DURATION := 2.0
const DECOY_STUN := 0.6

# Bright Burst (Both buttons) — AoE explosion
var denial_burst_cd := 0.0
const DENIAL_BURST_CD := 8.0
var denial_burst_anim := 0.0
const DENIAL_BURST_RADIUS := 160.0
const DENIAL_BURST_PUSH := 500.0

# ─── State ─────────────────────────────────────────────────────────────────
var match_timer := MATCH_TIME
var match_over := false
var blame_won := false
var phase: int = 0  # 0=countdown, 1=fighting, 2=unused, 3=advance
var countdown_timer := 3.5
var pulse_time := 0.0
var ambient_break_timer := 0.0

# ─── Fight dialogue ───────────────────────────────────────────────────────
var fight_dialogue_queue: Array[Dictionary] = []
var fight_dialogue_timer := 0.0
var fight_dialogue_index := -1
var fight_text_alpha := 0.0


func _ready() -> void:
	p1_score_label.add_theme_color_override("font_color", GameManager.get_blame_color_light())
	p2_score_label.add_theme_color_override("font_color", GameManager.get_denial_color_light())
	p1_score_label.text = "BLAME: 0"
	p2_score_label.text = "DENIAL: 0"

	fight_dialogue_queue = [
		{"speaker": "Blame", "text": "Why are you still here?", "color": GameManager.get_blame_color_light()},
		{"speaker": "Blame", "text": "Don't you remember what happened?", "color": GameManager.get_blame_color_light()},
		{"speaker": "Denial", "text": "None of it was my fault.", "color": GameManager.get_denial_color_light()},
		{"speaker": "Denial", "text": "I don't remember anything. Stop.", "color": GameManager.get_denial_color_light()},
	]
	phase = 0


func _process(delta: float) -> void:
	pulse_time += delta

	match phase:
		0:
			countdown_timer -= delta
			timer_label.text = str(ceili(countdown_timer))
			if countdown_timer <= 0:
				phase = 1
				fight_dialogue_timer = 3.0
		1: _process_fight(delta)
		3: GameManager.advance_phase()

	queue_redraw()


func _process_fight(delta: float) -> void:
	if match_over:
		return

	match_timer -= delta
	timer_label.text = str(ceili(match_timer))
	if match_timer <= 0:
		match_timer = 0
		_end_match()
		return

	# Decay timers
	p1_hit_flash = maxf(0.0, p1_hit_flash - delta * 4.0)
	p2_hit_flash = maxf(0.0, p2_hit_flash - delta * 4.0)
	p1_stun = maxf(0.0, p1_stun - delta)
	p2_stun = maxf(0.0, p2_stun - delta)
	blame_slam_anim = maxf(0.0, blame_slam_anim - delta * 3.0)
	denial_suppress_anim = maxf(0.0, denial_suppress_anim - delta * 4.0)
	denial_burst_anim = maxf(0.0, denial_burst_anim - delta * 2.5)
	denial_deflect_active = maxf(0.0, denial_deflect_active - delta)

	# Cooldowns
	blame_slam_cd = maxf(0.0, blame_slam_cd - delta)
	blame_accuse_cd = maxf(0.0, blame_accuse_cd - delta)
	blame_burden_cd = maxf(0.0, blame_burden_cd - delta)
	blame_punish_cd = maxf(0.0, blame_punish_cd - delta)
	denial_suppress_cd = maxf(0.0, denial_suppress_cd - delta)
	denial_deflect_cd = maxf(0.0, denial_deflect_cd - delta)
	denial_forget_cd = maxf(0.0, denial_forget_cd - delta)
	denial_burst_cd = maxf(0.0, denial_burst_cd - delta)

	# Power-up timer
	if p1_powered_up:
		blame_power_timer -= delta
		if blame_power_timer <= 0:
			p1_powered_up = false

	# Dialogue
	fight_dialogue_timer -= delta
	if fight_dialogue_timer <= 0 and fight_dialogue_index < fight_dialogue_queue.size() - 1:
		fight_dialogue_index += 1
		fight_text_alpha = 1.0
		fight_dialogue_timer = 6.0
	if fight_text_alpha > 0:
		fight_text_alpha -= delta * 0.12

	# Ambient shard breaking
	ambient_break_timer -= delta
	if ambient_break_timer <= 0:
		ambient_break_timer = 1.0
		GameManager.break_random_shards(1)

	_move_blame(delta)
	_move_denial(delta)
	_process_blame_abilities(delta)
	_process_denial_abilities(delta)
	_update_projectiles(delta)
	_update_burden_zones(delta)
	_update_decoys(delta)
	_update_shockwave(delta)

	# Hue
	var total: float = float(p1_damage + p2_damage)
	if total > 0:
		GameManager.set_hue(lerpf(GameManager.hue_value, float(p2_damage) / total, 3.0 * delta))

	p1_score_label.text = "BLAME: " + str(p1_damage)
	p2_score_label.text = "DENIAL: " + str(p2_damage)


# ═══ MOVEMENT ═══════════════════════════════════════════════════════════════

func _move_blame(delta: float) -> void:
	if p1_stun > 0:
		p1_vel.x = lerpf(p1_vel.x, 0.0, 5.0 * delta)
	else:
		var dir := 0.0
		if Input.is_action_pressed("p1_left"): dir -= 1.0
		if Input.is_action_pressed("p1_right"): dir += 1.0
		if dir != 0.0: p1_facing = dir
		# Check if in opponent's burden zone (Blame is immune to own zones)
		var speed: float = BLAME_SPEED
		p1_vel.x = lerpf(p1_vel.x, dir * speed, 10.0 * delta)

	if p1_on_ground and p1_stun <= 0 and Input.is_action_just_pressed("p1_up"):
		p1_vel.y = JUMP_FORCE
		p1_on_ground = false

	p1_vel.y += GRAVITY * delta
	p1_pos += p1_vel * delta
	if p1_pos.y >= GROUND_Y:
		p1_pos.y = GROUND_Y
		p1_vel.y = 0.0
		p1_on_ground = true
	p1_pos.y = maxf(p1_pos.y, CEILING)
	p1_pos.x = clampf(p1_pos.x, PLATFORM_LEFT, PLATFORM_RIGHT)


func _move_denial(delta: float) -> void:
	if p2_stun > 0:
		p2_vel.x = lerpf(p2_vel.x, 0.0, 5.0 * delta)
	else:
		var dir := 0.0
		if Input.is_action_pressed("p2_left"): dir -= 1.0
		if Input.is_action_pressed("p2_right"): dir += 1.0
		if dir != 0.0: p2_facing = dir
		# Check if in Blame's burden zone
		var speed: float = DENIAL_SPEED
		for zone: Dictionary in burden_zones:
			if p2_pos.distance_to(zone.pos as Vector2) < BURDEN_RADIUS:
				speed *= BURDEN_SLOW
				break
		p2_vel.x = lerpf(p2_vel.x, dir * speed, 10.0 * delta)

	if p2_on_ground and p2_stun <= 0 and Input.is_action_just_pressed("p2_up"):
		p2_vel.y = JUMP_FORCE
		p2_on_ground = false

	p2_vel.y += GRAVITY * delta
	p2_pos += p2_vel * delta
	if p2_pos.y >= GROUND_Y:
		p2_pos.y = GROUND_Y
		p2_vel.y = 0.0
		p2_on_ground = true
	p2_pos.y = maxf(p2_pos.y, CEILING)
	p2_pos.x = clampf(p2_pos.x, PLATFORM_LEFT, PLATFORM_RIGHT)


# ═══ BLAME ABILITIES ═══════════════════════════════════════════════════════

func _process_blame_abilities(_delta: float) -> void:
	if p1_stun > 0:
		return

	var dmg_mult: float = 2.0 if p1_powered_up else 1.0

	# Guilt Slam (Light Attack) — ground shockwave
	if Input.is_action_just_pressed("p1_attack") and blame_slam_cd <= 0:
		blame_slam_cd = BLAME_SLAM_CD
		blame_slam_anim = 1.0
		blame_shockwave_active = true
		blame_shockwave_origin = p1_pos.x
		blame_shockwave_x = p1_pos.x
		blame_shockwave_dir = p1_facing
		GameManager.break_shards_near(p1_pos, 80.0, 1)

	# Accusation (Heavy Attack) — ranged projectile
	if Input.is_action_just_pressed("p1_heavy") and blame_accuse_cd <= 0:
		blame_accuse_cd = BLAME_ACCUSE_CD
		var proj_vel := Vector2(BLAME_PROJ_SPEED * p1_facing, 0)
		var size: float = 10.0 if not p1_powered_up else 16.0
		blame_projectiles.append({"pos": Vector2(p1_pos.x + p1_facing * 25, p1_pos.y - 20), "vel": proj_vel, "size": size, "dmg": dmg_mult})

	# Burden Zone (Dodge button) — slow field
	if Input.is_action_just_pressed("p1_dodge") and blame_burden_cd <= 0:
		blame_burden_cd = BLAME_BURDEN_CD
		burden_zones.append({"pos": Vector2(p1_pos.x, GROUND_Y), "timer": BURDEN_DURATION})
		GameManager.break_shards_near(p1_pos, 60.0, 1)

	# Self-Punishment (Both attack buttons) — sacrifice for power
	if Input.is_action_pressed("p1_attack") and Input.is_action_just_pressed("p1_heavy") and blame_punish_cd <= 0:
		if p1_damage >= 2:
			blame_punish_cd = BLAME_PUNISH_CD
			p1_damage -= 2
			p1_powered_up = true
			blame_power_timer = BLAME_POWER_DURATION
			p1_hit_flash = 0.5  # Brief flash to show self-harm


# ═══ DENIAL ABILITIES ══════════════════════════════════════════════════════

func _process_denial_abilities(_delta: float) -> void:
	if p2_stun > 0:
		return

	# Suppress (Light Attack) — close-range push
	if Input.is_action_just_pressed("p2_attack") and denial_suppress_cd <= 0:
		denial_suppress_cd = DENIAL_SUPPRESS_CD
		denial_suppress_anim = 1.0
		if p2_pos.distance_to(p1_pos) < DENIAL_SUPPRESS_RANGE and p1_stun <= 0:
			var push_dir: float = signf(p1_pos.x - p2_pos.x)
			if push_dir == 0: push_dir = p2_facing
			p1_vel.x = push_dir * DENIAL_SUPPRESS_PUSH
			p1_vel.y = -120.0
			p2_damage += 1
			p1_hit_flash = 0.5
			GameManager.break_shards_near(p1_pos, 70.0, 2)

	# Deflect (Heavy Attack) — parry window
	if Input.is_action_just_pressed("p2_heavy") and denial_deflect_cd <= 0:
		denial_deflect_cd = DENIAL_DEFLECT_CD
		denial_deflect_active = DENIAL_DEFLECT_WINDOW
		denial_deflect_success = false

	# Forget (Dodge) — teleport + decoy
	if Input.is_action_just_pressed("p2_dodge") and denial_forget_cd <= 0:
		denial_forget_cd = DENIAL_FORGET_CD
		var old_pos := Vector2(p2_pos.x, p2_pos.y)
		p2_pos.x += p2_facing * DENIAL_FORGET_DIST
		p2_pos.x = clampf(p2_pos.x, PLATFORM_LEFT, PLATFORM_RIGHT)
		decoys.append({"pos": old_pos, "timer": DECOY_DURATION})

	# Bright Burst (Both buttons) — AoE explosion
	if Input.is_action_pressed("p2_attack") and Input.is_action_just_pressed("p2_heavy") and denial_burst_cd <= 0:
		if p2_damage >= 2:
			denial_burst_cd = DENIAL_BURST_CD
			p2_damage -= 2
			denial_burst_anim = 1.0
			GameManager.break_shards_near(p2_pos, DENIAL_BURST_RADIUS, 2)
			# Push Blame away if in range
			if p1_pos.distance_to(p2_pos) < DENIAL_BURST_RADIUS:
				var push_dir := (p1_pos - p2_pos).normalized()
				p1_vel = push_dir * DENIAL_BURST_PUSH
				p1_vel.y = minf(p1_vel.y, -200.0)
				p1_on_ground = false
				p1_stun = 0.5
				p1_hit_flash = 1.0
				p2_damage += 3


# ═══ UPDATE SYSTEMS ════════════════════════════════════════════════════════

func _update_shockwave(delta: float) -> void:
	if not blame_shockwave_active:
		return
	blame_shockwave_x += blame_shockwave_dir * BLAME_SHOCKWAVE_SPEED * delta
	var dist_traveled: float = absf(blame_shockwave_x - blame_shockwave_origin)

	# Hit Denial if she's on the ground and shockwave passes through
	if p2_on_ground and p2_stun <= 0 and denial_deflect_active <= 0:
		if absf(p2_pos.x - blame_shockwave_x) < 40.0:
			var dmg: int = 2 if p1_powered_up else 1
			p2_hit_flash = 1.0
			p2_vel.y = -300.0
			p2_on_ground = false
			p2_stun = 0.4
			p1_damage += dmg
			GameManager.break_shards_near(p2_pos, 90.0, 1)
	elif denial_deflect_active > 0 and absf(p2_pos.x - blame_shockwave_x) < 50.0:
		# Deflected! Stun Blame
		blame_shockwave_active = false
		denial_deflect_success = true
		denial_deflect_active = 0.0
		p1_stun = 0.7
		p1_hit_flash = 1.0
		p2_damage += 2
		return

	if dist_traveled > BLAME_SLAM_RANGE:
		blame_shockwave_active = false


func _update_projectiles(delta: float) -> void:
	for i in range(blame_projectiles.size() - 1, -1, -1):
		var proj: Dictionary = blame_projectiles[i]
		proj.pos = (proj.pos as Vector2) + (proj.vel as Vector2) * delta
		var pp: Vector2 = proj.pos as Vector2

		# Hit Denial?
		if pp.distance_to(p2_pos) < (proj.size as float) + 20.0 and p2_stun <= 0:
			if denial_deflect_active > 0:
				# Deflected! Reverse projectile direction and stun Blame
				denial_deflect_success = true
				denial_deflect_active = 0.0
				p1_stun = 0.7
				p1_hit_flash = 1.0
				p2_damage += 2
				blame_projectiles.remove_at(i)
				continue
			var dmg: int = (int(proj.dmg as float) + 1)
			p2_hit_flash = 1.0
			p2_stun = 0.3
			p2_vel.x = sign(pp.x - p1_pos.x) * 200.0
			p1_damage += dmg
			GameManager.break_shards_near(pp, 70.0, 1)
			blame_projectiles.remove_at(i)
			continue

		# Hit decoy?
		var hit_decoy := false
		for decoy: Dictionary in decoys:
			if pp.distance_to(decoy.pos as Vector2) < 30.0:
				hit_decoy = true
				p1_stun = DECOY_STUN
				p1_hit_flash = 0.8
				decoy.timer = 0.0  # Remove decoy
				break
		if hit_decoy:
			blame_projectiles.remove_at(i)
			continue

		if pp.x < -50 or pp.x > 1330:
			blame_projectiles.remove_at(i)


func _update_burden_zones(delta: float) -> void:
	for i in range(burden_zones.size() - 1, -1, -1):
		var zone: Dictionary = burden_zones[i]
		zone.timer = (zone.timer as float) - delta
		if (zone.timer as float) <= 0:
			burden_zones.remove_at(i)


func _update_decoys(delta: float) -> void:
	for i in range(decoys.size() - 1, -1, -1):
		var decoy: Dictionary = decoys[i]
		decoy.timer = (decoy.timer as float) - delta
		if (decoy.timer as float) <= 0:
			decoys.remove_at(i)

	# Blame hitting a decoy in melee
	for decoy: Dictionary in decoys:
		if p1_pos.distance_to(decoy.pos as Vector2) < 50.0 and blame_slam_anim > 0.5:
			p1_stun = DECOY_STUN
			p1_hit_flash = 0.8
			decoy.timer = 0.0


# ═══ DRAWING ═══════════════════════════════════════════════════════════════

func _draw() -> void:
	# ── Platform ──────────────────────────────────────────────────────
	draw_rect(Rect2(PLATFORM_LEFT - 20, GROUND_Y, PLATFORM_RIGHT - PLATFORM_LEFT + 40, 12),
		Color(0.25, 0.25, 0.3, 0.9))
	draw_line(Vector2(PLATFORM_LEFT - 20, GROUND_Y), Vector2(PLATFORM_RIGHT + 20, GROUND_Y),
		Color(0.4, 0.4, 0.48, 0.6), 2.0)

	# ── Burden Zones ──────────────────────────────────────────────────
	for zone: Dictionary in burden_zones:
		var zp: Vector2 = zone.pos as Vector2
		var life: float = (zone.timer as float) / BURDEN_DURATION
		var za: float = life * 0.25
		draw_circle(zp, BURDEN_RADIUS, Color(0.15, 0.1, 0.2, za))
		draw_arc(zp, BURDEN_RADIUS, 0, TAU, 24, Color(0.3, 0.15, 0.35, za + 0.1), 2.0)
		# Slow symbol
		draw_string(ThemeDB.fallback_font, zp + Vector2(-8, 4), "~", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.5, 0.3, 0.5, za + 0.15))

	# ── Shockwave ─────────────────────────────────────────────────────
	if blame_shockwave_active:
		var sw_y: float = GROUND_Y - 5
		var sw_col := Color(0.3, 0.35, 0.7, 0.6)
		if p1_powered_up:
			sw_col = Color(0.5, 0.3, 0.8, 0.7)
		# Draw shockwave as a series of lines at the wave front
		for i in range(5):
			var offset: float = float(i) * 8.0
			var x: float = blame_shockwave_x - blame_shockwave_dir * offset
			var h: float = BLAME_SHOCKWAVE_HEIGHT * (1.0 - float(i) / 5.0)
			draw_line(Vector2(x, sw_y), Vector2(x, sw_y - h), sw_col, 3.0 - float(i) * 0.4)

	# ── Projectiles ───────────────────────────────────────────────────
	for proj: Dictionary in blame_projectiles:
		var pp: Vector2 = proj.pos as Vector2
		var sz: float = proj.size as float
		draw_circle(pp, sz, Color(0.3, 0.35, 0.75, 0.8))
		draw_circle(pp, sz * 0.5, Color(0.5, 0.55, 0.9, 0.5))
		# Trail
		draw_line(pp, pp - (proj.vel as Vector2).normalized() * 20.0, Color(0.3, 0.35, 0.7, 0.3), 2.0)

	# ── Decoys ────────────────────────────────────────────────────────
	for decoy: Dictionary in decoys:
		var dp: Vector2 = decoy.pos as Vector2
		var da: float = clampf((decoy.timer as float) / DECOY_DURATION, 0.0, 1.0) * 0.5
		# Ghost of Denial
		draw_circle(dp, 20, Color(GameManager.get_denial_color(), da))
		draw_circle(dp, 12, Color(GameManager.get_denial_color_light(), da * 0.5))

	# ── Denial Deflect Shield ─────────────────────────────────────────
	if denial_deflect_active > 0:
		var shield_a: float = denial_deflect_active / DENIAL_DEFLECT_WINDOW
		var shield_col := Color(0.9, 0.7, 0.3, shield_a * 0.5)
		draw_arc(p2_pos, 35, -PI * 0.5 - 0.8, -PI * 0.5 + 0.8, 16, shield_col, 4.0)
		if denial_deflect_success:
			draw_circle(p2_pos, 40, Color(1.0, 0.9, 0.3, shield_a * 0.3))

	# ── Denial Burst AoE ──────────────────────────────────────────────
	if denial_burst_anim > 0:
		var burst_r: float = DENIAL_BURST_RADIUS * (1.0 - denial_burst_anim * 0.3)
		draw_circle(p2_pos, burst_r, Color(0.95, 0.65, 0.3, denial_burst_anim * 0.2))
		draw_arc(p2_pos, burst_r, 0, TAU, 32, Color(1.0, 0.8, 0.4, denial_burst_anim * 0.5), 3.0)

	# ── Blame Power-Up Glow ───────────────────────────────────────────
	if p1_powered_up:
		var glow_a: float = 0.15 + sin(pulse_time * 5.0) * 0.08
		draw_circle(p1_pos, 40, Color(0.4, 0.3, 0.7, glow_a))

	# ── P1 Blame (rectangles — heavy) ─────────────────────────────────
	var bc := GameManager.get_blame_color()
	var bcl := GameManager.get_blame_color_light()
	if p1_hit_flash > 0:
		bc = bc.lerp(Color.WHITE, p1_hit_flash * 0.6)
	if p1_stun > 0:
		bc.a = 0.5
	if p1_powered_up:
		bc = bc.lerp(Color(0.5, 0.3, 0.8), 0.3)

	# Body
	draw_rect(Rect2(p1_pos.x - 16, p1_pos.y - 55, 32, 36), bc)
	draw_rect(Rect2(p1_pos.x - 10, p1_pos.y - 49, 20, 24), Color(bcl.r, bcl.g, bcl.b, 0.25))
	# Head
	draw_rect(Rect2(p1_pos.x - 12, p1_pos.y - 72, 24, 19), bc)
	# Eyes
	draw_rect(Rect2(p1_pos.x + p1_facing * 3 - 6, p1_pos.y - 67, 4, 4), Color(0.7, 0.75, 0.9, 0.8))
	draw_rect(Rect2(p1_pos.x + p1_facing * 3 + 2, p1_pos.y - 67, 4, 4), Color(0.7, 0.75, 0.9, 0.8))
	# Legs
	draw_rect(Rect2(p1_pos.x - 12, p1_pos.y - 22, 9, 22), bc)
	draw_rect(Rect2(p1_pos.x + 3, p1_pos.y - 22, 9, 22), bc)
	# Slam arm animation
	if blame_slam_anim > 0:
		var arm_y: float = p1_pos.y - 45 + blame_slam_anim * 15.0
		draw_rect(Rect2(p1_pos.x + p1_facing * 16, arm_y, p1_facing * 25, 10), bcl)

	# ── P2 Denial (circles — quick) ───────────────────────────────────
	var dc := GameManager.get_denial_color()
	var dcl := GameManager.get_denial_color_light()
	if p2_hit_flash > 0:
		dc = dc.lerp(Color.WHITE, p2_hit_flash * 0.6)
	if p2_stun > 0:
		dc.a = 0.5

	# Body
	draw_circle(Vector2(p2_pos.x, p2_pos.y - 38), 18, dc)
	draw_circle(Vector2(p2_pos.x, p2_pos.y - 38), 11, Color(dcl.r, dcl.g, dcl.b, 0.25))
	# Head
	draw_circle(Vector2(p2_pos.x, p2_pos.y - 63), 13, dc)
	# Eyes
	draw_circle(Vector2(p2_pos.x + p2_facing * 4 - 4, p2_pos.y - 65), 2.5, Color(0.95, 0.85, 0.7, 0.8))
	draw_circle(Vector2(p2_pos.x + p2_facing * 4 + 4, p2_pos.y - 65), 2.5, Color(0.95, 0.85, 0.7, 0.8))
	# Legs
	draw_circle(Vector2(p2_pos.x - 7, p2_pos.y - 8), 6, dc)
	draw_circle(Vector2(p2_pos.x + 7, p2_pos.y - 8), 6, dc)
	draw_circle(Vector2(p2_pos.x - 7, p2_pos.y - 18), 5, dc)
	draw_circle(Vector2(p2_pos.x + 7, p2_pos.y - 18), 5, dc)
	# Suppress push animation
	if denial_suppress_anim > 0:
		var push_r: float = 30.0 + (1.0 - denial_suppress_anim) * 40.0
		draw_arc(p2_pos + Vector2(p2_facing * 20, -30), push_r, -0.6, 0.6, 12, Color(dcl.r, dcl.g, dcl.b, denial_suppress_anim * 0.4), 3.0)

	# ── Dialogue ──────────────────────────────────────────────────────
	if fight_text_alpha > 0 and fight_dialogue_index >= 0:
		var fd: Dictionary = fight_dialogue_queue[fight_dialogue_index]
		var text_col: Color = fd.color
		text_col.a = fight_text_alpha
		var font := ThemeDB.fallback_font
		var text_str: String = fd.speaker + ": \"" + fd.text + "\""
		var tw: float = font.get_string_size(text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string(font, Vector2(640 - tw * 0.5, 45), text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, text_col)

	# ── Controls overlay during countdown ─────────────────────────────
	if phase == 0:
		var ca: float = 0.7 + sin(countdown_timer * 3.0) * 0.15
		var font := ThemeDB.fallback_font
		var cc := Color(0.7, 0.7, 0.8, ca)
		# P1 Blame abilities
		draw_string(font, Vector2(80, 180), "BLAME — The Weight", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(GameManager.get_blame_color_light(), ca))
		draw_string(font, Vector2(80, 208), "Move: WASD / Stick", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, cc)
		draw_string(font, Vector2(80, 226), "Guilt Slam: F / X (ground shockwave)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, cc)
		draw_string(font, Vector2(80, 244), "Accusation: G / Y (projectile)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, cc)
		draw_string(font, Vector2(80, 262), "Burden Zone: R / B (slow field)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, cc)
		draw_string(font, Vector2(80, 280), "Self-Punishment: F+G (sacrifice 2pts, power up)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.5, 0.8, ca))

		# P2 Denial abilities
		draw_string(font, Vector2(720, 180), "DENIAL — The Escape", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(GameManager.get_denial_color_light(), ca))
		draw_string(font, Vector2(720, 208), "Move: Arrows / Stick", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, cc)
		draw_string(font, Vector2(720, 226), "Suppress: Enter / X (push away)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, cc)
		draw_string(font, Vector2(720, 244), "Deflect: RShift / Y (parry, reflects!)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, cc)
		draw_string(font, Vector2(720, 262), "Forget: Num0 / B (teleport + decoy)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, cc)
		draw_string(font, Vector2(720, 280), "Bright Burst: Enter+RShift (AoE, costs 2pts)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.7, 0.4, ca))


func _end_match() -> void:
	match_over = true
	if p1_damage > p2_damage:
		blame_won = true
	elif p2_damage > p1_damage:
		blame_won = false
	else:
		blame_won = randf() > 0.5

	GameManager.register_competitive_win(blame_won)
	phase = 3
