extends Control

## Cooperative Minigame — "Carrying the Weight Together"
## Core mechanic: EMOTIONAL PRESENCE. Ghostly platforms only solidify
## when the matching player is nearby. You literally need each other to move forward.
## Cold (blue) ghost platforms solidify when Blame is near.
## Warm (orange) ghost platforms solidify when Denial is near.
## A guilt shadow chases — slows when players are close, speeds up when apart.
## Shared clarity meter drains on falls, restored by gems.

@onready var dialogue: Node = $DialogueSystem

# ─── Physics ───────────────────────────────────────────────────────────────
const GRAVITY      := 850.0
const JUMP_SPEED   := -420.0
const PLAYER_SPEED := 230.0
const PLAYER_SIZE  := 16.0

# ─── State ─────────────────────────────────────────────────────────────────
var phase: int = 0  # 0=playing, 1=dialogue, 2=done
var pulse_time := 0.0

# ─── Players ───────────────────────────────────────────────────────────────
var p1_pos := Vector2(200.0, 580.0)
var p1_vel := Vector2.ZERO
var p1_on_ground := false

var p2_pos := Vector2(300.0, 580.0)
var p2_vel := Vector2.ZERO
var p2_on_ground := false

# ─── Platforms ─────────────────────────────────────────────────────────────
# {rect, type, solidity, grace_timer}
# type: "solid"=always there, "cold"=needs Blame near, "warm"=needs Denial near
# solidity: 0.0=ghost, 1.0=fully solid (lerps smoothly)
# grace_timer: stays solid for this long after player leaves range
var platforms: Array[Dictionary] = []
const PRESENCE_RANGE := 160.0  # How close the player needs to be
const GRACE_DURATION := 2.5    # Seconds platform stays solid after player leaves
const SOLIDIFY_SPEED := 4.0    # How fast platforms fade in/out

# ─── Gems ──────────────────────────────────────────────────────────────────
var gems: Array[Dictionary] = []
const GEM_RADIUS := 8.0

# ─── Shared Clarity Meter ─────────────────────────────────────────────────
var clarity := 100.0
const CLARITY_MAX := 100.0
const FALL_PENALTY := 15.0
const GEM_RESTORE := 8.0

# ─── Guilt Shadow ─────────────────────────────────────────────────────────
var shadow_pos := Vector2(640.0, 700.0)
var shadow_active := false
var shadow_activate_timer := 8.0  # Starts chasing after 8 seconds
const SHADOW_SPEED_CLOSE := 25.0   # When players are together
const SHADOW_SPEED_FAR := 65.0     # When players are separated
const SHADOW_HIT_RANGE := 40.0
const SHADOW_HIT_PENALTY := 20.0
var shadow_hit_cooldown := 0.0

# ─── Exit ──────────────────────────────────────────────────────────────────
var exit_rect := Rect2(555.0, 55.0, 170.0, 14.0)
var exit_timer := 0.0
const EXIT_HOLD := 1.5

# ─── VFX ───────────────────────────────────────────────────────────────────
var particles: Array[Dictionary] = []

# ─── Colors ────────────────────────────────────────────────────────────────
const COLD_COL   := Color(0.25, 0.4, 0.85)
const WARM_COL   := Color(0.9, 0.5, 0.2)
const SOLID_COL  := Color(0.2, 0.2, 0.27)


func _ready() -> void:
	dialogue.dialogue_finished.connect(_on_dialogue_done)
	_build_level()


func _build_level() -> void:
	# ═══ GROUND (always solid) ══════════════════════════════════════════
	_add_plat(Rect2(0, 610, 1280, 110), "solid")

	# ═══ SECTION 1: Blame helps Denial cross ════════════════════════════
	# Neutral platforms both can use to start
	_add_plat(Rect2(80, 530, 160, 12), "solid")      # Left starting ledge
	_add_plat(Rect2(320, 530, 100, 12), "solid")      # Mid-left ledge

	# Cold ghost platforms — Blame must stand nearby on the solid ledge
	# so Denial can cross these to reach the other side
	_add_plat(Rect2(470, 510, 90, 10), "cold")
	_add_plat(Rect2(590, 490, 90, 10), "cold")
	_add_plat(Rect2(710, 510, 90, 10), "cold")

	# Landing platform after the cold crossing
	_add_plat(Rect2(850, 520, 140, 12), "solid")

	# ═══ SECTION 2: Denial helps Blame climb ════════════════════════════
	# Denial stands on the right solid platform to solidify warm ghosts
	_add_plat(Rect2(950, 440, 130, 12), "solid")      # Denial's perch (right)

	# Warm ghost platforms — Denial must be on her perch nearby
	_add_plat(Rect2(780, 420, 90, 10), "warm")
	_add_plat(Rect2(630, 400, 90, 10), "warm")
	_add_plat(Rect2(480, 420, 90, 10), "warm")

	# Landing for Blame after warm crossing
	_add_plat(Rect2(300, 430, 140, 12), "solid")

	# ═══ SECTION 3: Both climb together (alternating) ═══════════════════
	# Neutral meeting point
	_add_plat(Rect2(180, 360, 120, 12), "solid")

	# Blame solidifies these for Denial
	_add_plat(Rect2(350, 330, 80, 10), "cold")
	_add_plat(Rect2(470, 310, 80, 10), "cold")

	# Neutral checkpoint
	_add_plat(Rect2(580, 290, 120, 12), "solid")

	# Denial solidifies these for Blame
	_add_plat(Rect2(730, 270, 80, 10), "warm")
	_add_plat(Rect2(850, 250, 80, 10), "warm")

	# Neutral checkpoint
	_add_plat(Rect2(960, 230, 120, 12), "solid")

	# ═══ SECTION 4: Final climb to exit ═════════════════════════════════
	# Mixed ghost platforms — need to leapfrog
	_add_plat(Rect2(830, 180, 80, 10), "cold")
	_add_plat(Rect2(700, 150, 80, 10), "warm")
	_add_plat(Rect2(560, 120, 80, 10), "cold")
	_add_plat(Rect2(420, 100, 80, 10), "warm")

	# Exit platform
	_add_plat(Rect2(555, 55, 170, 14), "solid")

	# ═══ GEMS ═══════════════════════════════════════════════════════════
	# Cold gems for Blame — along Denial's crossing paths
	gems.append({"pos": Vector2(510, 490), "type": "cold", "collected": false})
	gems.append({"pos": Vector2(750, 490), "type": "cold", "collected": false})
	gems.append({"pos": Vector2(670, 380), "type": "cold", "collected": false})
	gems.append({"pos": Vector2(390, 310), "type": "cold", "collected": false})
	gems.append({"pos": Vector2(600, 100), "type": "cold", "collected": false})

	# Warm gems for Denial — along Blame's crossing paths
	gems.append({"pos": Vector2(820, 400), "type": "warm", "collected": false})
	gems.append({"pos": Vector2(520, 400), "type": "warm", "collected": false})
	gems.append({"pos": Vector2(510, 290), "type": "warm", "collected": false})
	gems.append({"pos": Vector2(890, 230), "type": "warm", "collected": false})
	gems.append({"pos": Vector2(460, 80), "type": "warm", "collected": false})


func _add_plat(rect: Rect2, type: String) -> void:
	platforms.append({"rect": rect, "type": type, "solidity": 1.0 if type == "solid" else 0.0, "grace_timer": 0.0})


func _process(delta: float) -> void:
	pulse_time += delta

	if phase == 2:
		GameManager.advance_phase()
		return
	if phase == 1:
		queue_redraw()
		return

	_update_platform_solidity(delta)
	_update_player(true, delta)
	_update_player(false, delta)
	_check_gems()
	_update_guilt_shadow(delta)
	_update_particles(delta)
	_check_exit(delta)

	# Clarity depletion = reset to ground
	if clarity <= 0:
		clarity = 50.0
		p1_pos = Vector2(200, 580)
		p2_pos = Vector2(300, 580)
		p1_vel = Vector2.ZERO
		p2_vel = Vector2.ZERO
		shadow_pos = Vector2(640, 700)

	queue_redraw()


func _update_platform_solidity(delta: float) -> void:
	for plat: Dictionary in platforms:
		if plat["type"] == "solid":
			plat["solidity"] = 1.0
			continue

		var rect: Rect2 = plat["rect"]
		var center: Vector2 = rect.get_center()
		var needs_p1: bool = plat["type"] == "cold"   # Cold needs Blame
		var provider_pos: Vector2 = p1_pos if needs_p1 else p2_pos
		var dist: float = provider_pos.distance_to(center)

		if dist < PRESENCE_RANGE:
			plat["grace_timer"] = GRACE_DURATION
			plat["solidity"] = minf(float(plat["solidity"]) + SOLIDIFY_SPEED * delta, 1.0)
		else:
			plat["grace_timer"] = maxf(float(plat["grace_timer"]) - delta, 0.0)
			if float(plat["grace_timer"]) <= 0.0:
				plat["solidity"] = maxf(float(plat["solidity"]) - SOLIDIFY_SPEED * 0.6 * delta, 0.0)


func _update_player(is_p1: bool, delta: float) -> void:
	var pos: Vector2 = p1_pos if is_p1 else p2_pos
	var vel: Vector2 = p1_vel if is_p1 else p2_vel
	var on_ground := false

	var dir_x := 0.0
	if is_p1:
		if Input.is_action_pressed("p1_left"):  dir_x -= 1.0
		if Input.is_action_pressed("p1_right"): dir_x += 1.0
	else:
		if Input.is_action_pressed("p2_left"):  dir_x -= 1.0
		if Input.is_action_pressed("p2_right"): dir_x += 1.0

	vel.x = lerpf(vel.x, dir_x * PLAYER_SPEED, 12.0 * delta)
	vel.y += GRAVITY * delta
	pos += vel * delta

	# Platform collision — only if solid enough (>0.5)
	for plat: Dictionary in platforms:
		if float(plat["solidity"]) < 0.5:
			continue
		var rect: Rect2 = plat["rect"]
		var foot_y: float = pos.y + PLAYER_SIZE
		if vel.y >= 0 and foot_y >= rect.position.y and foot_y <= rect.position.y + 14.0 \
			and pos.x + PLAYER_SIZE > rect.position.x and pos.x - PLAYER_SIZE < rect.end.x:
			pos.y = rect.position.y - PLAYER_SIZE
			vel.y = 0.0
			on_ground = true

	# Fell off the bottom — penalty
	if pos.y > 650:
		clarity -= FALL_PENALTY
		# Respawn at nearest solid platform below where they fell
		pos = Vector2(clampf(pos.x, 100, 1180), 580.0)
		vel = Vector2.ZERO
		on_ground = true
		_spawn_burst(pos, Color(0.5, 0.2, 0.2), 8)

	pos.x = clampf(pos.x, PLAYER_SIZE, 1280.0 - PLAYER_SIZE)

	# Jump
	if on_ground:
		if is_p1 and Input.is_action_just_pressed("p1_up"):
			vel.y = JUMP_SPEED
			on_ground = false
		elif not is_p1 and Input.is_action_just_pressed("p2_up"):
			vel.y = JUMP_SPEED
			on_ground = false

	if is_p1:
		p1_pos = pos; p1_vel = vel; p1_on_ground = on_ground
	else:
		p2_pos = pos; p2_vel = vel; p2_on_ground = on_ground


func _check_gems() -> void:
	for gem: Dictionary in gems:
		if gem["collected"]:
			continue
		var gp: Vector2 = gem["pos"]
		var gt: String = gem["type"]
		if gt == "cold" and p1_pos.distance_to(gp) < GEM_RADIUS + PLAYER_SIZE:
			gem["collected"] = true
			clarity = minf(clarity + GEM_RESTORE, CLARITY_MAX)
			_spawn_burst(gp, COLD_COL, 10)
		elif gt == "warm" and p2_pos.distance_to(gp) < GEM_RADIUS + PLAYER_SIZE:
			gem["collected"] = true
			clarity = minf(clarity + GEM_RESTORE, CLARITY_MAX)
			_spawn_burst(gp, WARM_COL, 10)


func _update_guilt_shadow(delta: float) -> void:
	shadow_hit_cooldown = maxf(shadow_hit_cooldown - delta, 0.0)

	if not shadow_active:
		shadow_activate_timer -= delta
		if shadow_activate_timer <= 0:
			shadow_active = true
		return

	# Chase the midpoint between players
	var target: Vector2 = (p1_pos + p2_pos) * 0.5
	var player_dist: float = p1_pos.distance_to(p2_pos)

	# Speed depends on how far apart players are
	var speed: float = lerpf(SHADOW_SPEED_CLOSE, SHADOW_SPEED_FAR,
		clampf((player_dist - 100.0) / 300.0, 0.0, 1.0))

	var dir: Vector2 = (target - shadow_pos).normalized()
	shadow_pos += dir * speed * delta

	# Hit detection
	if shadow_hit_cooldown <= 0:
		if shadow_pos.distance_to(p1_pos) < SHADOW_HIT_RANGE:
			clarity -= SHADOW_HIT_PENALTY
			shadow_hit_cooldown = 2.0
			p1_vel = (p1_pos - shadow_pos).normalized() * 200.0
			_spawn_burst(p1_pos, Color(0.3, 0.1, 0.2), 8)
		if shadow_pos.distance_to(p2_pos) < SHADOW_HIT_RANGE:
			clarity -= SHADOW_HIT_PENALTY
			shadow_hit_cooldown = 2.0
			p2_vel = (p2_pos - shadow_pos).normalized() * 200.0
			_spawn_burst(p2_pos, Color(0.3, 0.1, 0.2), 8)


func _check_exit(delta: float) -> void:
	var all_done := true
	for gem: Dictionary in gems:
		if not gem["collected"]:
			all_done = false
			break
	if not all_done:
		exit_timer = 0.0
		return

	var p1_on := p1_pos.x + PLAYER_SIZE > exit_rect.position.x and p1_pos.x - PLAYER_SIZE < exit_rect.end.x \
		and absf((p1_pos.y + PLAYER_SIZE) - exit_rect.position.y) < 20.0
	var p2_on := p2_pos.x + PLAYER_SIZE > exit_rect.position.x and p2_pos.x - PLAYER_SIZE < exit_rect.end.x \
		and absf((p2_pos.y + PLAYER_SIZE) - exit_rect.position.y) < 20.0
	if p1_on and p2_on:
		exit_timer += delta
		if exit_timer >= EXIT_HOLD:
			phase = 1
			_show_dialogue()
	else:
		exit_timer = 0.0


func _spawn_burst(pos: Vector2, col: Color, count: int) -> void:
	for _i in range(count):
		var angle: float = randf() * TAU
		var spd: float = randf_range(40.0, 140.0)
		particles.append({"pos": pos, "vel": Vector2(cos(angle), sin(angle)) * spd,
			"color": col, "life": 0.5, "max_life": 0.5})


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


# ═══════════════════════════════════════════════════════════════════════════
func _draw() -> void:
	# ── Platforms ──────────────────────────────────────────────────────
	for plat: Dictionary in platforms:
		var rect: Rect2 = plat["rect"]
		var sol: float = plat["solidity"]
		var ptype: String = plat["type"]

		if ptype == "solid":
			draw_rect(rect, SOLID_COL)
			draw_line(rect.position, Vector2(rect.end.x, rect.position.y), Color(0.35, 0.35, 0.42, 0.6), 1.5)
		else:
			# Ghost platform — fades based on solidity
			var base_col: Color = COLD_COL if ptype == "cold" else WARM_COL

			if sol < 0.5:
				# Ghostly — dashed outline only
				var ghost_a: float = 0.08 + sol * 0.3 + sin(pulse_time * 2.0) * 0.04
				draw_rect(rect, Color(base_col.r, base_col.g, base_col.b, ghost_a))
				# Dashed outline
				var dash_a: float = 0.15 + sol * 0.3
				for dx in range(0, int(rect.size.x), 12):
					if (dx / 12) % 2 == 0:
						var x1: float = rect.position.x + float(dx)
						var x2: float = minf(x1 + 8.0, rect.end.x)
						draw_line(Vector2(x1, rect.position.y), Vector2(x2, rect.position.y),
							Color(base_col.r, base_col.g, base_col.b, dash_a), 1.5)
			else:
				# Solid enough to stand on — fill + edge glow
				var fill_a: float = 0.3 + sol * 0.5
				draw_rect(rect, Color(base_col.r * 0.4, base_col.g * 0.4, base_col.b * 0.4, fill_a))
				draw_line(rect.position, Vector2(rect.end.x, rect.position.y),
					Color(base_col.r, base_col.g, base_col.b, sol * 0.6), 2.0)
				# Glow aura
				draw_rect(Rect2(rect.position.x - 2, rect.position.y - 2, rect.size.x + 4, rect.size.y + 4),
					Color(base_col.r, base_col.g, base_col.b, sol * 0.1), false, 2.0)

	# ── Presence range indicators (subtle) ────────────────────────────
	# Show faint circles around players indicating their solidify range
	var p1_range_a: float = 0.04 + sin(pulse_time * 1.5) * 0.015
	draw_arc(p1_pos, PRESENCE_RANGE, 0, TAU, 32, Color(COLD_COL.r, COLD_COL.g, COLD_COL.b, p1_range_a), 1.0)
	var p2_range_a: float = 0.04 + sin(pulse_time * 1.5 + 1.0) * 0.015
	draw_arc(p2_pos, PRESENCE_RANGE, 0, TAU, 32, Color(WARM_COL.r, WARM_COL.g, WARM_COL.b, p2_range_a), 1.0)

	# ── Guilt Shadow ──────────────────────────────────────────────────
	if shadow_active:
		var sa: float = 0.5 + sin(pulse_time * 3.0) * 0.1
		var sz: float = 25.0 + sin(pulse_time * 2.0) * 5.0
		draw_circle(shadow_pos, sz, Color(0.1, 0.05, 0.12, sa))
		draw_circle(shadow_pos, sz * 0.5, Color(0.15, 0.08, 0.18, sa * 0.6))
		# Eyes
		draw_circle(shadow_pos + Vector2(-7, -5), 3, Color(0.5, 0.1, 0.1, sa))
		draw_circle(shadow_pos + Vector2(7, -5), 3, Color(0.5, 0.1, 0.1, sa))
		# Tendrils
		for i in range(4):
			var angle: float = pulse_time * 0.5 + float(i) * TAU / 4.0
			var tend: Vector2 = shadow_pos + Vector2(cos(angle), sin(angle)) * (sz + 15.0)
			draw_line(shadow_pos, tend, Color(0.12, 0.06, 0.15, sa * 0.4), 2.0)

	# ── Gems ──────────────────────────────────────────────────────────
	for gem: Dictionary in gems:
		if gem["collected"]:
			continue
		var gp: Vector2 = gem["pos"]
		var gc: Color = COLD_COL if gem["type"] == "cold" else WARM_COL
		var bob: float = sin(pulse_time * 2.2 + gp.x * 0.03) * 3.0
		var dp: Vector2 = gp + Vector2(0, bob)
		var pts := PackedVector2Array([
			dp + Vector2(0, -GEM_RADIUS * 1.4), dp + Vector2(GEM_RADIUS, 0),
			dp + Vector2(0, GEM_RADIUS * 1.4), dp + Vector2(-GEM_RADIUS, 0)])
		draw_colored_polygon(pts, gc)
		draw_circle(dp, GEM_RADIUS + 3, Color(gc.r, gc.g, gc.b, 0.1))

	# ── Exit ──────────────────────────────────────────────────────────
	var all_gems := true
	for gem: Dictionary in gems:
		if not gem["collected"]:
			all_gems = false
			break
	var ea: float = 0.3 + sin(pulse_time * 2.5) * 0.1 if all_gems else 0.08
	draw_rect(exit_rect, Color(0.35, 0.8, 0.45, ea))
	draw_string(ThemeDB.fallback_font, exit_rect.get_center() + Vector2(-12, -5),
		"EXIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.9, 0.55, ea + 0.2))
	if exit_timer > 0:
		draw_arc(exit_rect.get_center() + Vector2(0, -22), 14, -PI * 0.5, -PI * 0.5 + TAU * (exit_timer / EXIT_HOLD), 24, Color(0.5, 0.9, 0.55, 0.8), 3.0)

	# ── Particles ─────────────────────────────────────────────────────
	for p: Dictionary in particles:
		var a: float = float(p["life"]) / float(p["max_life"])
		var pc: Color = Color(p["color"])
		pc.a = a
		draw_circle(Vector2(p["pos"]), 2.5, pc)

	# ── Players ───────────────────────────────────────────────────────
	# P1 Blame
	draw_rect(Rect2(p1_pos - Vector2(PLAYER_SIZE, PLAYER_SIZE), Vector2(PLAYER_SIZE * 2, PLAYER_SIZE * 2)),
		GameManager.get_blame_color())
	draw_rect(Rect2(p1_pos - Vector2(PLAYER_SIZE * 0.5, PLAYER_SIZE * 0.5), Vector2(PLAYER_SIZE, PLAYER_SIZE)),
		Color(GameManager.get_blame_color_light(), 0.3))
	draw_rect(Rect2(p1_pos.x - 5, p1_pos.y - 7, 3, 3), Color(0.7, 0.8, 1.0, 0.8))
	draw_rect(Rect2(p1_pos.x + 2, p1_pos.y - 7, 3, 3), Color(0.7, 0.8, 1.0, 0.8))

	# P2 Denial
	draw_circle(p2_pos, PLAYER_SIZE, GameManager.get_denial_color())
	draw_circle(p2_pos, PLAYER_SIZE * 0.55, Color(GameManager.get_denial_color_light(), 0.3))
	draw_circle(Vector2(p2_pos.x - 4, p2_pos.y - 5), 2, Color(0.95, 0.85, 0.7, 0.8))
	draw_circle(Vector2(p2_pos.x + 4, p2_pos.y - 5), 2, Color(0.95, 0.85, 0.7, 0.8))

	# ── HUD ───────────────────────────────────────────────────────────
	# Clarity meter
	var cbar_w: float = (clarity / CLARITY_MAX) * 180.0
	var cbar_col: Color = Color(0.5, 0.7, 0.8, 0.5) if clarity > 30 else Color(0.8, 0.3, 0.3, 0.6)
	draw_rect(Rect2(550, 16, cbar_w, 7), cbar_col)
	draw_rect(Rect2(550, 16, 180, 7), Color(0.3, 0.3, 0.35, 0.3), false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(555, 38), "clarity", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.5, 0.6, 0.5))

	# Gem count
	var collected: int = 0
	for gem: Dictionary in gems:
		if gem["collected"]: collected += 1
	draw_string(ThemeDB.fallback_font, Vector2(690, 38),
		str(collected) + "/" + str(gems.size()), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.7, 0.85, 0.5))

	# Hint (first few seconds)
	if pulse_time < 6.0:
		var hint_a: float = maxf(0.0, 1.0 - pulse_time / 6.0) * 0.6
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(380, 580), "Your presence solidifies matching platforms", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.6, 0.7, hint_a))
		draw_string(font, Vector2(445, 600), "Stay close to weaken the shadow", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.6, 0.7, hint_a * 0.7))


func _show_dialogue() -> void:
	var lines: Array[Dictionary] = [
		{"speaker": "Blame", "text": "So she wasn't a random stranger. We weren't each other's burden. We were each other's reason.", "color": GameManager.get_blame_color_light()},
		{"speaker": "Denial", "text": "But she trusted me. She loved us so much.", "color": GameManager.get_denial_color_light()},
	]
	dialogue.play_dialogue(lines)


func _on_dialogue_done() -> void:
	phase = 2
