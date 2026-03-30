extends Control

## Competitive Minigame 1 — Platform fighter on shattered glass.
## Background is a seamless mosaic of glass shards (triangles + rectangles).
## Hits break shards near impact. Random ambient shards also crack over time.
## Winner = whoever broke more shards. No health bars.

@onready var dialogue: Node = $DialogueSystem
@onready var timer_label: Label = $HUD/TimerLabel
@onready var p1_score_label: Label = $HUD/P1Score
@onready var p2_score_label: Label = $HUD/P2Score

# --- Arena / Physics ---
const GRAVITY := 900.0
const JUMP_FORCE := -420.0
const PLAYER_SPEED := 260.0
const ATTACK_RANGE := 75.0
const ATTACK_COOLDOWN := 0.45
const KNOCKBACK_X := 280.0
const KNOCKBACK_Y := -180.0
const MATCH_TIME := 45.0

const GROUND_Y := 540.0
const PLATFORM_LEFT := 140.0
const PLATFORM_RIGHT := 1140.0
const CEILING := 60.0

# --- Expanded combat constants ---
const LIGHT_ATTACK_COOLDOWN := 0.35
const LIGHT_ATTACK_RANGE := 75.0
const LIGHT_SHARD_RADIUS := 100.0
const LIGHT_KNOCKBACK_X := 250.0
const LIGHT_KNOCKBACK_Y := -150.0

const HEAVY_ATTACK_COOLDOWN := 0.7
const HEAVY_ATTACK_WINDUP := 0.3
const HEAVY_ATTACK_RANGE := 90.0
const HEAVY_SHARD_RADIUS := 200.0
const HEAVY_KNOCKBACK_X := 420.0
const HEAVY_KNOCKBACK_Y := -250.0

const DODGE_COOLDOWN := 0.8
const DODGE_DISTANCE := 150.0
const DODGE_DURATION := 0.15
const DODGE_SPEED := 1000.0  # px/s during dash

# --- Shattered Glass (uses GameManager global shards) ---
var ambient_break_timer := 0.0
const AMBIENT_BREAK_INTERVAL := 0.6

# --- Players ---
var p1_pos := Vector2(380, GROUND_Y)
var p1_vel := Vector2.ZERO
var p1_on_ground := true
var p1_attack_timer := 0.0
var p1_attack_anim := 0.0
var p1_hit_flash := 0.0
var p1_facing := 1.0
var p1_hits := 0

# P1 expanded combat state
var p1_heavy_timer := 0.0       # cooldown remaining
var p1_heavy_windup := 0.0      # windup countdown (>0 means winding up)
var p1_heavy_anim := 0.0        # 1.0 -> 0.0 strike animation
var p1_dodge_timer := 0.0       # cooldown remaining
var p1_dodge_active := 0.0      # time remaining in dodge roll
var p1_invincible := false
var p1_afterimage_timer := 0.0  # afterimage fade
var p1_afterimage_pos := Vector2.ZERO

var p2_pos := Vector2(900, GROUND_Y)
var p2_vel := Vector2.ZERO
var p2_on_ground := true
var p2_attack_timer := 0.0
var p2_attack_anim := 0.0
var p2_hit_flash := 0.0
var p2_facing := -1.0
var p2_hits := 0

# P2 expanded combat state
var p2_heavy_timer := 0.0
var p2_heavy_windup := 0.0
var p2_heavy_anim := 0.0
var p2_dodge_timer := 0.0
var p2_dodge_active := 0.0
var p2_invincible := false
var p2_afterimage_timer := 0.0
var p2_afterimage_pos := Vector2.ZERO

# --- State ---
var match_timer := MATCH_TIME
var match_over := false
var blame_won := false
var phase: int = 0
var countdown_timer := 2.5
# falling_shards handled by GameManager

# --- Fight dialogue ---
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
	countdown_timer = 2.5


# --- Shard generation with SHARED VERTEX GRID (no gaps) ---
# Shard generation moved to GameManager


func _process(delta: float) -> void:
	match phase:
		0:
			countdown_timer -= delta
			timer_label.text = str(ceili(countdown_timer))
			if countdown_timer <= 0:
				phase = 1
				fight_dialogue_timer = 3.0
		1: _process_fight(delta)
		2: pass
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

	# Fight dialogue
	fight_dialogue_timer -= delta
	if fight_dialogue_timer <= 0 and fight_dialogue_index < fight_dialogue_queue.size() - 1:
		fight_dialogue_index += 1
		fight_text_alpha = 1.0
		fight_dialogue_timer = 6.0
	if fight_text_alpha > 0:
		fight_text_alpha -= delta * 0.12

	# --- Ambient random shard breaking across the whole screen ---
	ambient_break_timer -= delta
	if ambient_break_timer <= 0:
		ambient_break_timer = AMBIENT_BREAK_INTERVAL + randf_range(-0.2, 0.3)
		GameManager.break_random_shards(1)

	# --- P1 (Blame) movement ---
	_process_player_movement(delta, true)

	# --- P2 (Denial) movement ---
	_process_player_movement(delta, false)

	# --- Decay timers ---
	p1_attack_timer = maxf(0.0, p1_attack_timer - delta)
	p2_attack_timer = maxf(0.0, p2_attack_timer - delta)
	p1_attack_anim = maxf(0.0, p1_attack_anim - delta * 4.0)
	p2_attack_anim = maxf(0.0, p2_attack_anim - delta * 4.0)
	p1_hit_flash = maxf(0.0, p1_hit_flash - delta * 5.0)
	p2_hit_flash = maxf(0.0, p2_hit_flash - delta * 5.0)

	p1_heavy_timer = maxf(0.0, p1_heavy_timer - delta)
	p2_heavy_timer = maxf(0.0, p2_heavy_timer - delta)
	p1_heavy_anim = maxf(0.0, p1_heavy_anim - delta * 3.0)
	p2_heavy_anim = maxf(0.0, p2_heavy_anim - delta * 3.0)
	p1_dodge_timer = maxf(0.0, p1_dodge_timer - delta)
	p2_dodge_timer = maxf(0.0, p2_dodge_timer - delta)
	p1_afterimage_timer = maxf(0.0, p1_afterimage_timer - delta * 4.0)
	p2_afterimage_timer = maxf(0.0, p2_afterimage_timer - delta * 4.0)

	# --- Process dodge active ---
	_process_dodge(delta, true)
	_process_dodge(delta, false)

	# --- Process heavy windup ---
	_process_heavy_windup(delta, true)
	_process_heavy_windup(delta, false)

	# --- Light Attacks ---
	# P1 light attacks P2
	if Input.is_action_just_pressed("p1_attack") and p1_attack_timer <= 0 and p1_dodge_active <= 0 and p1_heavy_windup <= 0:
		p1_attack_timer = LIGHT_ATTACK_COOLDOWN
		p1_attack_anim = 1.0
		if p1_pos.distance_to(p2_pos) < LIGHT_ATTACK_RANGE and not p2_invincible:
			p2_hit_flash = 1.0
			p2_vel.x = sign(p2_pos.x - p1_pos.x) * LIGHT_KNOCKBACK_X
			p2_vel.y = LIGHT_KNOCKBACK_Y
			p2_on_ground = false
			var broken: int = GameManager.break_shards_near(p2_pos, 1, LIGHT_SHARD_RADIUS)
			p1_hits += broken
			p1_score_label.text = "BLAME: " + str(p1_hits)

	# P2 light attacks P1
	if Input.is_action_just_pressed("p2_attack") and p2_attack_timer <= 0 and p2_dodge_active <= 0 and p2_heavy_windup <= 0:
		p2_attack_timer = LIGHT_ATTACK_COOLDOWN
		p2_attack_anim = 1.0
		if p2_pos.distance_to(p1_pos) < LIGHT_ATTACK_RANGE and not p1_invincible:
			p1_hit_flash = 1.0
			p1_vel.x = sign(p1_pos.x - p2_pos.x) * LIGHT_KNOCKBACK_X
			p1_vel.y = LIGHT_KNOCKBACK_Y
			p1_on_ground = false
			var broken: int = GameManager.break_shards_near(p1_pos, 2, LIGHT_SHARD_RADIUS)
			p2_hits += broken
			p2_score_label.text = "DENIAL: " + str(p2_hits)

	# --- Heavy Attacks (initiate windup) ---
	if Input.is_action_just_pressed("p1_heavy") and p1_heavy_timer <= 0 and p1_dodge_active <= 0 and p1_heavy_windup <= 0:
		p1_heavy_timer = HEAVY_ATTACK_COOLDOWN
		p1_heavy_windup = HEAVY_ATTACK_WINDUP

	if Input.is_action_just_pressed("p2_heavy") and p2_heavy_timer <= 0 and p2_dodge_active <= 0 and p2_heavy_windup <= 0:
		p2_heavy_timer = HEAVY_ATTACK_COOLDOWN
		p2_heavy_windup = HEAVY_ATTACK_WINDUP

	# --- Dodge Roll ---
	if Input.is_action_just_pressed("p1_dodge") and p1_dodge_timer <= 0 and p1_dodge_active <= 0 and p1_heavy_windup <= 0:
		p1_dodge_timer = DODGE_COOLDOWN
		p1_dodge_active = DODGE_DURATION
		p1_invincible = true
		p1_afterimage_pos = p1_pos
		p1_afterimage_timer = 1.0

	if Input.is_action_just_pressed("p2_dodge") and p2_dodge_timer <= 0 and p2_dodge_active <= 0 and p2_heavy_windup <= 0:
		p2_dodge_timer = DODGE_COOLDOWN
		p2_dodge_active = DODGE_DURATION
		p2_invincible = true
		p2_afterimage_pos = p2_pos
		p2_afterimage_timer = 1.0

	# Update hue
	var total_hits: float = float(p1_hits + p2_hits)
	if total_hits > 0:
		var target_hue: float = float(p2_hits) / total_hits
		GameManager.set_hue(lerpf(GameManager.hue_value, target_hue, 3.0 * delta))


func _process_player_movement(delta: float, is_p1: bool) -> void:
	# During dodge, override movement
	if is_p1 and p1_dodge_active > 0:
		return
	if not is_p1 and p2_dodge_active > 0:
		return

	if is_p1:
		var p1_dir: float = 0.0
		if Input.is_action_pressed("p1_left"): p1_dir -= 1.0
		if Input.is_action_pressed("p1_right"): p1_dir += 1.0
		if p1_dir != 0.0: p1_facing = p1_dir
		p1_vel.x = lerpf(p1_vel.x, p1_dir * PLAYER_SPEED, 10.0 * delta)

		if p1_on_ground and Input.is_action_just_pressed("p1_up"):
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
	else:
		var p2_dir: float = 0.0
		if Input.is_action_pressed("p2_left"): p2_dir -= 1.0
		if Input.is_action_pressed("p2_right"): p2_dir += 1.0
		if p2_dir != 0.0: p2_facing = p2_dir
		p2_vel.x = lerpf(p2_vel.x, p2_dir * PLAYER_SPEED, 10.0 * delta)

		if p2_on_ground and Input.is_action_just_pressed("p2_up"):
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


func _process_dodge(delta: float, is_p1: bool) -> void:
	if is_p1:
		if p1_dodge_active > 0:
			p1_dodge_active -= delta
			# Dash movement in facing direction
			p1_pos.x += p1_facing * DODGE_SPEED * delta
			p1_pos.x = clampf(p1_pos.x, PLATFORM_LEFT, PLATFORM_RIGHT)
			# Keep gravity applied but reduced during dodge
			p1_vel.y += GRAVITY * delta * 0.3
			p1_pos.y += p1_vel.y * delta
			if p1_pos.y >= GROUND_Y:
				p1_pos.y = GROUND_Y
				p1_vel.y = 0.0
				p1_on_ground = true
			if p1_dodge_active <= 0:
				p1_invincible = false
				p1_vel.x = p1_facing * PLAYER_SPEED * 0.5  # residual momentum
	else:
		if p2_dodge_active > 0:
			p2_dodge_active -= delta
			p2_pos.x += p2_facing * DODGE_SPEED * delta
			p2_pos.x = clampf(p2_pos.x, PLATFORM_LEFT, PLATFORM_RIGHT)
			p2_vel.y += GRAVITY * delta * 0.3
			p2_pos.y += p2_vel.y * delta
			if p2_pos.y >= GROUND_Y:
				p2_pos.y = GROUND_Y
				p2_vel.y = 0.0
				p2_on_ground = true
			if p2_dodge_active <= 0:
				p2_invincible = false
				p2_vel.x = p2_facing * PLAYER_SPEED * 0.5


func _process_heavy_windup(delta: float, is_p1: bool) -> void:
	if is_p1:
		if p1_heavy_windup > 0:
			p1_heavy_windup -= delta
			if p1_heavy_windup <= 0:
				# Windup finished — strike lands now
				p1_heavy_anim = 1.0
				if p1_pos.distance_to(p2_pos) < HEAVY_ATTACK_RANGE and not p2_invincible:
					p2_hit_flash = 1.0
					p2_vel.x = sign(p2_pos.x - p1_pos.x) * HEAVY_KNOCKBACK_X
					p2_vel.y = HEAVY_KNOCKBACK_Y
					p2_on_ground = false
					var broken: int = GameManager.break_shards_near(p2_pos, 1, HEAVY_SHARD_RADIUS)
					p1_hits += broken
					p1_score_label.text = "BLAME: " + str(p1_hits)
				# Also break shards at the attacker position for heavy slam visual
				var self_broken: int = GameManager.break_shards_near(p1_pos, 1, HEAVY_SHARD_RADIUS * 0.5)
				p1_hits += self_broken
				p1_score_label.text = "BLAME: " + str(p1_hits)
	else:
		if p2_heavy_windup > 0:
			p2_heavy_windup -= delta
			if p2_heavy_windup <= 0:
				p2_heavy_anim = 1.0
				if p2_pos.distance_to(p1_pos) < HEAVY_ATTACK_RANGE and not p1_invincible:
					p1_hit_flash = 1.0
					p1_vel.x = sign(p1_pos.x - p2_pos.x) * HEAVY_KNOCKBACK_X
					p1_vel.y = HEAVY_KNOCKBACK_Y
					p1_on_ground = false
					var broken: int = GameManager.break_shards_near(p1_pos, 2, HEAVY_SHARD_RADIUS)
					p2_hits += broken
					p2_score_label.text = "DENIAL: " + str(p2_hits)
				var self_broken: int = GameManager.break_shards_near(p2_pos, 2, HEAVY_SHARD_RADIUS * 0.5)
				p2_hits += self_broken
				p2_score_label.text = "DENIAL: " + str(p2_hits)


# Shard breaking/falling functions now in GameManager


func _draw() -> void:
	# Shards drawn by global ShardBackground autoload

	# --- Platform ---
	draw_rect(Rect2(PLATFORM_LEFT - 20, GROUND_Y, PLATFORM_RIGHT - PLATFORM_LEFT + 40, 12),
		Color(0.25, 0.25, 0.3, 0.9))
	draw_line(Vector2(PLATFORM_LEFT - 20, GROUND_Y), Vector2(PLATFORM_RIGHT + 20, GROUND_Y),
		Color(0.4, 0.4, 0.48, 0.6), 2.0)
	draw_rect(Rect2(PLATFORM_LEFT - 20, GROUND_Y + 12, PLATFORM_RIGHT - PLATFORM_LEFT + 40, 6),
		Color(0.15, 0.15, 0.18, 0.7))

	# --- Afterimages (drawn before characters so they appear behind) ---
	if p1_afterimage_timer > 0:
		_draw_blame_afterimage(p1_afterimage_pos, p1_facing, p1_afterimage_timer)
	if p2_afterimage_timer > 0:
		_draw_denial_afterimage(p2_afterimage_pos, p2_facing, p2_afterimage_timer)

	# --- Characters ---
	_draw_blame(p1_pos, p1_facing, p1_attack_anim, p1_hit_flash, p1_heavy_windup, p1_heavy_anim, p1_dodge_active)
	_draw_denial(p2_pos, p2_facing, p2_attack_anim, p2_hit_flash, p2_heavy_windup, p2_heavy_anim, p2_dodge_active)

	# --- Controls flash during countdown ---
	if phase == 0:
		var ctrl_alpha: float = 0.7 + sin(countdown_timer * 3.0) * 0.15
		var font := ThemeDB.fallback_font
		var cc := Color(0.7, 0.7, 0.8, ctrl_alpha)
		var hc := Color(0.55, 0.55, 0.65, ctrl_alpha * 0.7)
		# P1 controls (left side)
		draw_string(font, Vector2(100, 200), "PLAYER 1 — BLAME", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(GameManager.get_blame_color_light(), ctrl_alpha))
		draw_string(font, Vector2(100, 230), "Move: WASD / Left Stick", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, cc)
		draw_string(font, Vector2(100, 252), "Jump: W / A button", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, cc)
		draw_string(font, Vector2(100, 274), "Light Attack: F / X button", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, cc)
		draw_string(font, Vector2(100, 296), "Heavy Attack: G / Y button", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, cc)
		draw_string(font, Vector2(100, 318), "Dodge: R / B button", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, cc)
		# P2 controls (right side)
		draw_string(font, Vector2(780, 200), "PLAYER 2 — DENIAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(GameManager.get_denial_color_light(), ctrl_alpha))
		draw_string(font, Vector2(780, 230), "Move: Arrows / Left Stick", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, cc)
		draw_string(font, Vector2(780, 252), "Jump: Up / A button", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, cc)
		draw_string(font, Vector2(780, 274), "Light Attack: Enter / X button", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, cc)
		draw_string(font, Vector2(780, 296), "Heavy Attack: RShift / Y button", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, cc)
		draw_string(font, Vector2(780, 318), "Dodge: Num0 / B button", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, cc)
		# Center hint
		draw_string(font, Vector2(490, 420), "Break the glass!", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, hc)

	# --- Dialogue ---
	if fight_text_alpha > 0 and fight_dialogue_index >= 0:
		var fd: Dictionary = fight_dialogue_queue[fight_dialogue_index]
		var text_col: Color = fd.color
		text_col.a = fight_text_alpha
		var font := ThemeDB.fallback_font
		var text_str: String = fd.speaker + ": \"" + fd.text + "\""
		var tw: float = font.get_string_size(text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string(font, Vector2(640 - tw * 0.5, 45), text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, text_col)


func _draw_blame(pos: Vector2, facing: float, atk_anim: float, hit_flash: float,
		heavy_windup: float, heavy_anim: float, dodge_active: float) -> void:
	var c := GameManager.get_blame_color()
	var cl := GameManager.get_blame_color_light()
	if hit_flash > 0:
		c = c.lerp(Color.WHITE, hit_flash * 0.6)
		cl = cl.lerp(Color.WHITE, hit_flash * 0.6)

	# Dodge roll: stretch horizontally in dash direction
	var stretch_x := 1.0
	var squash_y := 1.0
	if dodge_active > 0:
		var dodge_t: float = dodge_active / DODGE_DURATION
		stretch_x = 1.0 + dodge_t * 0.6  # stretch wider
		squash_y = 1.0 - dodge_t * 0.3   # squash shorter
		# Tint slightly transparent during i-frames
		c.a = 0.6
		cl.a = 0.6

	# All drawing offset from pos; apply stretch via helper
	var px: float = pos.x
	var py: float = pos.y

	# Legs — thin rectangles
	var leg_w: float = 8.0 * stretch_x
	var leg_h: float = 24.0 * squash_y
	draw_rect(Rect2(px - 13 * stretch_x, py - leg_h, leg_w, leg_h), c)
	draw_rect(Rect2(px + 5 * stretch_x, py - leg_h, leg_w, leg_h), c)

	# Body — tall rectangle
	var body_w: float = 28.0 * stretch_x
	var body_h: float = 34.0 * squash_y
	var body_y: float = py - leg_h - body_h
	draw_rect(Rect2(px - 14 * stretch_x, body_y, body_w, body_h), c)
	draw_rect(Rect2(px - 9 * stretch_x, body_y + 6 * squash_y, 18 * stretch_x, 22 * squash_y),
		Color(cl.r, cl.g, cl.b, 0.25))

	# Head — square
	var head_size: float = 22.0 * stretch_x
	var head_h: float = 20.0 * squash_y
	var head_y: float = body_y - head_h + 2 * squash_y
	draw_rect(Rect2(px - 11 * stretch_x, head_y, head_size, head_h), c)

	# Eyes
	var eye_x: float = px + facing * 3 * stretch_x
	var eye_y: float = head_y + 5 * squash_y
	draw_rect(Rect2(eye_x - 6 * stretch_x, eye_y, 4 * stretch_x, 4 * squash_y),
		Color(0.7, 0.75, 0.9, 0.8))
	draw_rect(Rect2(eye_x + 2 * stretch_x, eye_y, 4 * stretch_x, 4 * squash_y),
		Color(0.7, 0.75, 0.9, 0.8))

	# Arm — depends on attack state
	var arm_y: float = body_y + 8 * squash_y

	if heavy_windup > 0:
		# Heavy windup: arm raised/pulled back
		var windup_t: float = heavy_windup / HEAVY_ATTACK_WINDUP  # 1.0 at start, 0.0 at strike
		var arm_back_x: float = px - facing * (15 + windup_t * 20)
		var arm_up_y: float = arm_y - windup_t * 30
		# Arm drawn as rectangle from shoulder pulled back and up
		var ax1: float = minf(px, arm_back_x)
		var ax2: float = maxf(px, arm_back_x)
		draw_rect(Rect2(ax1, arm_up_y, ax2 - ax1 + 8, 10), cl)
		# Fist
		draw_rect(Rect2(arm_back_x - 6, arm_up_y - 3, 14, 14), c)
	elif heavy_anim > 0:
		# Heavy strike: big forward swing
		var arm_end_x: float = px + facing * (25 + heavy_anim * 45)
		var arm_end_y: float = arm_y + heavy_anim * 8  # slight downward arc
		var ax1: float = minf(px, arm_end_x)
		var ax2: float = maxf(px, arm_end_x)
		draw_rect(Rect2(ax1, minf(arm_y, arm_end_y), ax2 - ax1 + 10, 12), cl)
		# Big fist
		draw_rect(Rect2(arm_end_x - 8, arm_end_y - 5, 18, 18), c)
	elif atk_anim > 0:
		# Light attack: fast punch
		var arm_end_x: float = px + facing * (20 + atk_anim * 30)
		draw_rect(Rect2(minf(px, arm_end_x), arm_y, absf(arm_end_x - px) + 8, 8), cl)
		draw_rect(Rect2(arm_end_x - 5, arm_y - 2, 12, 12), c)
	else:
		# Idle arm
		draw_rect(Rect2(px + facing * 14 * stretch_x, arm_y, 10 * stretch_x, 6 * squash_y),
			Color(c.r, c.g, c.b, 0.7))


func _draw_denial(pos: Vector2, facing: float, atk_anim: float, hit_flash: float,
		heavy_windup: float, heavy_anim: float, dodge_active: float) -> void:
	var c := GameManager.get_denial_color()
	var cl := GameManager.get_denial_color_light()
	if hit_flash > 0:
		c = c.lerp(Color.WHITE, hit_flash * 0.6)
		cl = cl.lerp(Color.WHITE, hit_flash * 0.6)

	# Dodge roll: stretch horizontally
	var stretch_x := 1.0
	var squash_y := 1.0
	if dodge_active > 0:
		var dodge_t: float = dodge_active / DODGE_DURATION
		stretch_x = 1.0 + dodge_t * 0.6
		squash_y = 1.0 - dodge_t * 0.3
		c.a = 0.6
		cl.a = 0.6

	var px: float = pos.x
	var py: float = pos.y

	# Legs — circle chains
	draw_circle(Vector2(px - 7 * stretch_x, py - 8 * squash_y), 6 * squash_y, c)
	draw_circle(Vector2(px + 7 * stretch_x, py - 8 * squash_y), 6 * squash_y, c)
	draw_circle(Vector2(px - 7 * stretch_x, py - 18 * squash_y), 5 * squash_y, c)
	draw_circle(Vector2(px + 7 * stretch_x, py - 18 * squash_y), 5 * squash_y, c)

	# Body — circle
	var body_y: float = py - 40 * squash_y
	draw_circle(Vector2(px, body_y), 18 * maxf(stretch_x, squash_y), c)
	draw_circle(Vector2(px, body_y), 11 * maxf(stretch_x, squash_y), Color(cl.r, cl.g, cl.b, 0.25))

	# Head — circle
	var head_y: float = py - 65 * squash_y
	draw_circle(Vector2(px, head_y), 13 * squash_y, c)

	# Eyes
	var eye_x: float = px + facing * 4 * stretch_x
	draw_circle(Vector2(eye_x - 4 * stretch_x, head_y - 2 * squash_y), 2.5 * squash_y,
		Color(0.95, 0.85, 0.7, 0.8))
	draw_circle(Vector2(eye_x + 4 * stretch_x, head_y - 2 * squash_y), 2.5 * squash_y,
		Color(0.95, 0.85, 0.7, 0.8))

	# Arm
	var arm_origin_y: float = body_y - 2

	if heavy_windup > 0:
		# Heavy windup: arm pulled back and raised
		var windup_t: float = heavy_windup / HEAVY_ATTACK_WINDUP
		var arm_back := Vector2(px - facing * (16 + windup_t * 18), arm_origin_y - windup_t * 28)
		var arm_start := Vector2(px + facing * 14, arm_origin_y)
		for i in range(5):
			var t: float = float(i) / 4.0
			draw_circle(arm_start.lerp(arm_back, t), 4.5, cl)
		# Big fist pulled back
		draw_circle(arm_back, 9, c)
	elif heavy_anim > 0:
		# Heavy strike: big forward swing
		var arm_end := Vector2(px + facing * (22 + heavy_anim * 40), arm_origin_y + heavy_anim * 6)
		var arm_start := Vector2(px + facing * 14, arm_origin_y)
		for i in range(6):
			var t: float = float(i) / 5.0
			draw_circle(arm_start.lerp(arm_end, t), 5, cl)
		# Big fist
		draw_circle(arm_end, 10, c)
	elif atk_anim > 0:
		# Light attack: fast punch with circle chain
		var arm_end := Vector2(px + facing * (18 + atk_anim * 28), arm_origin_y)
		var arm_start := Vector2(px + facing * 14, arm_origin_y)
		for i in range(4):
			var t: float = float(i) / 3.0
			draw_circle(arm_start.lerp(arm_end, t), 4, cl)
		draw_circle(arm_end, 7, c)
	else:
		# Idle arm
		draw_circle(Vector2(px + facing * 16 * stretch_x, body_y),
			5 * squash_y, Color(c.r, c.g, c.b, 0.7))


func _draw_blame_afterimage(pos: Vector2, facing: float, alpha: float) -> void:
	var c := GameManager.get_blame_color()
	c.a = alpha * 0.35

	# Simplified ghostly version of Blame — just the main shapes
	draw_rect(Rect2(pos.x - 13, pos.y - 24, 8, 24), c)
	draw_rect(Rect2(pos.x + 5, pos.y - 24, 8, 24), c)
	draw_rect(Rect2(pos.x - 14, pos.y - 56, 28, 34), c)
	draw_rect(Rect2(pos.x - 11, pos.y - 74, 22, 20), c)


func _draw_denial_afterimage(pos: Vector2, facing: float, alpha: float) -> void:
	var c := GameManager.get_denial_color()
	c.a = alpha * 0.35

	# Simplified ghostly version of Denial
	draw_circle(Vector2(pos.x - 7, pos.y - 8), 6, c)
	draw_circle(Vector2(pos.x + 7, pos.y - 8), 6, c)
	draw_circle(Vector2(pos.x, pos.y - 40), 18, c)
	draw_circle(Vector2(pos.x, pos.y - 65), 13, c)


func _end_match() -> void:
	match_over = true
	if p1_hits > p2_hits:
		blame_won = true
	elif p2_hits > p1_hits:
		blame_won = false
	else:
		blame_won = randf() > 0.5

	GameManager.register_competitive_win(blame_won)
	# Post-match dialogue moved to fragment_reveal scene
	phase = 3
