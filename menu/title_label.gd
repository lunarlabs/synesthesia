extends Label

const MAX_LINES: int = 32

func _ready() -> void:
	# update when resized / text changed
	connect("resized", Callable(self, "_update_shader"))
	connect("text_changed", Callable(self, "_update_shader"))
	_update_shader()

func _update_shader() -> void:
	if material == null or material is not ShaderMaterial:
		return

	var mat: ShaderMaterial = material

	# Get font and font size explicitly
	var font: Font = get_theme_font("font")
	var font_size: int = get_theme_font_size("font_size")

	# Create the shaped string (the analyzer can't infer the shaped-string type, so use Object)
	var shaper: Object = font.create_shaped_string(text, font_size) as Object
	# give it the Label's width so it performs wrapping like the Label would
	shaper.set_width(size.x)
	shaper.shape()

	var line_count: int = int(shaper.get_line_count())

	var offsets: PackedFloat32Array = PackedFloat32Array()
	var heights: PackedFloat32Array = PackedFloat32Array()

	# Sum total height in pixels first
	var total_height: float = 0.0
	for i in range(line_count):
		var line: Object = shaper.get_line(i) as Object
		var line_height: float = float(line.size.y)
		total_height += line_height

	# Protect against division by zero
	if total_height <= 0.0:
		# fallback: single-line full-height
		mat.set_shader_parameter("line_count", 1)
		mat.set_shader_parameter("line_offsets", PackedFloat32Array([0.0]))
		mat.set_shader_parameter("line_heights", PackedFloat32Array([1.0]))
		return

	var y_accum: float = 0.0
	for i in range(line_count):
		var line: Object = shaper.get_line(i) as Object
		var line_height: float = float(line.size.y)

		var uv_offset: float = y_accum / total_height
		var uv_height: float = line_height / total_height

		offsets.append(uv_offset)
		heights.append(uv_height)

		y_accum += line_height

	# Clamp number of lines to the shader array size (shader expects up to 32)
	var send_count: int = min(line_count, MAX_LINES)
	# If you want to always send MAX_LINES length arrays, pad them; otherwise shader uses line_count.
	# Here we send exactly 'send_count' entries.
	mat.set_shader_parameter("line_count", send_count)
	mat.set_shader_parameter("line_offsets", offsets)
	mat.set_shader_parameter("line_heights", heights)
