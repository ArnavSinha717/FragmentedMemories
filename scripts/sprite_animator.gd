class_name SpriteAnimator

## Utility for extracting and drawing frames from sprite sheets.
## Used by scenes to animate characters and VFX from asset packs.

var texture: Texture2D
var frame_width: int
var frame_height: int
var total_cols: int
var total_rows: int


func _init(tex: Texture2D, fw: int, fh: int) -> void:
	texture = tex
	frame_width = fw
	frame_height = fh
	if texture:
		total_cols = maxi(1, int(texture.get_width()) / fw)
		total_rows = maxi(1, int(texture.get_height()) / fh)
	else:
		total_cols = 1
		total_rows = 1


func get_frame_rect(col: int, row: int) -> Rect2:
	return Rect2(col * frame_width, row * frame_height, frame_width, frame_height)


func get_frame_by_index(index: int) -> Rect2:
	var col: int = index % total_cols
	var row: int = index / total_cols
	return Rect2(col * frame_width, row * frame_height, frame_width, frame_height)


func draw_frame(canvas: CanvasItem, pos: Vector2, col: int, row: int,
		scale: float = 1.0, flip_h: bool = false, modulate: Color = Color.WHITE) -> void:
	if not texture:
		return
	var src: Rect2 = get_frame_rect(col, row)
	var dest_size := Vector2(frame_width * scale, frame_height * scale)
	if flip_h:
		dest_size.x = -dest_size.x
	var dest := Rect2(pos - Vector2(absf(dest_size.x), dest_size.y) * 0.5, Vector2(absf(dest_size.x), dest_size.y))
	if flip_h:
		dest.position.x += dest.size.x
		dest.size.x = -dest.size.x
	canvas.draw_texture_rect_region(texture, dest, src, modulate)


func draw_frame_index(canvas: CanvasItem, pos: Vector2, index: int,
		scale: float = 1.0, flip_h: bool = false, modulate: Color = Color.WHITE) -> void:
	if not texture:
		return
	var src: Rect2 = get_frame_by_index(index)
	var dest_size := Vector2(frame_width * scale, frame_height * scale)
	var dest := Rect2(pos - Vector2(absf(dest_size.x), dest_size.y) * 0.5, Vector2(absf(dest_size.x), dest_size.y))
	if flip_h:
		dest.position.x += dest.size.x
		dest.size.x = -dest.size.x
	canvas.draw_texture_rect_region(texture, dest, src, modulate)


## Animate: returns the frame index based on time and FPS
static func anim_frame(time: float, frame_count: int, fps: float = 10.0, looping: bool = true) -> int:
	var frame: int = int(time * fps)
	if looping:
		return frame % maxi(frame_count, 1)
	else:
		return mini(frame, frame_count - 1)
