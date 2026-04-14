extends Node

# Configuration
const VU_COUNT = 16
const FREQ_MIN = 20.0
const FREQ_MAX = 15000.0 # 15k is usually the upper limit of useful visual data
const ATTACK_RATE = 25.0 # How fast the VU meter rises (higher = faster)
const DECAY_RATE = 10.0 # How fast the VU meter falls (lower = slower, more natural)

# State
var spectrum: AudioEffectSpectrumAnalyzerInstance
var spectrum_image: Image
var spectrum_texture: ImageTexture
var min_db = 60.0
var frequency_bands: Array[float] = []
var previous_magnitudes: Array[float] = []

func _ready():
	process_thread_group = Node.PROCESS_THREAD_GROUP_SUB_THREAD
	# Setup the arrays
	frequency_bands.resize(VU_COUNT)
	previous_magnitudes.resize(VU_COUNT)
	previous_magnitudes.fill(0.0)
	
	# Get the analyzer
	spectrum = AudioServer.get_bus_effect_instance(2, 0)
	spectrum_image = Image.create(VU_COUNT, 1, false, Image.FORMAT_RF)
	spectrum_texture = ImageTexture.create_from_image(spectrum_image)

func _process(delta):
	# 1. Calculate the "step" multiplier for logarithmic spacing
	# Math: We want to multiply our frequency by this factor to get to the next band
	var step_factor = pow(FREQ_MAX / FREQ_MIN, 1.0 / VU_COUNT)
	
	var prev_hz = FREQ_MIN
	
	for i in range(VU_COUNT):
		# Calculate the end frequency for this specific band
		var next_hz = prev_hz * step_factor
		
		# Get magnitude
		var magnitude = spectrum.get_magnitude_for_frequency_range(prev_hz, next_hz).length()
		
		# Convert to Decibels (Logarithmic loudness) for better visual scaling
		# Use explicit linear_to_db for clarity
		var energy = linear_to_db(magnitude)
		
		# Normalize: -60db becomes 0.0, 0db becomes 1.0
		var height = clamp((min_db + energy) / min_db, 0.0, 1)
		
		# Smooth the value with attack/decay (frame-rate independent)
		# Use faster attack when rising, slower decay when falling
		var smoothing_rate = ATTACK_RATE if height > previous_magnitudes[i] else DECAY_RATE
		var smoothed_height = lerp(previous_magnitudes[i], height, smoothing_rate * delta)
		previous_magnitudes[i] = smoothed_height
		
		# Store for use
		frequency_bands[i] = smoothed_height
		
		# Update the texture
		spectrum_image.set_pixel(i, 0, Color(smoothed_height, 0, 0))

		# Prepare for next iteration
		prev_hz = next_hz

	spectrum_texture.update(spectrum_image)
	RenderingServer.global_shader_parameter_set("viz", spectrum_texture)
