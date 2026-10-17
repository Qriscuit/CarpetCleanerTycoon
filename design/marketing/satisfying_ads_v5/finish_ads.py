"""Make the AI-hook-ready body and handoff files from the approved picture lock."""
from pathlib import Path
import hashlib
import json
import subprocess
import zipfile

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[2]
FF = 'C:/ProgramData/chocolatey/bin/ffmpeg.exe'
FP = 'C:/ProgramData/chocolatey/bin/ffprobe.exe'
OUT = BASE / 'exports'
STILLS = BASE / 'stills'
HANDOFF = BASE / 'ai_handoff'

def run(args):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr[-5000:])
    return result.stdout

def probe(file):
    return json.loads(run([FP, '-v', 'error', '-show_streams', '-show_format', '-of', 'json', file]))

def sha(file):
    digest = hashlib.sha256()
    with file.open('rb') as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()

def main():
    HANDOFF.mkdir(exist_ok=True)
    body = OUT / 'Carpet_Cleaner_Pond_Garden_B_Gameplay_10s.mp4'
    picture = OUT / 'intermediates/picture_lock.mkv'
    audio = OUT / 'Carpet_Cleaner_Mix.wav'
    run([FF, '-hide_banner', '-loglevel', 'error', '-y', '-i', picture, '-i', audio,
         '-filter_complex', '[0:v]trim=start_frame=150:end_frame=450,setpts=PTS-STARTPTS[v];[1:a]atrim=start=5:end=15,asetpts=PTS-STARTPTS[a]',
         '-map', '[v]', '-map', '[a]', '-t', 10,
         '-c:v', 'libx264', '-preset', 'slow', '-crf', 17, '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-level', '4.2',
         '-r', 30, '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709',
         '-c:a', 'aac', '-b:a', '256k', '-ar', 48000, '-movflags', '+faststart', body])
    raw = ROOT / 'build/ad-capture-v5/pond-paid-002/restorations.avi'
    run([FF, '-hide_banner', '-loglevel', 'error', '-y', '-ss', str(1196/30), '-i', raw,
         '-vf', 'scale=in_color_matrix=bt601:in_range=pc:out_range=pc,format=rgb24', '-frames:v', 1, '-update', 1,
         HANDOFF / 'AI_Hook_End_Target_Raw.png'])
    run([FF, '-hide_banner', '-loglevel', 'error', '-y', '-ss', 5, '-i', picture,
         '-vf', 'scale=in_color_matrix=bt709:in_range=tv:out_range=pc,format=rgb24', '-frames:v', 1, '-update', 1,
         HANDOFF / 'AI_Hook_End_Target_Composed.png'])
    with zipfile.ZipFile(OUT / 'Pond_Garden_Individual_Art_Layers.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for file in sorted((BASE / 'production_art').rglob('*')):
            if file.is_file(): archive.write(file, file.relative_to(BASE))
    report = {
        'A': {'file': 'exports/Carpet_Cleaner_Pond_Garden_A_15s.mp4', 'frames': 450, 'seconds': 15},
        'B': {'file': str(body.relative_to(BASE)), 'frames': 300, 'seconds': 10,
              'role': 'Finished gameplay body; prepend the separately created five-second AI hook to form the second fifteen-second ad.',
              'derived_from': 'A lossless picture-lock frames 150 through 449, with the same master audio samples from 5 through 15 seconds.'},
        'AI_hook_generated': False,
        'handoff': {'first_gameplay_frame': str((HANDOFF / 'AI_Hook_End_Target_Composed.png').relative_to(BASE)),
                    'raw_reference': str((HANDOFF / 'AI_Hook_End_Target_Raw.png').relative_to(BASE)),
                    'tool': 'Actual mint wide brush, not a wet squeegee; current paid build uses brush cleaning.',
                    'picture_crop': [270, 880, 540, 730], 'picture_slot': [100, 500, 880, 980],
                    'instruction': 'End the future five-second illustration at the supplied frame pose and continue the actual brush movement. Keep printed koi/lotus still; generate no fake gameplay HUD.'},
        'B_probe': probe(body), 'B_sha256': sha(body)
    }
    (HANDOFF / 'Handoff.json').write_text(json.dumps(report['handoff'], indent=2), encoding='utf-8')
    (OUT / 'Deliverables.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('Finished 10-second shared body, exact AI handoff frames and individual art-layer archive.')

if __name__ == '__main__': main()
