extends Node2D

## Persistent shard background drawn behind all scenes.
## Lives inside a CanvasLayer at layer -1 (behind everything).
## Reads shard data from GameManager and draws every frame.

var time_elapsed: float = 0.0
var ambient_timer: float = 0.0


func _process(delta: float) -> void:
	time_elapsed += delta

	if not GameManager.shards_generated:
		return

	# Ambient progressive decay — shards break slowly during gameplay
	if not GameManager.collapse_active:
		var phase: GameManager.Phase = GameManager.current_phase
		var decay_interval: float = 999.0  # No decay by default
		match phase:
			GameManager.Phase.MAIN_MENU: decay_interval = 999.0
			GameManager.Phase.INTRO_CUTSCENE: decay_interval = 8.0
			GameManager.Phase.COMPETITIVE_1: decay_interval = 0.6  # Fight breaks lots
			GameManager.Phase.COMPETITIVE_2: decay_interval = 1.5
			GameManager.Phase.COOPERATIVE_1: decay_interval = 2.0
			GameManager.Phase.COOPERATIVE_2: decay_interval = 2.5
			GameManager.Phase.TRANSITION_CUTSCENE: decay_interval = 3.0
			GameManager.Phase.FULL_MEMORY: decay_interval = 999.0  # Collapse handles this
			_: decay_interval = 4.0  # Gentle decay for cutscenes/reveals

		ambient_timer += delta
		if ambient_timer >= decay_interval:
			ambient_timer = 0.0
			GameManager.break_random_shards(1)

	# Update falling shards
	for i in range(GameManager.falling_shards.size() - 1, -1, -1):
		var fs: Dictionary = GameManager.falling_shards[i]
		fs.vel = (fs.vel as Vector2) + Vector2(0, 400) * delta
		fs.center = (fs.center as Vector2) + (fs.vel as Vector2) * delta
		fs.alpha = (fs.alpha as float) - delta * 0.7
		if (fs.alpha as float) <= 0 or (fs.center as Vector2).y > 800:
			GameManager.falling_shards.remove_at(i)

	# Collapse: rapidly break remaining shards
	if GameManager.collapse_active:
		GameManager.collapse_timer += delta
		var alive: int = GameManager.get_alive_shard_count()
		if alive > 0:
			# Break shards in waves — faster as collapse progresses
			var break_rate: int = maxi(1, int(GameManager.collapse_timer * 15.0))
			GameManager.break_random_shards(break_rate)
		# Collapse is done when all shards broken
		if alive <= 0:
			GameManager.collapse_active = false

	queue_redraw()


func _draw() -> void:
	if not GameManager.shards_generated:
		draw_rect(Rect2(0, 0, 1280, 720), Color(0.08, 0.08, 0.12))
		return

	# Base background color
	draw_rect(Rect2(0, 0, 1280, 720), GameManager.get_bg_color())

	# Draw all shards
	for shard: Dictionary in GameManager.shards:
		var pts: PackedVector2Array = shard.points
		if shard.alive:
			draw_colored_polygon(pts, shard.surface_color as Color)
			for j in range(pts.size()):
				draw_line(pts[j], pts[(j + 1) % pts.size()], shard.edge_color as Color, 1.0)
		else:
			draw_colored_polygon(pts, shard.revealed_color as Color)

	# Draw falling shards
	for fs: Dictionary in GameManager.falling_shards:
		var col: Color = fs.color
		col.a = fs.alpha
		var offset: Vector2 = (fs.center as Vector2) - _poly_center(fs.points as PackedVector2Array)
		var shifted := PackedVector2Array()
		for p in (fs.points as PackedVector2Array):
			shifted.append(p + offset)
		if shifted.size() >= 3:
			draw_colored_polygon(shifted, col)

	# Phase-specific overlays
	var phase: GameManager.Phase = GameManager.current_phase
	match phase:
		# Fog walk needs dark overlay — the scene handles its own darkness
		# but we still want the shard bg to show through faintly
		GameManager.Phase.COOPERATIVE_2:
			draw_rect(Rect2(0, 0, 1280, 720), Color(0.0, 0.0, 0.02, 0.85))
		# Fragment reveals: slight dim so images pop
		GameManager.Phase.FRAGMENT_REVEAL_1, GameManager.Phase.FRAGMENT_REVEAL_2, \
		GameManager.Phase.FRAGMENT_REVEAL_3, GameManager.Phase.FRAGMENT_REVEAL_4:
			draw_rect(Rect2(0, 0, 1280, 720), Color(0.0, 0.0, 0.0, 0.5))
		# Outro + reflection: mostly revealed, calm
		GameManager.Phase.REFLECTION:
			draw_rect(Rect2(0, 0, 1280, 720), Color(0.02, 0.02, 0.04, 0.3))


func _poly_center(pts: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in pts:
		sum += p
	return sum / maxf(float(pts.size()), 1.0)
