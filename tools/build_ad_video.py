"""Assemble a normal-speed game ad from recorded takes and the original vector kit.

All paths in the edit JSON are relative to that JSON. Raw sources are read-only.
Requires installed ffmpeg/ffprobe and the bundled Node runtime with Sharp.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "tools" / "render_ad_assets.cjs"
FPS = 30
WIDTH, HEIGHT = 1080, 1920
STILL_KINDS = ("endcard", "freeze", "hero")


def run(args, *, capture=False):
    result = subprocess.run([str(v) for v in args], text=True, stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE if capture else None, check=False)
    if result.returncode:
        if capture:
            print(result.stderr, file=sys.stderr)
        raise RuntimeError(f"Command failed with status {result.returncode}: {args[0]}")
    return result.stdout if capture else None


def probe(path, ffprobe):
    return json.loads(run([ffprobe, "-v", "error", "-show_streams", "-show_format", "-of", "json", path], capture=True))


def resolve(base, value):
    return (base / value).resolve()


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for part in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(part)
    return digest.hexdigest()


def source_color(stream, clip):
    """JPEG's 601 matrix describes YUV coefficients, not a request to retint RGB art."""
    matrix = clip.get("source_matrix") or {
        "bt470bg": "bt601", "smpte170m": "bt601", "bt709": "bt709",
        "bt2020nc": "bt2020", "smpte240m": "smpte240m",
    }.get(stream.get("color_space"), "bt601")
    video_range = clip.get("source_range") or stream.get("color_range")
    if video_range not in ("pc", "tv"):
        video_range = "pc" if stream.get("pix_fmt", "").startswith(("yuvj", "rgb", "bgr", "gbr")) else "tv"
    return matrix, video_range


def video_filter(crop=None, matrix="bt601", video_range="pc"):
    parts = []
    if crop:
        x, y, w, h = crop
        parts.append(f"crop={w}:{h}:{x}:{y}")
    # A crop is a framing choice. Every subsequent resize keeps the original aspect.
    # Decode the actual source YUV matrix/range into RGB before compositing PNG art.
    # Merely tagging a 601 YUV picture as 709 shifts the game's and vector kit's hues.
    parts.extend([f"scale={WIDTH}:{HEIGHT}:force_original_aspect_ratio=decrease:flags=lanczos:"
                  f"in_color_matrix={matrix}:in_range={video_range}:out_range=pc", "format=rgba",
                  f"pad={WIDTH}:{HEIGHT}:(ow-iw)/2:(oh-ih)/2:color=0xFFF5DD",
                  "setsar=1", f"fps={FPS}"])
    return ",".join(parts)


def overlay_layers(clip):
    """Normalize the original caption schema and the independently animated layers."""
    layers = []
    if clip.get("overlay"):
        motion = {"enter": clip.get("overlay_intro_seconds", .14), "rise": 12}
        motion.update(clip.get("overlay_motion") or {})
        layers.append({"source": clip["overlay"], "motion": motion})
    layers.extend(clip.get("overlays", []))
    return layers


def layer_settings(layer, duration):
    if not isinstance(layer, dict) or not layer.get("source"):
        raise ValueError("Each overlay layer must supply a source path.")
    motion = layer.get("motion") or {}
    settings = {"at": float(layer.get("at", 0)), "until": float(layer.get("until", duration)),
                "enter": float(motion.get("enter", .22)), "exit": float(motion.get("exit", 0)),
                "rise": float(motion.get("rise", 14)), "float": float(motion.get("float", 0)),
                "period": float(motion.get("period", 3))}
    if not all(math.isfinite(value) for value in settings.values()):
        raise ValueError("Overlay timing and motion must be finite numbers.")
    if not 0 <= settings["at"] < settings["until"] <= duration:
        raise ValueError("Overlay at/until must be inside the clip duration.")
    if min(settings["enter"], settings["exit"]) < 0:
        raise ValueError("Overlay enter and exit durations cannot be negative.")
    if settings["enter"] + settings["exit"] > settings["until"] - settings["at"]:
        raise ValueError("Overlay enter and exit durations exceed the layer duration.")
    if settings["period"] <= 0:
        raise ValueError("Overlay floating period must be positive.")
    return settings


def validate(edit, base, ffprobe):
    if not edit.get("recorded_gameplay"):
        raise ValueError("Set recorded_gameplay=true only after the referenced takes have actually been recorded.")
    if not edit.get("clips"):
        raise ValueError("No clips supplied.")
    total_frames = 0
    sources = {}
    for clip in edit["clips"]:
        if clip.get("kind", "gameplay") not in ("gameplay", *STILL_KINDS):
            raise ValueError(f"Clip {clip.get('id')}: unknown kind.")
        frames = clip.get("frames")
        if not isinstance(frames, int) or frames <= 0:
            raise ValueError(f"Clip {clip.get('id')}: frames must be a positive integer.")
        total_frames += frames
        src = resolve(base, clip["source"])
        if not src.is_file():
            raise FileNotFoundError(src)
        if src not in sources:
            sources[src] = probe(src, ffprobe)
        info = sources[src]
        video = next((s for s in info["streams"] if s["codec_type"] == "video"), None)
        if not video:
            raise ValueError(f"No video stream: {src}")
        start = float(clip.get("in", 0))
        duration = float(info.get("format", {}).get("duration", video.get("duration", 0)))
        required = start + (1 / FPS if clip.get("kind") in STILL_KINDS else frames / FPS)
        if start < 0 or (duration and required > duration + 1 / FPS):
            raise ValueError(f"Clip {clip['id']} extends beyond the recording ({required:.3f} > {duration:.3f}).")
        crop = clip.get("crop")
        if crop:
            if len(crop) != 4 or any(not isinstance(v, int) for v in crop):
                raise ValueError("crop must be four integer source pixels [x,y,width,height].")
            x, y, w, h = crop
            if min(x, y) < 0 or min(w, h) <= 0 or x + w > video["width"] or y + h > video["height"]:
                raise ValueError(f"Clip {clip['id']} crop exceeds {video['width']}×{video['height']} source.")
        for key in ("background", "audio_source"):
            if clip.get(key) and not resolve(base, clip[key]).is_file():
                raise FileNotFoundError(resolve(base, clip[key]))
        for layer in overlay_layers(clip):
            layer_settings(layer, frames / FPS)
            if not resolve(base, layer["source"]).is_file():
                raise FileNotFoundError(resolve(base, layer["source"]))
            if layer["source"].endswith("safe_guide.svg"):
                raise ValueError("The internal framing guide must never be exported.")
        if clip.get("kind") in ("freeze", "hero"):
            zoom = clip.get("freeze_zoom", [1, 1.03])
            if (not isinstance(zoom, list) or len(zoom) != 2 or
                    any(not isinstance(v, (int, float)) or not math.isfinite(v) or not 1 <= v <= 1.15 for v in zoom)):
                raise ValueError("freeze_zoom must be [start,end], with factors between 1 and 1.15.")
        if clip.get("speed", 1) != 1:
            raise ValueError("This edit only supports normal-speed game footage.")
    if total_frames != edit.get("total_frames", total_frames):
        raise ValueError("Clip frame counts do not match total_frames.")
    return sources, total_frames


def render_asset(node, job, assets):
    job_file = assets / (job["name"] + ".job.json")
    job_file.write_text(json.dumps(job, indent=2), encoding="utf-8")
    run([node, HELPER, job_file])
    return Path(job["output"])


def make_review_images(final, edit, base, total, ff):
    """Read the finished video; these files are QA aids, never source gameplay."""
    from PIL import Image, ImageDraw, ImageFont

    stills = resolve(base, edit.get("stills_dir", "stills"))
    stills.mkdir(parents=True, exist_ok=True)
    poster_time = min(float(edit.get("poster_time", 8.3)), max(0, total - 1 / FPS))
    poster = stills / "ad_poster.jpg"
    def extract(time, target):
        # PNG is RGB, avoiding FFmpeg's JPEG 601-matrix tagging ambiguity. Pillow
        # then encodes an ordinary, correctly interpreted JPEG from those pixels.
        png = target.with_suffix(".png")
        run(ff + ["-loglevel", "error", "-ss", time, "-i", final, "-vf",
                  "scale=in_color_matrix=bt709:in_range=tv:out_range=pc,format=rgb24",
                  "-frames:v", 1, "-update", 1, png])
        Image.open(png).convert("RGB").save(target, quality=95, subsampling=0)

    extract(poster_time, poster)
    times = edit.get("review_frame_times", [.65, 3.3, 6.3, 8.3, 10.3, 13.2])
    times = [min(float(t), max(0, total - 1 / FPS)) for t in times]
    columns, tile_width, tile_height, margin, header = 3, 318, 544, 24, 90
    rows = math.ceil(len(times) / columns)
    sheet = Image.new("RGB", (columns * tile_width + margin * 2, rows * tile_height + margin * 2 + header), "#fff5dd")
    draw = ImageDraw.Draw(sheet)
    try:
        title_font = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 30)
        label_font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 22)
    except OSError:
        title_font = label_font = ImageFont.load_default()
    draw.text((margin, 24), edit.get("review_title", "CARPET CLEANER / FINAL VIDEO FRAMES"), font=title_font, fill="#234d40")
    draw.text((margin, 61), "Picture and caption review - extracted from the exported MP4", font=label_font, fill="#52685b")
    for index, time in enumerate(times):
        still = stills / f"review_frame_{index + 1:02d}.jpg"
        extract(time, still)
        frame = Image.open(still.with_suffix(".png")).convert("RGB").resize((270, 480), Image.Resampling.LANCZOS)
        x = margin + index % columns * tile_width
        y = header + margin + index // columns * tile_height
        sheet.paste(frame, (x, y))
        draw.text((x, y + 492), f"{index + 1:02d} / {time:.2f} seconds", font=label_font, fill="#234d40")
    contact = stills / "Contact_Sheet.jpg"
    sheet.save(contact, quality=93, subsampling=0)
    return {"poster": str(poster), "poster_time": poster_time, "contact_sheet": str(contact), "frame_times": times}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("edit", type=Path)
    parser.add_argument("--validate-only", action="store_true")
    parser.add_argument("--node", default=shutil.which("node"))
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg"))
    parser.add_argument("--ffprobe", default=shutil.which("ffprobe"))
    args = parser.parse_args()
    if not args.ffmpeg or not args.ffprobe:
        parser.error("Installed ffmpeg and ffprobe are required.")
    edit_path = args.edit.resolve()
    base = edit_path.parent
    edit = json.loads(edit_path.read_text(encoding="utf-8-sig"))
    sources, total_frames = validate(edit, base, args.ffprobe)
    total = total_frames / FPS
    print(f"Validated {len(edit['clips'])} clips, {total_frames} frames, {total:.3f} seconds.", flush=True)
    if args.validate_only:
        return
    if not args.node:
        parser.error("Node plus Sharp is required to render the outlined vector assets.")
    output = resolve(base, edit.get("output_dir", "exports"))
    output.mkdir(parents=True, exist_ok=True)
    work = output / "intermediates"
    assets = work / "art"
    assets.mkdir(parents=True, exist_ok=True)
    ff = [args.ffmpeg, "-hide_banner", "-loglevel", "warning", "-y"]
    rendered = []
    timeline = []
    clock_frames = 0
    for index, clip in enumerate(edit["clips"]):
        name = f"{index + 1:02d}_{clip['id']}"
        if not all(c.isalnum() or c in "_-" for c in name):
            raise ValueError("Clip IDs must contain only letters, digits, underscores and hyphens.")
        source = resolve(base, clip["source"])
        video_stream = next(s for s in sources[source]["streams"] if s["codec_type"] == "video")
        matrix, video_range = source_color(video_stream, clip)
        start, frames = float(clip.get("in", 0)), clip["frames"]
        duration = frames / FPS
        silent = clip.get("audio", "source") == "mute" or clip.get("kind") in STILL_KINDS
        intermediate = work / f"{name}.mkv"
        layers = overlay_layers(clip)
        print(f"Rendering {name}: source {start:.3f}-{start + duration:.3f}s -> {frames} frames", flush=True)
        if clip.get("kind") == "endcard":
            hero = assets / f"{name}_hero.png"
            extract = ff + ["-ss", start, "-i", source]
            hero_filter = []
            if clip.get("crop"):
                x, y, w, h = clip["crop"]
                hero_filter.append(f"crop={w}:{h}:{x}:{y}")
            hero_filter += [f"scale=in_color_matrix={matrix}:in_range={video_range}:out_range=pc", "format=rgb24"]
            extract += ["-vf", ",".join(hero_filter)]
            run(extract + ["-frames:v", 1, "-update", 1, hero])
            background = resolve(base, clip.get("background", "../ad_preproduction_v2/vectors/endcard.svg"))
            card = render_asset(args.node, {"name": name, "kind": "endcard", "source": str(background),
                                           "hero": str(hero), "slot": clip.get("hero_slot", [365, 505, 350, 565]),
                                           "output": str(assets / f"{name}_card.png")}, assets)
            command = ff + ["-loop", 1, "-framerate", FPS, "-i", card]
        elif clip.get("kind") in ("freeze", "hero"):
            hero = assets / f"{name}_hero.png"
            run(ff + ["-ss", start, "-i", source, "-vf", video_filter(clip.get("crop"), matrix, video_range),
                      "-frames:v", 1, "-update", 1, hero])
            command = ff + ["-loop", 1, "-framerate", FPS, "-i", hero]
        else:
            command = ff + ["-ss", start, "-i", source]
        # Clip audio is sourced explicitly, then bounded to precisely the same edit duration.
        audio_path = resolve(base, clip["audio_source"]) if clip.get("audio_source") else source
        audio_info = probe(audio_path, args.ffprobe) if clip.get("audio_source") else sources[source]
        has_audio = any(s["codec_type"] == "audio" for s in audio_info["streams"])
        if not silent and not has_audio:
            raise ValueError(f"Clip {clip['id']} requests source audio but it has none; supply audio_source or set audio='mute'.")
        if silent:
            command += ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo"]
        else:
            command += ["-ss", float(clip.get("audio_in", start)), "-i", audio_path]
        for layer_index, layer in enumerate(layers):
            layer_name = f"{name}_overlay_{layer_index + 1:02d}"
            overlay = render_asset(args.node, {"name": layer_name, "kind": "overlay",
                                               "source": str(resolve(base, layer["source"])),
                                               "output": str(assets / f"{layer_name}.png")}, assets)
            command += ["-loop", 1, "-framerate", FPS, "-i", overlay]
        picture = video_filter(None, "bt709", "pc") if clip.get("kind") in STILL_KINDS else video_filter(clip.get("crop"), matrix, video_range)
        if clip.get("kind") in ("freeze", "hero"):
            zoom_start, zoom_end = clip.get("freeze_zoom", [1, 1.03])
            # Presentation motion applies only to a disclosed recorded still; the
            # cleaning footage is never retimed, reversed or synthetically advanced.
            # Oversample the held frame so integer crop steps stay below one output
            # pixel. Keep planar RGB through zoompan instead of an implicit YUV hop.
            picture += (f",scale={WIDTH * 2}:{HEIGHT * 2}:flags=lanczos,format=gbrp,"
                        f"zoompan=z='{zoom_start}+({zoom_end}-{zoom_start})*min(on/{max(1, frames - 1)},1)':"
                        f"x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2':d=1:s={WIDTH}x{HEIGHT}:fps={FPS},format=rgba")
        graph = f"[0:v]{picture},trim=duration={duration},setpts=PTS-STARTPTS[base];"
        current = "base"
        for layer_index, layer in enumerate(layers):
            settings = layer_settings(layer, duration)
            at, until, intro, outro = (settings[k] for k in ("at", "until", "enter", "exit"))
            label, composite = f"layer{layer_index}", f"composite{layer_index}"
            filters = "format=rgba,setpts=PTS-STARTPTS"
            if intro > 0:
                filters += f",fade=t=in:st={at}:d={intro}:alpha=1"
            if outro > 0:
                filters += f",fade=t=out:st={until-outro}:d={outro}:alpha=1"
            graph += f"[{layer_index + 2}:v]{filters}[{label}];"
            y = f"{settings['rise']}*pow(1-clip((t-{at})/{intro},0,1),3)" if intro > 0 else "0"
            if settings["float"]:
                y += f"+{settings['float']}*sin(2*PI*max(t-{at},0)/{settings['period']})"
            graph += (f"[{current}][{label}]overlay=x=0:y='{y}':format=rgb:"
                      f"enable='gte(t,{at})*lt(t,{until})'[{composite}];")
            current = composite
        graph += f"[{current}]null[rgb];"
        # One explicit RGB -> 709/limited conversion, after all artwork is composed.
        # The intermediates and final encoded file now contain 709 values, not just tags.
        graph += ("[rgb]scale=in_range=pc:out_range=tv:out_color_matrix=bt709,format=yuv420p,"
                  "setparams=range=limited:colorspace=bt709:color_primaries=bt709:color_trc=bt709[v];")
        gain = float(clip.get("audio_gain", 1))
        # Short boundary fades avoid clicks; no sustained scrape is invented across an edit.
        af = f"aresample=48000,aformat=channel_layouts=stereo,apad,atrim=duration={duration},asetpts=PTS-STARTPTS,volume={gain}"
        if not silent:
            af += f",afade=t=in:d=0.003,afade=t=out:st={max(0, duration - 0.003)}:d=0.003"
        graph += f"[1:a]{af}[a]"
        run(command + ["-filter_complex", graph, "-map", "[v]", "-map", "[a]",
                       "-t", duration, "-c:v", "ffv1", "-level", 3, "-coder", 1, "-context", 1,
                       "-c:a", "pcm_s16le", intermediate])
        rendered.append(intermediate)
        timeline.append({**clip, "timeline_in_frame": clock_frames, "timeline_out_frame_exclusive": clock_frames + frames,
                         "source_color_matrix": matrix, "source_color_range": video_range,
                         "intermediate": str(intermediate.relative_to(base))})
        clock_frames += frames
    concat_file = work / "concat.txt"
    # Paths are generated by this script, but apostrophes still need ffconcat escaping.
    concat_file.write_text("\n".join("file '" + str(p).replace("\\", "/").replace("'", "'\\''") + "'" for p in rendered), encoding="utf-8")
    picture = work / "picture_lock.mkv"
    run(ff + ["-f", "concat", "-safe", 0, "-i", concat_file, "-c", "copy", picture])
    audio_inputs = []
    graph = [f"[0:a]apad,atrim=duration={total},asetpts=PTS-STARTPTS[game]"]
    buses = ["[game]"]
    input_index = 1
    if edit.get("music"):
        music = edit["music"]
        audio_inputs += ["-stream_loop", "-1", "-i", resolve(base, music["source"])]
        gain = float(music.get("gain", .32))
        music_in = float(music.get("in", 0))
        fade_out = float(music.get("fade_out", .9))
        graph.append(f"[{input_index}:a]atrim=start={music_in}:duration={total},asetpts=PTS-STARTPTS,aresample=48000,"
                     f"aformat=channel_layouts=stereo,volume={gain},afade=t=in:d=0.08,"
                     f"afade=t=out:st={max(0, total-fade_out)}:d={fade_out}[music]")
        buses.append("[music]")
        input_index += 1
    for event_num, event in enumerate(edit.get("audio_events", [])):
        audio_inputs += ["-i", resolve(base, event["source"])]
        delay = round(float(event["at"]) * 1000)
        label = f"event{event_num}"
        graph.append(f"[{input_index}:a]aresample=48000,aformat=channel_layouts=stereo,volume={float(event.get('gain', 1))},"
                     f"adelay={delay}|{delay}[{label}]")
        buses.append(f"[{label}]")
        input_index += 1
    graph.append("".join(buses) + f"amix=inputs={len(buses)}:duration=first:normalize=0,atrim=duration={total}[mix]")
    premix = work / "premix.wav"
    run(ff + ["-i", picture] + audio_inputs + ["-filter_complex", ";".join(graph), "-map", "[mix]", "-c:a", "pcm_s24le", premix])
    target_lufs = float(edit.get("target_lufs", -18))
    measurement = subprocess.run([str(v) for v in [args.ffmpeg, "-hide_banner", "-i", premix, "-af",
                                   f"loudnorm=I={target_lufs}:TP=-1:LRA=11:print_format=json", "-f", "null", "-"]],
                                 text=True, capture_output=True, check=True)
    a, b = measurement.stderr.rfind("{"), measurement.stderr.rfind("}")
    measured = json.loads(measurement.stderr[a:b + 1])
    normalizer = f"loudnorm=I={target_lufs}:TP=-1:LRA=11:linear=true:"
    normalizer += ":".join(f"{name}={measured[key]}" for name, key in (("measured_I", "input_i"), ("measured_TP", "input_tp"),
                            ("measured_LRA", "input_lra"), ("measured_thresh", "input_thresh"), ("offset", "target_offset")))
    mix = output / "Carpet_Cleaner_Mix.wav"
    run(ff + ["-i", premix, "-af", normalizer, "-ar", 48000, "-c:a", "pcm_s24le", mix])
    final = output / edit.get("filename", "Carpet_Cleaner_Find_The_Fox_15s.mp4")
    run(ff + ["-i", picture, "-i", mix, "-map", "0:v:0", "-map", "1:a:0", "-t", total,
              "-c:v", "libx264", "-preset", edit.get("preset", "slow"), "-crf", str(edit.get("crf", 17)),
              "-pix_fmt", "yuv420p", "-profile:v", "high", "-level", "4.2", "-r", FPS,
              "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
              "-c:a", "aac", "-b:a", "256k", "-ar", 48000, "-movflags", "+faststart", final])
    final_info = probe(final, args.ffprobe)
    vstream = next(s for s in final_info["streams"] if s["codec_type"] == "video")
    astream = next(s for s in final_info["streams"] if s["codec_type"] == "audio")
    if (vstream["width"], vstream["height"], vstream.get("r_frame_rate")) != (WIDTH, HEIGHT, "30/1"):
        raise RuntimeError("Export dimensions or frame rate did not match the edit.")
    if int(vstream.get("nb_frames", 0)) != total_frames:
        raise RuntimeError("Exported frame count did not match the edit.")
    if abs(float(astream.get("duration", 0)) - total) > .05:
        raise RuntimeError("Exported audio was unexpectedly truncated.")
    review_images = make_review_images(final, edit, base, total, ff)
    manifest = {"edit": str(edit_path), "canvas": [WIDTH, HEIGHT], "fps": FPS, "frames": total_frames,
                "seconds": total, "speed": 1, "sources_preserved": True, "clips": timeline,
                "color_pipeline": "Source-metadata YUV decode -> RGB artwork composition -> explicit BT.709 limited-range YUV -> H.264; review PNGs decode BT.709 before Pillow JPEG encoding",
                "source_files": [{"path": str(p), "bytes": p.stat().st_size, "sha256": sha256(p)} for p in sources],
                "audio": {"target_lufs": target_lufs, "target_true_peak_dbtp": -1, "premix_measurement": measured,
                          "music": edit.get("music"), "added_events": edit.get("audio_events", [])},
                "output": str(final), "output_probe": final_info, "review_images": review_images}
    (output / "Edit_Report.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Finished {final}", flush=True)


if __name__ == "__main__":
    main()
