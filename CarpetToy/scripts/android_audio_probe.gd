extends Control
## Opt-in hardware regression for the AudioTrack loop-boundary crash.
## Exported only with -- --shop-test --audition-audio in a separate app.

const NATURAL_SECONDS := 30.0
const SEEK_ROUNDS := 24
var audio: Node
var started := 0
var checks := 0
var failures: Array[String] = []
var feeding := true
var wrap_counts := [0, 0, 0]
var last_positions := [0.0, 0.0, 0.0]
var voices: Array[AudioStreamPlayer] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("ANDROID_AUDIO_PROBE: " + message)

func _ready() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Sound probe requires -- --shop-test; refusing to run")
		get_tree().quit(2)
		return
	var ledger := get_node("/root/ShopState")
	check(str(ledger._save_path).contains("shop_test_"), "Ledger selected isolated test path")
	ledger.set_process(false)
	ledger._save_enabled = false
	audio = get_node("/root/GameAudio")
	check(str(audio.settings_path).contains("audio_test_"), "Audio selected isolated settings path")
	check(not audio.silent_test, "Hardware audio mixing enabled")
	audio.music_enabled = true
	audio.effects_enabled = true
	audio.focused = true
	audio.set_context("cleaning")
	voices.assign([audio.music, audio.fabric, audio.grit])
	for voice in voices:
		var stream := voice.stream as AudioStreamWAV
		check(stream != null, "Stream exists: " + voice.name)
		if stream != null:
			check(stream.loop_end == roundi(stream.get_length() * stream.mix_rate) - 1, "Inclusive loop boundary: " + voice.name)
	started = Time.get_ticks_msec()
	print("ANDROID_AUDIO_PROBE_START ", JSON.stringify({"engine": Engine.get_version_info(), "args": OS.get_cmdline_user_args(), "platform": OS.get_name(), "isolated_save": true}))
	_run.call_deferred()

func _process(_delta: float) -> void:
	if audio == null: return
	if feeding:
		audio.feed_brush(0.6, 1.0, true)
		for index in voices.size():
			var position := voices[index].get_playback_position()
			if position + 1.0 < last_positions[index]: wrap_counts[index] += 1
			last_positions[index] = position
	$Status.text = "Checking sound playback\n%d seconds" % ((Time.get_ticks_msec() - started) / 1000)

func _run() -> void:
	await get_tree().create_timer(NATURAL_SECONDS).timeout
	check(wrap_counts[0] >= 1, "Music crossed its 24-second boundary")
	check(wrap_counts[1] >= 6, "Fabric crossed its 4-second boundary repeatedly")
	check(wrap_counts[2] >= 6, "Soil crossed its 4-second boundary repeatedly")
	var natural_wraps := wrap_counts.duplicate()
	for _round in SEEK_ROUNDS:
		for voice in voices:
			voice.seek(voice.stream.get_length() - 0.012)
		await get_tree().create_timer(0.08).timeout
		for voice in voices:
			check(voice.playing, "Boundary seek stays playing: " + voice.name)
	feeding = false
	audio._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not audio.music.playing and not audio.fabric.playing and not audio.grit.playing, "Focus loss silences voices")
	await get_tree().create_timer(0.15).timeout
	audio._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	feeding = true
	await get_tree().create_timer(0.25).timeout
	for voice in voices: check(voice.playing, "Focus return resumes sustained contact: " + voice.name)
	feeding = false
	audio.set_context("off")
	audio.music.stop()
	audio.fabric.stop()
	audio.grit.stop()
	var result := {"engine": Engine.get_version_info(), "platform": OS.get_name(), "isolated_save": true, "natural_seconds": NATURAL_SECONDS, "natural_wrap_counts_music_fabric_soil": natural_wraps, "seek_rounds_per_voice": SEEK_ROUNDS, "checks": checks, "failure_count": failures.size(), "failures": failures, "elapsed_seconds": (Time.get_ticks_msec() - started) / 1000.0}
	var file := FileAccess.open("user://android_audio_probe.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
	print("ANDROID_AUDIO_PROBE_COMPLETE ", JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)
