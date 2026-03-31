extends Control

## Competitive Minigame 1 — Asymmetric Emotion-Based Fighter
## Blame: Heavy brawler (Guilt Slam, Accusation projectile, Burden Zone, Self-Punishment)
## Denial: Quick trickster (Suppress push, Deflect parry, Forget teleport, Bright Burst)
## Score = damage dealt. Shards break as visual feedback.

@onready var dialogue: Node = $DialogueSystem
@onready var timer_label: Label = $HUD/TimerLabel
@onready var p1_score_label: Label = $HUD/P1Score
@onready var p2_score_label: Label = $HUD/P2Score

# ─── Sprite assets ─────────────────────────────────────────────────────────
var golem_sheet: Texture2D    # Blame character
var rogue_sheet: Texture2D    # Denial character
var thunder_strike_sheet: Texture2D  # Guilt Slam VFX
var dark_vfx_sheet: Texture2D        # Burden Zone / Self-Punishment
var holy_impact_sheet: Texture2D     # Deflect parry VFX
var firebolt_sheet: Texture2D        # Accusation projectile
var fire_hit_sheet: Texture2D        # Bright Burst
var smear_sheet: Texture2D           # Suppress slash
var thrust_sheet: Texture2D          # Hit impact
var battle_fx_sheet: Texture2D       # Generic hit sparks

# Frame sizes (calculated from sheet dimensions)
# Golem: 1000x1000, 10 cols x 10 rows = 100x100
# Rogue: 500x444, ~10 cols x 8 rows = 50x55
const GOLEM_FW := 100
const GOLEM_FH := 100
const ROGUE_FW := 50
const ROGUE_FH := 37

# ─── Arena ─────────────────────────────────────────────────────────────────
const GRAVITY := 1100.0
const JUMP_FORCE := -520.0    # Reaches ~457px from ground — can land on platforms
const GROUND_Y := 580.0
const PLATFORM_LEFT := 140.0
const PLATFORM_RIGHT := 1140.0
const CEILING := 60.0
const MATCH_TIME := 110.0
# Floating platform collision rects (drawn + collided)
const PLATFORMS: Array[Rect2] = [
	Rect2(280, 460, 180, 10),   # Left platform
	Rect2(820, 460, 180, 10),   # Right platform
	Rect2(520, 360, 240, 10),   # Center high platform
]

# ─── Players ───────────────────────────────────────────────────────────────
var p1_pos := Vector2(350, 580.0)
var p1_vel := Vector2.ZERO
var p1_on_ground := true
var p1_facing := 1.0
var p1_damage := 0
var p1_hit_flash := 0.0
var p1_stun := 0.0
var p1_powered_up := false  # Self-Punishment buff active

var p2_pos := Vector2(930, 580.0)
var p2_vel := Vector2.ZERO
var p2_on_ground := true
var p2_facing := -1.0
var p2_damage := 0
var p2_hit_flash := 0.0
var p2_stun := 0.0

# ─── Blame Abilities ──────────────────────────────────────────────────────
const BLAME_SPEED := 240.0  # Slightly slow — heavy brawler

# Basic Punch — close range melee (both players have this)
const PUNCH_RANGE := 70.0
const PUNCH_DAMAGE := 1
const PUNCH_KNOCKBACK := 200.0

# Guilt Slam (Light Attack) — ground shockwave + melee punch
var blame_slam_cd := 0.0
var blame_slam_anim := 0.0
const BLAME_SLAM_CD := 0.6  # Faster cooldown
const BLAME_SLAM_RANGE := 400.0  # Shockwave travels further
var blame_shockwave_active := false
var blame_shockwave_x := 0.0  # Current shockwave front position
var blame_shockwave_origin := 0.0
var blame_shockwave_dir := 1.0
const BLAME_SHOCKWAVE_SPEED := 600.0
const BLAME_SHOCKWAVE_HEIGHT := 50.0  # Must jump to avoid

# Accusation (Heavy Attack) — ranged projectile
var blame_accuse_cd := 0.0
const BLAME_ACCUSE_CD := 0.9  # Faster projectiles
var blame_projectiles: Array[Dictionary] = []
const BLAME_PROJ_SPEED := 500.0  # Faster speed

# Burden Zone (Dodge) — slow field
var blame_burden_cd := 0.0
const BLAME_BURDEN_CD := 5.0  # Slightly shorter cooldown
var burden_zones: Array[Dictionary] = []
const BURDEN_DURATION := 5.0  # Lasts longer
const BURDEN_RADIUS := 100.0  # Bigger area
const BURDEN_SLOW := 0.35  # Even slower (35% speed)

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
var phase: int = 0  # 0=instructions, 1=fighting, 2=unused, 3=advance
var countdown_timer := 3.5
var waiting_for_start := true  # wait for space/X to begin
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

	# Load sprite assets
	golem_sheet = _load_tex("res://assets/blame_golem/Mecha-stone Golem 0.1/PNG sheet/Character_sheet.png")
	rogue_sheet = _load_tex("res://assets/Fullmain.png")
	thunder_strike_sheet = _load_tex("res://assets/Thunder Effect 02/Thunder Effect 02/Thunder Strike/Thunderstrike w blur.png")
	dark_vfx_sheet = _load_tex("res://assets/Dark VFX 01 - 02/Dark VFX 1/Dark VFX 1 (40x32).png")
	holy_impact_sheet = _load_tex("res://assets/Holy VFX 01-02/Holy VFX 01/Holy VFX 01 Impact.png")
	firebolt_sheet = _load_tex("res://assets/Fire Effect 1/Fire Effect 1/Firebolt SpriteSheet.png")
	fire_hit_sheet = _load_tex("res://assets/Fire Effect 1/Fire Effect 1/Fire Breath hit effect SpriteSheet.png")
	smear_sheet = _load_tex("res://assets/Smear VFX 01/Smear VFX 01/Smear 01 Horizontal 1.png")
	thrust_sheet = _load_tex("res://assets/Thrust/Thrusts 1 SpriteSheet.png")
	battle_fx_sheet = _load_tex("res://assets/Effects/Effect 1 - Sprite Sheet.png")

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
			if waiting_for_start:
				timer_label.text = ""
				if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("p1_attack") or Input.is_action_just_pressed("p2_attack"):
					waiting_for_start = false
					countdown_timer = 3.5
			else:
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

	var prev_y1: float = p1_pos.y
	p1_vel.y += GRAVITY * delta
	p1_pos += p1_vel * delta
	p1_on_ground = false
	if p1_pos.y >= GROUND_Y:
		p1_pos.y = GROUND_Y
		p1_vel.y = 0.0
		p1_on_ground = true
	elif p1_vel.y > 0:
		_check_platform_land(prev_y1, true)
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

	var prev_y2: float = p2_pos.y
	p2_vel.y += GRAVITY * delta
	p2_pos += p2_vel * delta
	p2_on_ground = false
	if p2_pos.y >= GROUND_Y:
		p2_pos.y = GROUND_Y
		p2_vel.y = 0.0
		p2_on_ground = true
	elif p2_vel.y > 0:
		_check_platform_land(prev_y2, false)
	p2_pos.y = maxf(p2_pos.y, CEILING)
	p2_pos.x = clampf(p2_pos.x, PLATFORM_LEFT, PLATFORM_RIGHT)


# ═══ BLAME ABILITIES ═══════════════════════════════════════════════════════

func _process_blame_abilities(_delta: float) -> void:
	if p1_stun > 0:
		return

	var dmg_mult: float = 2.0 if p1_powered_up else 1.0

	# Guilt Slam (Light Attack) — melee punch + ground shockwave
	if Input.is_action_just_pressed("p1_attack") and blame_slam_cd <= 0:
		blame_slam_cd = BLAME_SLAM_CD
		blame_slam_anim = 1.0
		# Melee punch if close enough
		if p1_pos.distance_to(p2_pos) < PUNCH_RANGE and p2_stun <= 0 and denial_deflect_active <= 0:
			var punch_dmg: int = PUNCH_DAMAGE * (2 if p1_powered_up else 1)
			p1_damage += punch_dmg
			p2_hit_flash = 0.6
			p2_vel.x = p1_facing * PUNCH_KNOCKBACK
			p2_vel.y = -100.0
			p2_stun = 0.2
			_spawn_sparks(p2_pos, Vector2(p1_facing, -0.5), GameManager.get_blame_color_light(), 8)
			_spawn_score_popup(p2_pos, "+" + str(punch_dmg), GameManager.get_blame_color_light())
			screen_shake = 0.25
		# Shockwave always fires
		blame_shockwave_active = true
		blame_shockwave_origin = p1_pos.x
		blame_shockwave_x = p1_pos.x
		blame_shockwave_dir = p1_facing
		GameManager.break_shards_near(p1_pos, 90.0, 1)

	# Accusation (Heavy Attack) — ranged projectile
	if Input.is_action_just_pressed("p1_heavy") and blame_accuse_cd <= 0:
		blame_accuse_cd = BLAME_ACCUSE_CD
		var proj_vel := Vector2(BLAME_PROJ_SPEED * p1_facing, 0)
		var proj_size: float = 10.0 if not p1_powered_up else 16.0
		blame_projectiles.append({"pos": Vector2(p1_pos.x + p1_facing * 25, p1_pos.y - 20), "vel": proj_vel, "size": proj_size, "dmg": dmg_mult})

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

	# Suppress (Light Attack) — close-range push + melee punch
	if Input.is_action_just_pressed("p2_attack") and denial_suppress_cd <= 0:
		denial_suppress_cd = DENIAL_SUPPRESS_CD
		denial_suppress_anim = 1.0
		if p2_pos.distance_to(p1_pos) < DENIAL_SUPPRESS_RANGE and p1_stun <= 0:
			if denial_deflect_active > 0:
				pass  # Don't push during deflect window
			else:
				var push_dir: float = signf(p1_pos.x - p2_pos.x)
				if push_dir == 0: push_dir = p2_facing
				p1_vel.x = push_dir * DENIAL_SUPPRESS_PUSH
				p1_vel.y = -120.0
				# Extra damage if very close (melee range)
				var dmg: int = 2 if p2_pos.distance_to(p1_pos) < PUNCH_RANGE else 1
				p2_damage += dmg
				p1_hit_flash = 0.6
				p1_stun = 0.15
				GameManager.break_shards_near(p1_pos, 70.0, 2)
				_spawn_sparks(p1_pos, Vector2(push_dir, -0.3), GameManager.get_denial_color_light(), 10)
				_spawn_score_popup(p1_pos, "+" + str(dmg), GameManager.get_denial_color_light())
				screen_shake = 0.2

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
				_spawn_vfx(p1_pos, Color(1.0, 0.7, 0.3), 20, 250.0, 5.0)
				_spawn_score_popup(p1_pos, "+3", GameManager.get_denial_color_light())
				screen_shake = 0.6


# ═══ UPDATE SYSTEMS ════════════════════════════════════════════════════════

func _update_shockwave(delta: float) -> void:
	if not blame_shockwave_active:
		return
	blame_shockwave_x += blame_shockwave_dir * BLAME_SHOCKWAVE_SPEED * delta
	var dist_traveled: float = absf(blame_shockwave_x - blame_shockwave_origin)

	# Hit Denial if she's on the ground and shockwave passes through
	if p2_on_ground and p2_stun <= 0 and denial_deflect_active <= 0:
		if absf(p2_pos.x - blame_shockwave_x) < 40.0:
			var dmg: int = 3 if p1_powered_up else 2
			p2_hit_flash = 1.0
			p2_vel.y = -350.0
			p2_on_ground = false
			p2_stun = 0.5
			p1_damage += dmg
			_spawn_vfx(p2_pos, GameManager.get_blame_color_light(), 12, 200.0, 4.0)
			_spawn_score_popup(p2_pos, "+" + str(dmg), GameManager.get_blame_color_light())
			screen_shake = 0.4
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
			continue
		# Knockback: push denial outward when inside the zone
		var zp: Vector2 = zone.pos as Vector2
		var dist: float = p2_pos.distance_to(zp)
		if dist < BURDEN_RADIUS and dist > 1.0:
			var push_dir: float = signf(p2_pos.x - zp.x)
			if absf(push_dir) < 0.1: push_dir = p2_facing
			p2_vel.x += push_dir * 400.0 * delta  # Constant outward push


func _check_platform_land(prev_y: float, is_p1: bool) -> void:
	var pos: Vector2 = p1_pos if is_p1 else p2_pos
	for plat: Rect2 in PLATFORMS:
		var plat_top: float = plat.position.y
		# Within horizontal bounds?
		if pos.x > plat.position.x and pos.x < plat.position.x + plat.size.x:
			# Was above platform last frame, now at or below it?
			if prev_y <= plat_top and pos.y >= plat_top:
				if is_p1:
					p1_pos.y = plat_top
					p1_vel.y = 0.0
					p1_on_ground = true
				else:
					p2_pos.y = plat_top
					p2_vel.y = 0.0
					p2_on_ground = true
				return


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


# ═══ VFX PARTICLES ═════════════════════════════════════════════════════════

var vfx: Array[Dictionary] = []  # {pos, vel, color, life, max_life, size, type}
var score_popups: Array[Dictionary] = []  # {pos, text, color, life}
var screen_shake := 0.0


func _spawn_vfx(pos: Vector2, col: Color, count: int, spread: float = 150.0, sz: float = 3.0) -> void:
	for _i in range(count):
		var angle: float = randf() * TAU
		var spd: float = randf_range(30.0, spread)
		vfx.append({"pos": pos, "vel": Vector2(cos(angle), sin(angle)) * spd,
			"color": col, "life": 0.6, "max_life": 0.6, "size": randf_range(sz * 0.5, sz * 1.5), "type": 0})


func _spawn_sparks(pos: Vector2, dir: Vector2, col: Color, count: int) -> void:
	for _i in range(count):
		var spread_angle: float = randf_range(-0.5, 0.5)
		var spd: float = randf_range(100, 300)
		vfx.append({"pos": pos, "vel": dir.rotated(spread_angle) * spd,
			"color": col, "life": 0.4, "max_life": 0.4, "size": randf_range(1.5, 3.5), "type": 1})


func _spawn_score_popup(pos: Vector2, text: String, col: Color) -> void:
	score_popups.append({"pos": pos + Vector2(0, -30), "text": text, "color": col, "life": 1.0})


func _update_vfx(delta: float) -> void:
	screen_shake = maxf(0.0, screen_shake - delta * 5.0)

	for i in range(vfx.size() - 1, -1, -1):
		var p: Dictionary = vfx[i]
		p["life"] = float(p["life"]) - delta
		if float(p["life"]) <= 0.0:
			vfx.remove_at(i)
		else:
			p["pos"] = Vector2(p["pos"]) + Vector2(p["vel"]) * delta
			p["vel"] = Vector2(p["vel"]) * 0.92

	for i in range(score_popups.size() - 1, -1, -1):
		var p: Dictionary = score_popups[i]
		p["life"] = float(p["life"]) - delta
		p["pos"] = Vector2(p["pos"]) + Vector2(0, -40) * delta
		if float(p["life"]) <= 0.0:
			score_popups.remove_at(i)


# ═══ DRAWING ═══════════════════════════════════════════════════════════════

func _draw() -> void:
	_update_vfx(get_process_delta_time())
	var shake := Vector2.ZERO
	if screen_shake > 0:
		shake = Vector2(randf_range(-2, 2), randf_range(-2, 2)) * screen_shake * 5.0

	# ── Arena: multi-level platforms ──────────────────────────────────
	var pc := Color(0.2, 0.2, 0.27)
	var pe := Color(0.35, 0.35, 0.44, 0.6)
	# Main ground
	draw_rect(Rect2(PLATFORM_LEFT - 20 + shake.x, GROUND_Y + shake.y, PLATFORM_RIGHT - PLATFORM_LEFT + 40, 14), pc)
	draw_line(Vector2(PLATFORM_LEFT - 20 + shake.x, GROUND_Y + shake.y), Vector2(PLATFORM_RIGHT + 20 + shake.x, GROUND_Y + shake.y), pe, 2.0)
	# Ground detail — hash marks
	for gx in range(int(PLATFORM_LEFT), int(PLATFORM_RIGHT), 60):
		draw_line(Vector2(gx + shake.x, GROUND_Y + 3 + shake.y), Vector2(gx + shake.x, GROUND_Y + 11 + shake.y), Color(0.25, 0.25, 0.32, 0.3), 1.0)
	# Side pillars
	draw_rect(Rect2(PLATFORM_LEFT - 25 + shake.x, GROUND_Y - 80 + shake.y, 10, 94), Color(0.18, 0.18, 0.24, 0.5))
	draw_rect(Rect2(PLATFORM_RIGHT + 15 + shake.x, GROUND_Y - 80 + shake.y, 10, 94), Color(0.18, 0.18, 0.24, 0.5))
	# Floating platforms (match PLATFORMS collision rects)
	var fp_col := Color(0.22, 0.22, 0.3, 0.7)
	var fp_edge := Color(0.35, 0.35, 0.45, 0.5)
	for plat: Rect2 in PLATFORMS:
		var pr := Rect2(plat.position + shake, plat.size)
		draw_rect(pr, fp_col)
		draw_line(pr.position, pr.position + Vector2(pr.size.x, 0), fp_edge, 1.5)
		# Support brackets
		draw_rect(Rect2(pr.position.x + 10, pr.position.y + pr.size.y, 4, 12), Color(0.18, 0.18, 0.24, 0.4))
		draw_rect(Rect2(pr.position.x + pr.size.x - 14, pr.position.y + pr.size.y, 4, 12), Color(0.18, 0.18, 0.24, 0.4))

	# ── Burden Zones (dark VFX sprite + fallback) ────────────────────
	for zone: Dictionary in burden_zones:
		var zp: Vector2 = (zone.pos as Vector2) + shake
		var life: float = (zone.timer as float) / BURDEN_DURATION
		var za: float = life * 0.4
		if dark_vfx_sheet:
			# Dark VFX 1: 400x64, 40x32 frames = 10 cols x 2 rows
			var f: int = _anim_frame(pulse_time, 10, 8.0)
			_draw_vfx_strip(dark_vfx_sheet, zp + Vector2(0, -20), 40, 32, f, 10, 5.0, false, Color(1, 1, 1, za))
			# Second layer slightly offset for density
			_draw_vfx_strip(dark_vfx_sheet, zp + Vector2(15, -15), 40, 32, (f + 3) % 10, 10, 4.0, true, Color(0.8, 0.6, 1.0, za * 0.6))
		else:
			for ring in range(4):
				var r: float = BURDEN_RADIUS * (0.3 + float(ring) * 0.2)
				var rot: float = pulse_time * (1.5 - float(ring) * 0.3)
				draw_arc(zp, r, rot, rot + TAU * 0.7, 16, Color(0.2, 0.1, 0.3, za * 0.8), 2.0)
		# Outer boundary ring
		draw_arc(zp, BURDEN_RADIUS, 0, TAU, 24, Color(0.3, 0.15, 0.35, za * 0.25), 2.0)
		draw_circle(zp, BURDEN_RADIUS, Color(0.1, 0.05, 0.15, za * 0.08))

	# ── Shockwave (thunder strike sprite + fallback) ─────────────────
	if blame_shockwave_active:
		var sw_y: float = GROUND_Y - 3 + shake.y
		var sw_x: float = blame_shockwave_x + shake.x
		var sw_pos := Vector2(sw_x, sw_y - 20)
		# Thunder strike sprite animation
		if thunder_strike_sheet:
			var dist: float = absf(blame_shockwave_x - blame_shockwave_origin)
			var progress: float = clampf(dist / BLAME_SLAM_RANGE, 0.0, 1.0)
			var t_frame: int = _anim_frame(progress, 13, 13.0, false)
			_draw_vfx_strip(thunder_strike_sheet, sw_pos, 64, 64, t_frame, 13, 3.0, blame_shockwave_dir < 0)
		else:
			# Fallback programmatic
			var sw_col := Color(0.3, 0.4, 0.8, 0.7)
			draw_rect(Rect2(sw_x - 4, sw_y - 45, 8, 45), sw_col)
		# Ground crack trail
		draw_line(Vector2(blame_shockwave_origin + shake.x, sw_y), Vector2(sw_x, sw_y), Color(0.3, 0.3, 0.6, 0.3), 2.0)

	# ── Projectiles (firebolt sprites or fallback) ───────────────────
	for proj: Dictionary in blame_projectiles:
		var pp: Vector2 = (proj.pos as Vector2) + shake
		var sz: float = proj.size as float
		var pflip: bool = (proj.vel as Vector2).x < 0
		if firebolt_sheet:
			var f: int = _anim_frame(pulse_time, 11, 14.0)
			_draw_vfx_strip(firebolt_sheet, pp, 48, 48, f, 11, 2.5, pflip, Color(0.6, 0.7, 1.0))
		else:
			var pdir: Vector2 = (proj.vel as Vector2).normalized()
			var proj_col := Color(0.3, 0.4, 0.8, 0.85)
			draw_circle(pp, sz, proj_col)
			draw_line(pp, pp - pdir * 20.0, Color(proj_col.r, proj_col.g, proj_col.b, 0.3), 2.0)
		# Glow always
		draw_circle(pp, sz + 4, Color(0.3, 0.4, 0.8, 0.1))

	# ── Decoys (ghostly Denial with shimmer) ──────────────────────────
	for decoy: Dictionary in decoys:
		var dp: Vector2 = (decoy.pos as Vector2) + shake
		var da: float = clampf((decoy.timer as float) / DECOY_DURATION, 0.0, 1.0)
		var flicker: float = sin(pulse_time * 12.0) * 0.15
		var dcol := Color(GameManager.get_denial_color(), (da * 0.4 + flicker))
		# Ghost body
		draw_circle(dp + Vector2(0, -38), 18, dcol)
		draw_circle(dp + Vector2(0, -63), 13, dcol)
		draw_circle(dp + Vector2(-7, -8), 6, dcol)
		draw_circle(dp + Vector2(7, -8), 6, dcol)
		# Shimmer aura
		draw_arc(dp + Vector2(0, -35), 30, 0, TAU, 16, Color(GameManager.get_denial_color_light(), da * 0.15 + flicker * 0.5), 1.5)

	# ── Deflect Shield (holy VFX sprite + arcs) ───────────────────────
	if denial_deflect_active > 0:
		var sa: float = denial_deflect_active / DENIAL_DEFLECT_WINDOW
		var dfl_pos: Vector2 = p2_pos + shake + Vector2(p2_facing * 20, -35)
		if holy_impact_sheet:
			# Holy VFX 01 Impact: 224x32, 32px frames = 7 frames
			var f: int = _anim_frame(DENIAL_DEFLECT_WINDOW - denial_deflect_active, 7, 20.0, false)
			_draw_vfx_strip(holy_impact_sheet, dfl_pos, 32, 32, f, 7, 4.0, p2_facing < 0, Color(1, 1, 1, sa))
		else:
			for layer in range(3):
				var r: float = 32.0 + float(layer) * 8.0
				draw_arc(dfl_pos, r, p2_facing * -0.9, p2_facing * 0.9, 20, Color(1.0, 0.85, 0.3, sa * 0.5), 3.0)
		if denial_deflect_success:
			draw_circle(dfl_pos, 50, Color(1.0, 0.9, 0.3, sa * 0.3))

	# ── Burst AoE (fire hit sprite + rings) ───────────────────────────
	if denial_burst_anim > 0:
		var burst_pos: Vector2 = p2_pos + shake + Vector2(0, -30)
		var ba: float = denial_burst_anim
		if fire_hit_sheet:
			# Fire Breath hit: sprite sheet for the explosion
			var fh_frame: int = _anim_frame(1.0 - ba, 8, 12.0, false)
			_draw_vfx_strip(fire_hit_sheet, burst_pos, 48, 48, fh_frame, 8, 5.0, false, Color(1, 1, 1, ba))
		# Expanding rings always
		for ring in range(3):
			var r: float = DENIAL_BURST_RADIUS * (1.0 - ba * 0.2) * (0.4 + float(ring) * 0.3)
			draw_arc(burst_pos, r, 0, TAU, 32, Color(1.0, 0.7, 0.3, ba * (0.3 - float(ring) * 0.08)), 2.0)
		draw_circle(burst_pos, 20, Color(1.0, 0.9, 0.5, ba * 0.2))

	# ── Power-Up Aura (swirling energy) ───────────────────────────────
	if p1_powered_up:
		var aura_pos: Vector2 = p1_pos + shake
		for i in range(6):
			var angle: float = pulse_time * 3.0 + float(i) * TAU / 6.0
			var r: float = 35.0 + sin(pulse_time * 4.0 + float(i)) * 8.0
			var orb_pos: Vector2 = aura_pos + Vector2(cos(angle), sin(angle)) * r + Vector2(0, -35)
			draw_circle(orb_pos, 3, Color(0.5, 0.3, 0.85, 0.4))
		draw_circle(aura_pos + Vector2(0, -35), 42, Color(0.4, 0.2, 0.7, 0.08 + sin(pulse_time * 5.0) * 0.04))

	# ── P1 Blame (Mecha Golem sprite) ────────────────────────────────
	var sp1: Vector2 = p1_pos + shake
	var p1_flip: bool = p1_facing < 0
	var p1_mod := Color.WHITE
	if p1_hit_flash > 0: p1_mod = Color(1, 0.5, 0.5, 1).lerp(Color.WHITE, 1.0 - p1_hit_flash)
	if p1_stun > 0: p1_mod.a = 0.5
	if p1_powered_up: p1_mod = p1_mod.lerp(Color(0.7, 0.5, 1.0), 0.4)

	# Shadow
	_draw_shadow_ellipse(Rect2(sp1.x - 20, GROUND_Y + shake.y - 4, 40, 8), Color(0, 0, 0, 0.2))

	# Pick golem animation row & frame
	# Sheet layout (10 cols x 10 rows, 100x100):
	# Row 5: Idle (8 frames), Row 6: Walk (10 frames), Row 2: Attack (8 frames)
	# Row 3: Hurt/defend (5 frames), Row 8: Death (4 frames)
	var g_row: int = 5
	var g_frame: int = 0
	var g_scale: float = 1.8  # Scale up from 100px

	if p1_stun > 0:
		g_row = 3  # Hurt/defend
		g_frame = 0
	elif blame_slam_anim > 0:
		g_row = 2  # Attack
		g_frame = _anim_frame(1.0 - blame_slam_anim, 8, 16.0, false)
	elif not p1_on_ground:
		g_row = 6  # Walk frame for jump
		g_frame = 2
	elif absf(p1_vel.x) > 30:
		g_row = 6  # Walk
		g_frame = _anim_frame(pulse_time, 6, 10.0)
	else:
		g_row = 5  # Idle
		g_frame = _anim_frame(pulse_time, 4, 6.0)

	GameManager.draw_blame_sprite(self, sp1, g_frame, g_row, g_scale, p1_flip, p1_mod)

	# Power-up aura (sprite-based glow behind character)
	if p1_powered_up:
		for i in range(4):
			var angle: float = pulse_time * 3.0 + float(i) * TAU / 4.0
			var orb_pos: Vector2 = sp1 + Vector2(cos(angle), sin(angle)) * 45.0 + Vector2(0, -50)
			draw_circle(orb_pos, 4, Color(0.6, 0.3, 1.0, 0.4))

	# ── P2 Denial (Rogue Knight sprite) ───────────────────────────────
	var sp2: Vector2 = p2_pos + shake
	var p2_flip: bool = p2_facing < 0
	var p2_mod := Color.WHITE
	if p2_hit_flash > 0: p2_mod = Color(1, 0.5, 0.5, 1).lerp(Color.WHITE, 1.0 - p2_hit_flash)
	if p2_stun > 0: p2_mod.a = 0.5

	# Shadow
	_draw_shadow_ellipse(Rect2(sp2.x - 16, GROUND_Y + shake.y - 3, 32, 6), Color(0, 0, 0, 0.15))

	# Pick rogue animation row & frame
	# Sheet layout (Fullmain.png, 500x444, 50x74 frames, 10 cols x 6 rows):
	# Row 0: Idle (4 frames), Row 1: Run (8 frames), Row 2: Attack1 (10 frames)
	# Row 3: Attack2 (8 frames), Row 4: Stand (6 frames), Row 5: Crouch (4 frames)
	var r_row: int = 0
	var r_frame: int = 0
	var r_scale: float = 2.5  # Scale up from 50px — larger to match golem

	if p2_stun > 0:
		r_row = 0
		r_frame = 0
	elif denial_suppress_anim > 0:
		r_row = 2  # Attack1 (slash)
		r_frame = _anim_frame(1.0 - denial_suppress_anim, 6, 16.0, false)
	elif denial_deflect_active > 0:
		r_row = 3  # Attack2 / parry
		r_frame = 0
	elif not p2_on_ground:
		r_row = 1  # Run frame for jump
		r_frame = 1
	elif absf(p2_vel.x) > 30:
		r_row = 1  # Run
		r_frame = _anim_frame(pulse_time, 4, 10.0)
	else:
		r_row = 0  # Idle
		r_frame = _anim_frame(pulse_time, 2, 3.0)

	GameManager.draw_denial_sprite(self, sp2, r_frame, r_row, r_scale, p2_flip, p2_mod)

	# Suppress wave VFX (smear sprite)
	if denial_suppress_anim > 0 and smear_sheet:
		var smear_frame: int = _anim_frame(1.0 - denial_suppress_anim, 5, 12.0, false)
		_draw_vfx_strip(smear_sheet, sp2 + Vector2(p2_facing * 40, -35), 48, 48, smear_frame, 5, 3.0, p2_facing < 0, Color(1, 1, 1, denial_suppress_anim))

	# ── VFX Particles ─────────────────────────────────────────────────
	for p: Dictionary in vfx:
		var a: float = float(p["life"]) / float(p["max_life"])
		var vcol: Color = Color(p["color"])
		vcol.a = a
		var vsz: float = float(p["size"]) * a
		if int(p["type"]) == 1:
			# Sparks — small bright lines
			var vdir: Vector2 = Vector2(p["vel"]).normalized()
			draw_line(Vector2(p["pos"]), Vector2(p["pos"]) + vdir * vsz * 3.0, vcol, 1.5)
		else:
			draw_circle(Vector2(p["pos"]) + shake, vsz, vcol)

	# ── Score Popups ──────────────────────────────────────────────────
	for popup: Dictionary in score_popups:
		var pa: float = clampf(float(popup["life"]), 0.0, 1.0)
		var pcol: Color = Color(popup["color"])
		pcol.a = pa
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(popup["pos"]) + shake, popup["text"] as String, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, pcol)

	# ── Dialogue ──────────────────────────────────────────────────────
	if fight_text_alpha > 0 and fight_dialogue_index >= 0:
		var fd: Dictionary = fight_dialogue_queue[fight_dialogue_index]
		var text_col: Color = fd.color
		text_col.a = fight_text_alpha
		var font := ThemeDB.fallback_font
		var text_str: String = fd.speaker + ": \"" + fd.text + "\""
		var tw: float = font.get_string_size(text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string(font, Vector2(640 - tw * 0.5, 45) + shake, text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, text_col)

	# ── Controls during countdown ─────────────────────────────────────
	if phase == 0:
		var ca: float = 0.65 + sin(countdown_timer * 3.0) * 0.12
		var font := ThemeDB.fallback_font
		var cc := Color(0.65, 0.65, 0.75, ca)
		var hl := Color(0.5, 0.5, 0.65, ca * 0.6)
		# P1
		draw_string(font, Vector2(80, 175), "BLAME — The Weight", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(GameManager.get_blame_color_light(), ca))
		draw_line(Vector2(80, 182), Vector2(310, 182), Color(GameManager.get_blame_color(), ca * 0.3), 1.0)
		draw_string(font, Vector2(80, 205), "Move: WASD / Stick  |  Jump: W / A", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, hl)
		draw_string(font, Vector2(80, 225), "F / X : Guilt Slam (punch + shockwave)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, cc)
		draw_string(font, Vector2(80, 243), "G / Y : Accusation (cold projectile)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, cc)
		draw_string(font, Vector2(80, 261), "R / B : Burden Zone (slow field)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, cc)
		draw_string(font, Vector2(80, 281), "F+G  : Self-Punishment (-2pts, double dmg)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.4, 0.8, ca))
		# P2
		draw_string(font, Vector2(740, 175), "DENIAL — The Escape", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(GameManager.get_denial_color_light(), ca))
		draw_line(Vector2(740, 182), Vector2(980, 182), Color(GameManager.get_denial_color(), ca * 0.3), 1.0)
		draw_string(font, Vector2(740, 205), "Move: Arrows / Stick  |  Jump: Up / A", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, hl)
		draw_string(font, Vector2(740, 225), "Enter / X : Suppress (push + punch)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, cc)
		draw_string(font, Vector2(740, 243), "RShift / Y : Deflect (parry, reflects!)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, cc)
		draw_string(font, Vector2(740, 261), "Num0 / B : Forget (teleport + decoy)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, cc)
		draw_string(font, Vector2(740, 281), "Enter+RShift : Bright Burst (-2pts, AoE)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.65, 0.35, ca))
		# Center text
		var ct_a: float = 0.5 + sin(pulse_time * 2.0) * 0.2
		if waiting_for_start:
			draw_string(font, Vector2(440, 430), "Press SPACE / X to Start", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.8, 0.8, 0.9, ct_a))
		else:
			draw_string(font, Vector2(530, 450), "GET READY", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.7, 0.7, 0.8, ct_a))


func _anim_frame(time: float, frame_count: int, fps: float = 10.0, looping: bool = true) -> int:
	var frame: int = int(time * fps)
	if looping:
		return frame % maxi(frame_count, 1)
	else:
		return mini(frame, frame_count - 1)


func _draw_shadow_ellipse(rect: Rect2, color: Color) -> void:
	var center := rect.get_center()
	var pts := PackedVector2Array()
	for i in range(16):
		var angle: float = float(i) / 16.0 * TAU
		pts.append(center + Vector2(cos(angle) * rect.size.x * 0.5, sin(angle) * rect.size.y * 0.5))
	draw_colored_polygon(pts, color)


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _draw_sprite_frame(tex: Texture2D, pos: Vector2, fw: int, fh: int,
		scol: int, srow: int, scl: float, flip_h: bool, mod: Color = Color.WHITE) -> void:
	if not tex:
		return
	var src := Rect2(scol * fw, srow * fh, fw, fh)
	var dw: float = float(fw) * scl
	var dh: float = float(fh) * scl
	var dest := Rect2(pos.x - dw * 0.5, pos.y - dh, dw, dh)
	if flip_h:
		src.position.x += src.size.x
		src.size.x = -src.size.x
	draw_texture_rect_region(tex, dest, src, mod)


func _draw_vfx_strip(tex: Texture2D, pos: Vector2, frame_w: int, frame_h: int,
		frame: int, total_frames: int, scl: float, flip_h: bool = false, mod: Color = Color.WHITE) -> void:
	if not tex:
		return
	var f: int = clampi(frame, 0, total_frames - 1)
	var src := Rect2(f * frame_w, 0, frame_w, frame_h)
	var dw: float = float(frame_w) * scl
	var dh: float = float(frame_h) * scl
	var dest := Rect2(pos.x - dw * 0.5, pos.y - dh * 0.5, dw, dh)
	if flip_h:
		src.position.x += src.size.x
		src.size.x = -src.size.x
	draw_texture_rect_region(tex, dest, src, mod)


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
