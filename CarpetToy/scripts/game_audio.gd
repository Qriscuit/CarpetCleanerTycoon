extends Node
## Four reusable voices; assets are rendered offline, never synthesized in play.
const MUSIC = preload("res://assets/audio/quiet_shop_music_loop.wav")
const FABRIC = preload("res://assets/audio/brush_fabric_loop.wav")
const SOIL = preload("res://assets/audio/brush_soil_loop.wav")
const COMPLETION = preload("res://assets/audio/restoration_complete.wav")
const CONTACT_HOLD := 0.075
var music_enabled := true
var effects_enabled := true
var music: AudioStreamPlayer
var fabric: AudioStreamPlayer
var grit: AudioStreamPlayer
var completion: AudioStreamPlayer
var context := "off"
var focused := true
var contact_remaining := 0.0
var fabric_target := 0.0
var grit_target := 0.0
var music_gain := 0.0
var fabric_gain := 0.0
var grit_gain := 0.0
var settings_path := "user://audio_settings.cfg"
var silent_test := false

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--shop-test" in args:
		settings_path = "res://.godot/audio_test_%d.cfg" % OS.get_process_id()
		silent_test = not "--audition-audio" in args
	load_settings()
	music = _voice("Music", MUSIC)
	fabric = _voice("BrushFabric", FABRIC)
	grit = _voice("BrushSoil", SOIL)
	completion = _voice("RestorationComplete", COMPLETION, false)

func _voice(label: String, source: AudioStreamWAV, looping: bool = true) -> AudioStreamPlayer:
	var voice := AudioStreamPlayer.new()
	voice.name = label
	voice.volume_db = -80.0
	add_child(voice)
	var frame_count := _sample_frame_count(source)
	if frame_count <= 0:
		push_warning("Audio source has no valid sample frames: " + label)
		return voice
	var stream := source.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if looping and frame_count > 1 else AudioStreamWAV.LOOP_DISABLED
	stream.loop_begin = 0
	# The pinned WAV mixer can decode its end limit inclusively. The frame
	# count is one past the final valid index; using it reads beyond PCM data.
	stream.loop_end = frame_count - 1
	voice.stream = stream
	return voice

static func _sample_frame_count(source: AudioStreamWAV) -> int:
	if source == null or source.mix_rate <= 0 or source.data.is_empty():
		return 0
	var bytes := source.data.size()
	var channels := 2 if source.stereo else 1
	match source.format:
		AudioStreamWAV.FORMAT_8_BITS, AudioStreamWAV.FORMAT_16_BITS:
			var frame_bytes := channels * (2 if source.format == AudioStreamWAV.FORMAT_16_BITS else 1)
			if bytes % frame_bytes != 0: return 0
		AudioStreamWAV.FORMAT_IMA_ADPCM:
			if bytes % channels != 0: return 0
		AudioStreamWAV.FORMAT_QOA:
			if bytes < 8: return 0 # The decoder needs a complete QOA header.
		_:
			return 0
	# get_length accounts for format, channel count and compressed headers.
	# Bytes/2 is valid only for mono PCM16, never for every imported WAV.
	var duration := source.get_length()
	if not is_finite(duration) or duration <= 0.0: return 0
	var frames := roundi(duration * source.mix_rate)
	return frames if frames > 0 and frames <= 2147483647 else 0

func set_context(value: String) -> void:
	context = value
	end_brush()
	if value == "off" and is_instance_valid(completion): completion.stop()

func play_completion() -> bool:
	# The full-restoration reveal owns this event, never ordinary brush input
	# or early finish. Repeated calls during the same cue cannot retrigger it.
	if context == "off" or not focused or not effects_enabled or not is_instance_valid(completion):
		return false
	if completion.playing: return false
	end_brush()
	completion.volume_linear = 0.0 if silent_test else 0.52
	completion.play()
	return true

func feed_brush(speed: float, surface_soil: float, removed_dirt: bool) -> void:
	if context != "cleaning" or not focused or not effects_enabled or speed <= 0.005:
		end_brush()
		return
	contact_remaining = CONTACT_HOLD
	var movement := clampf(speed / 1.8, 0.0, 1.0)
	fabric_target = lerpf(0.12, 0.58, sqrt(movement))
	grit_target = fabric_target * clampf(surface_soil, 0.0, 1.0) * 0.55 if removed_dirt else 0.0
	# No random restarts/pitch jumps: the cloth remains one continuous gesture.

func end_brush() -> void:
	contact_remaining = 0.0
	fabric_target = 0.0
	grit_target = 0.0

func _process(delta: float) -> void:
	if not is_instance_valid(music): return
	contact_remaining = maxf(0.0, contact_remaining - delta)
	if contact_remaining == 0.0:
		fabric_target = 0.0
		grit_target = 0.0
	var allow_effects := focused and effects_enabled and context == "cleaning"
	var attack := 1.0 - exp(-delta / 0.025)
	var release := 1.0 - exp(-delta / 0.045)
	var target_fabric := fabric_target if allow_effects else 0.0
	var target_grit := grit_target if allow_effects else 0.0
	fabric_gain = lerpf(fabric_gain, target_fabric, attack if target_fabric > fabric_gain else release)
	grit_gain = lerpf(grit_gain, target_grit, attack if target_grit > grit_gain else release)
	var target_music := 0.0
	if focused and music_enabled and context != "off":
		target_music = 0.40 if context == "home" else 0.22
		if fabric_target > 0.0: target_music *= 0.72
	music_gain = lerpf(music_gain, target_music, 1.0 - exp(-delta / 0.35))
	_apply_gain(music, music_gain)
	_apply_gain(fabric, fabric_gain)
	_apply_gain(grit, grit_gain)

func _apply_gain(voice: AudioStreamPlayer, gain: float) -> void:
	if gain < 0.0005:
		voice.stop()
		return
	voice.volume_linear = 0.0 if silent_test else gain
	if not voice.playing: voice.play()

func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	if not enabled:
		music_gain = 0.0
		music.stop()
	save_settings()

func set_effects_enabled(enabled: bool) -> void:
	effects_enabled = enabled
	if not enabled: _silence_effects()
	save_settings()

func _silence_brush() -> void:
	end_brush()
	fabric_gain = 0.0
	grit_gain = 0.0
	if is_instance_valid(fabric): fabric.stop()
	if is_instance_valid(grit): grit.stop()

func _silence_effects() -> void:
	_silence_brush()
	if is_instance_valid(completion): completion.stop()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		focused = false
		_silence_effects()
		music_gain = 0.0
		if is_instance_valid(music): music.stop()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		focused = true

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK: return
	var saved_music: Variant = config.get_value("audio", "music", true)
	var saved_effects: Variant = config.get_value("audio", "effects", true)
	music_enabled = saved_music if saved_music is bool else true
	effects_enabled = saved_effects if saved_effects is bool else true

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "music", music_enabled)
	config.set_value("audio", "effects", effects_enabled)
	if config.save(settings_path) != OK:
		push_warning("Audio preferences could not be saved")
