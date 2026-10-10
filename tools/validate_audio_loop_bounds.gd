extends SceneTree
## Exercise the native WAV mixer across the production loop boundaries.
## Isolated -- --shop-test is mandatory; no physical audio is emitted.

const AudioController = preload("res://scripts/game_audio.gd")
var checks := 0
var failures := 0
var crossed_boundaries := 0
var fixtures: Array[Dictionary] = []
var live_loop_wraps: Dictionary = {"fabric": 0, "soil": 0}
var live_seconds := 0.0
var audio: Node

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test to protect player audio preferences and saves")
		quit(2)
		return
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("AUDIO LOOP: " + message)

func exercise_stream(label: String, source: AudioStreamWAV, expected: int = -1) -> void:
	var imported_mode := source.loop_mode
	var imported_end := source.loop_end
	var imported_data := source.data
	var frames := AudioController._sample_frame_count(source)
	check(frames > 1, label + " exposes multiple decoded frames")
	if expected >= 0: check(frames == expected, label + " decoded frame count")
	var voice: AudioStreamPlayer = audio._voice(label, source)
	var stream := voice.stream as AudioStreamWAV
	check(stream != null and stream != source, label + " duplicates the immutable source")
	if stream == null:
		voice.free()
		return
	check(stream.loop_begin == 0 and stream.loop_end == frames - 1 and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, label + " loop is inside the decoded allocation")
	check(source.loop_mode == imported_mode and source.loop_end == imported_end and source.data == imported_data, label + " never mutates imported data or bounds")
	var playback := stream.instantiate_playback()
	# Different block sizes/starts reproduce the inclusive mixer boundary
	# independently of whether a desktop allocator happens to tolerate an OOB read.
	for block in [128, 257, 1024, 4096]:
		playback.start(maxf(0.0, stream.get_length() - 64.0 / stream.mix_rate))
		var mixed := playback.mix_audio(1.0, block)
		check(mixed.size() == block and playback.is_playing(), label + " wraps native mixer block " + str(block))
		var valid := true
		for value: Vector2 in mixed:
			if not value.is_finite() or value.abs().x > 1.2 or value.abs().y > 1.2:
				valid = false
				break
		check(valid, label + " native samples remain finite and in range")
		crossed_boundaries += 1
		playback.stop()
	fixtures.append({"name": label, "format": source.format, "stereo": source.stereo, "mix_rate": source.mix_rate, "decoded_frames": frames, "data_bytes": source.data.size(), "loop_end": stream.loop_end})
	voice.free()

func pcm_fixture(bits: int, stereo: bool) -> AudioStreamWAV:
	var source := AudioStreamWAV.new()
	source.format = AudioStreamWAV.FORMAT_16_BITS if bits == 16 else AudioStreamWAV.FORMAT_8_BITS
	source.stereo = stereo
	source.mix_rate = 44100
	var data := PackedByteArray()
	data.resize(1024 * (2 if bits == 16 else 1) * (2 if stereo else 1))
	data.fill(0)
	source.data = data
	return source

func exercise_live_hold() -> void:
	# Physical output stays muted, but the actual player/mixer advances under
	# continuous brush contact for longer than two four-second sound loops.
	audio.set_context("cleaning")
	audio.focused = true
	audio.effects_enabled = true
	var started := Time.get_ticks_msec()
	var previous_fabric := 0.0
	var previous_soil := 0.0
	while Time.get_ticks_msec() - started < 9200:
		# This standalone mixer harness may lose desktop window focus while
		# another diagnostic runs. Keep its deliberate contact fixture focused.
		audio.focused = true
		audio.feed_brush(1.5, 1.0, true)
		await process_frame
		var fabric_position: float = audio.fabric.get_playback_position()
		var soil_position: float = audio.grit.get_playback_position()
		if fabric_position + 0.25 < previous_fabric: live_loop_wraps.fabric += 1
		if soil_position + 0.25 < previous_soil: live_loop_wraps.soil += 1
		previous_fabric = fabric_position
		previous_soil = soil_position
	live_seconds = (Time.get_ticks_msec() - started) / 1000.0
	check(int(live_loop_wraps.fabric) >= 2 and int(live_loop_wraps.soil) >= 2, "Real-time fabric and soil playback each crosses two loop boundaries")
	audio.set_context("off")
	audio._silence_effects()

func run() -> void:
	audio = root.get_node("GameAudio")
	audio.set_context("off")
	root.get_node("ShopState").set_process(false)
	var voice_count := audio.get_child_count()
	exercise_stream("ProductionMusic", AudioController.MUSIC, 1058400)
	exercise_stream("ProductionFabric", AudioController.FABRIC, 176400)
	exercise_stream("ProductionSoil", AudioController.SOIL, 176400)
	for bits in [8, 16]:
		for stereo in [false, true]:
			exercise_stream("PCM%d_%s" % [bits, "stereo" if stereo else "mono"], pcm_fixture(bits, stereo), 1024)
	var raw := FileAccess.get_file_as_bytes("res://assets/audio/brush_fabric_loop.wav")
	for compression in [1, 2]:
		var source := AudioStreamWAV.load_from_buffer(raw, {"compress/mode": compression})
		check(source != null, "Compressed fixture imports " + str(compression))
		if source != null: exercise_stream("Compressed%d" % compression, source)
	var empty := AudioStreamWAV.new()
	check(AudioController._sample_frame_count(empty) == 0, "Empty stream has no readable frames")
	var rejected: AudioStreamPlayer = audio._voice("EmptyFixture", empty)
	check(rejected.stream == null, "Empty source is rejected without enabling a loop")
	rejected.free()
	var incomplete := pcm_fixture(16, true)
	incomplete.data = PackedByteArray([0, 0, 0])
	check(AudioController._sample_frame_count(incomplete) == 0, "Incomplete stereo PCM frame is rejected")
	var one_shot: AudioStreamPlayer = audio._voice("OneShotFixture", AudioController.COMPLETION, false)
	var one_stream := one_shot.stream as AudioStreamWAV
	check(one_stream != null and one_stream.loop_mode == AudioStreamWAV.LOOP_DISABLED and one_stream.loop_end == 37043, "Completion remains one complete finite cue")
	if one_stream != null:
		var playback := one_stream.instantiate_playback()
		playback.start(one_stream.get_length() - 64.0 / one_stream.mix_rate)
		playback.mix_audio(1.0, 8192)
		check(not playback.is_playing(), "Native one-shot mixer stops at its actual end")
	one_shot.free()
	check(audio.get_child_count() == voice_count, "Fixture voices leave the four production voices intact")
	if "--audio-live-hold" in OS.get_cmdline_user_args(): await exercise_live_hold()
	var report := {"engine": Engine.get_version_info(), "checks": checks, "failures": failures, "native_boundary_cases": crossed_boundaries, "fixtures": fixtures, "real_time_hold_seconds": live_seconds, "real_time_loop_wraps": live_loop_wraps}
	var file := FileAccess.open("res://../build/audio_loop_bounds_validation.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("AUDIO_LOOP_BOUNDS ", checks, " checks, ", failures, " failures; ", crossed_boundaries, " native mixer boundary cases")
	quit(0 if failures == 0 else 1)
