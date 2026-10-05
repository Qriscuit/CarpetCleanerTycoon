"""Focused export/provenance checks for the third Carpet Cleaner ad."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "design/marketing/ad_production_v3"
OUTPUT = BASE / "exports/Carpet_Cleaner_Three_Tools_18s_v3.mp4"


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def main():
    info = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(OUTPUT)], text=True))
    video = next(s for s in info["streams"] if s["codec_type"] == "video")
    audio = next(s for s in info["streams"] if s["codec_type"] == "audio")
    assert [video["width"], video["height"], video["r_frame_rate"], int(video["nb_frames"])] == [1080, 1920, "30/1", 540]
    assert video["color_space"] == "bt709" and video["color_range"] == "tv"
    assert abs(float(audio["duration"]) - 18) < .05 and audio["channels"] == 2
    measurement = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(OUTPUT), "-af", "loudnorm=I=-18:TP=-1:LRA=11:print_format=json", "-f", "null", "-"], capture_output=True, text=True, check=True)
    content = measurement.stderr
    loudness = json.loads(content[content.rfind("{"):content.rfind("}")+1])
    assert abs(float(loudness["input_i"]) + 18) < .5
    assert float(loudness["input_tp"]) < -1
    panels = json.loads((BASE / "exports/Three_Tools_Triptych.json").read_text(encoding="utf-8"))
    for source in panels["source_files"]:
        assert digest(Path(source["path"])) == source["sha256"]
    prior = ROOT / "design/marketing/ad_production_v2/exports/Carpet_Cleaner_Illustrated_15s_v2.mp4"
    assert digest(prior) == "c118f3b29d54cbc8cc0b67f51aa94ff268dc5839338a8303e0a8e64c21b06b9f"
    sources = {}
    for take in ("brush-band-002", "wet-tools-003", "wet-tools-002"):
        manifest = json.loads((ROOT / "build/ad-capture-v3" / take / "take_manifest.json").read_text(encoding="utf-8"))
        assert manifest["success"] and manifest["native_speed"] and not manifest["mask_fixture"]
        sources[take] = {"success": True, "frames": manifest["driver_frames"], "native_speed": True, "mask_fixture": False,
                         "unlocked_start_fixture": manifest["unlocked_setup_fixture"]}
    svg_count = 0
    for asset in (BASE / "art").glob("*.svg"):
        svg = asset.read_text(encoding="utf-8")
        assert "<text " not in svg and "<image " not in svg
        svg_count += 1
    report = {"artifact": OUTPUT.name, "bytes": OUTPUT.stat().st_size, "sha256": digest(OUTPUT),
              "video": {"width":1080,"height":1920,"fps":30,"frames":540,"seconds":18,"color_space":"BT.709","range":"limited"},
              "audio": {"channels":2,"sample_rate":int(audio["sample_rate"]),"seconds":float(audio["duration"]),
                        "integrated_lufs":float(loudness["input_i"]),"true_peak_dbtp":float(loudness["input_tp"])},
              "capture_checks":sources,"raw_panel_sources_preserved":True,"approved_v2_preserved":True,
              "outlined_vector_files_checked":svg_count,
              "editorial_notes":["Three simultaneous tool views are distinct normal-speed source excerpts.","Maximum wet tools use an isolated unlocked starting save.","Final three seconds hold a real recorded clean frame."],
              "browser_review":"pending"}
    (BASE / "exports/Final_QA.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
