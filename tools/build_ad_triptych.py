"""Compose three normal-speed recorded tool views beneath original vector art.

Produces an explicitly tagged BT.709 FFV1 source for build_ad_video.py. No game
state, tool response, frame speed, or cleaning progress is changed by this edit.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil

from PIL import Image, ImageDraw

from build_ad_video import FPS, WIDTH, HEIGHT, run, probe, resolve, source_color, render_asset, sha256


def track_expression(points, axis):
    """Linearly move an editorial crop between explicitly chosen source pixels."""
    if not points:
        raise ValueError("A tracking crop needs at least one keyframe.")
    for point in points:
        if len(point) != 3 or not all(isinstance(v, (int, float)) for v in point):
            raise ValueError("Tracking keyframes are [seconds, x, y].")
    if any(b[0] <= a[0] for a, b in zip(points, points[1:])):
        raise ValueError("Tracking times must be strictly increasing.")
    result = str(points[-1][axis])
    for a, b in reversed(list(zip(points, points[1:]))):
        value = f"{a[axis]}+({b[axis]}-{a[axis]})*clip((t-{a[0]})/({b[0]}-{a[0]}),0,1)"
        result = f"if(lt(t,{b[0]}),{value},{result})"
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("edit", type=Path)
    parser.add_argument("--node", required=True)
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg"))
    parser.add_argument("--ffprobe", default=shutil.which("ffprobe"))
    args = parser.parse_args()
    base = args.edit.resolve().parent
    spec = json.loads(args.edit.read_text(encoding="utf-8-sig"))
    if not spec.get("recorded_gameplay"):
        raise ValueError("Only actual recorded gameplay is accepted.")
    output = resolve(base, spec.get("output", "exports/triptych_source.mkv"))
    work = output.parent / "triptych_work"
    work.mkdir(parents=True, exist_ok=True)
    frames = spec["frames"]
    if not isinstance(frames, int) or frames < 1 or len(spec["panels"]) != 3:
        raise ValueError("Supply a positive frame count and exactly three panels.")
    duration = frames / FPS
    for field in ("background", "overlay"):
        if not resolve(base, spec[field]).is_file():
            raise FileNotFoundError(spec[field])
    background = render_asset(args.node, {"name": "background", "kind": "overlay", "source": str(resolve(base, spec["background"])), "output": str(work / "background.png")}, work)
    overlay = render_asset(args.node, {"name": "overlay", "kind": "overlay", "source": str(resolve(base, spec["overlay"])), "output": str(work / "overlay.png")}, work)
    ff = [args.ffmpeg, "-hide_banner", "-loglevel", "warning", "-y", "-filter_complex_threads", "2"]
    command = ff + ["-loop", 1, "-framerate", FPS, "-i", background, "-loop", 1, "-framerate", FPS, "-i", overlay]
    graph = [f"[0:v]format=rgba,trim=duration={duration},setpts=PTS-STARTPTS[base]"]
    sources, panels = {}, []
    for index, panel in enumerate(spec["panels"]):
        source = resolve(base, panel["source"])
        info = sources.setdefault(source, probe(source, args.ffprobe))
        stream = next(s for s in info["streams"] if s["codec_type"] == "video")
        start = float(panel.get("in", 0))
        if start < 0 or start + duration > float(info["format"]["duration"]) + 1 / FPS:
            raise ValueError(f"Panel {index} exceeds its recorded source.")
        if panel.get("speed", 1) != 1:
            raise ValueError("Only normal-speed footage is supported.")
        x, y, width, height = panel["crop"]
        px, py, pw, ph = panel["slot"]
        if min(x, y, px, py) < 0 or min(width, height, pw, ph) <= 0:
            raise ValueError("Invalid crop or slot bounds.")
        if x + width > stream["width"] or y + height > stream["height"] or px + pw > WIDTH or py + ph > HEIGHT:
            raise ValueError("A crop or slot exceeds its canvas.")
        track = panel.get("track", [])
        for _, tx, ty in track:
            if tx < 0 or ty < 0 or tx + width > stream["width"] or ty + height > stream["height"]:
                raise ValueError("A tracked crop exceeds its recorded frame.")
        # Separate mask input per panel keeps the graph explicit and independent.
        mask = Image.new("L", (pw, ph), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, pw - 1, ph - 1), radius=int(spec.get("corner_radius", 28)), fill=255)
        mask_path = work / f"panel_{index + 1}_mask.png"
        mask.save(mask_path)
        vi, mi = 2 + index * 2, 3 + index * 2
        command += ["-ss", start, "-i", source, "-loop", 1, "-framerate", FPS, "-i", mask_path]
        matrix, video_range = source_color(stream, panel)
        cx = track_expression(track, 1) if track else str(x)
        cy = track_expression(track, 2) if track else str(y)
        graph.append(f"[{vi}:v]fps={FPS},trim=duration={duration},setpts=PTS-STARTPTS,"
                     f"crop={width}:{height}:x='{cx}':y='{cy}',"
                     f"scale={pw}:{ph}:force_original_aspect_ratio=increase:flags=lanczos:in_color_matrix={matrix}:in_range={video_range}:out_range=pc,"
                     f"format=rgb24,crop={pw}:{ph},setsar=1[video{index}]")
        graph.append(f"[{mi}:v]format=gray,trim=duration={duration},setpts=PTS-STARTPTS[mask{index}]")
        graph.append(f"[video{index}][mask{index}]alphamerge[panel{index}]")
        before = "base" if index == 0 else f"composite{index - 1}"
        graph.append(f"[{before}][panel{index}]overlay={px}:{py}:format=rgb[composite{index}]")
        panels.append({**panel, "source_matrix": matrix, "source_range": video_range})
    graph.append("[1:v]format=rgba,setpts=PTS-STARTPTS[art]")
    graph.append("[composite2][art]overlay=0:0:format=rgb[rgb]")
    graph.append("[rgb]scale=in_range=pc:out_range=tv:out_color_matrix=bt709,format=yuv420p,"
                 "setparams=range=limited:colorspace=bt709:color_primaries=bt709:color_trc=bt709[v]")
    audio_panel = spec.get("audio_panel", 0)
    if audio_panel is None:
        command += ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo"]
        ai = 8
    else:
        if audio_panel not in range(3):
            raise ValueError("audio_panel must be 0,1,2 or null.")
        ai = 2 + audio_panel * 2
        audio_source = resolve(base, spec["panels"][audio_panel]["source"])
        if not any(s["codec_type"] == "audio" for s in sources[audio_source]["streams"]):
            raise ValueError("Selected panel has no recorded audio.")
    graph.append(f"[{ai}:a]aresample=48000,aformat=channel_layouts=stereo,apad,atrim=duration={duration},asetpts=PTS-STARTPTS[a]")
    run(command + ["-filter_complex", ";".join(graph), "-map", "[v]", "-map", "[a]", "-t", duration,
                   "-c:v", "ffv1", "-level", "3", "-c:a", "pcm_s16le", output])
    out_info = probe(output, args.ffprobe)
    actual = next(s for s in out_info["streams"] if s["codec_type"] == "video")
    if (actual["width"], actual["height"], actual["r_frame_rate"]) != (WIDTH, HEIGHT, "30/1"):
        raise RuntimeError("Triptych dimensions or timing mismatch.")
    report = {"output": str(output), "frames": frames, "seconds": duration, "panels": panels,
              "normal_speed": True, "source_files": [{"path": str(p), "sha256": sha256(p)} for p in sources],
              "audio_panel": audio_panel, "output_probe": out_info}
    output.with_suffix(".json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"Finished {output}", flush=True)


if __name__ == "__main__":
    main()
