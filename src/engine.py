#!/usr/bin/env python3
"""
FilmDown Engine - High Performance Media Downloader Engine
Powered by Alptuğ Dağ
"""

import sys
import os
import json
import warnings
import re
import argparse
import shutil

# Filter all deprecation and runtime warnings
warnings.filterwarnings('ignore')
os.environ['PYTHONWARNINGS'] = 'ignore'

class FilteredStderr:
    def __init__(self, original):
        self.original = original
    def write(self, s):
        if 'Deprecated Feature' in s or 'No supported JavaScript' in s or 'WARNING:' in s:
            return
        if self.original:
            try:
                self.original.write(s)
            except Exception:
                pass
    def flush(self):
        if self.original:
            try:
                self.original.flush()
            except Exception:
                pass

if sys.stderr:
    sys.stderr = FilteredStderr(sys.stderr)

try:
    import yt_dlp
except ImportError:
    extra_paths = [
        '/Library/Frameworks/Python.framework/Versions/3.10/lib/python3.10/site-packages',
        '/opt/homebrew/lib/python3.11/site-packages',
        '/usr/local/lib/python3.10/site-packages',
        os.path.expanduser('~/.local/lib/python3.10/site-packages')
    ]
    for p in extra_paths:
        if os.path.exists(p) and p not in sys.path:
            sys.path.insert(0, p)
    import yt_dlp

def sanitize_name(name):
    if not name:
        return 'Video'
    cleaned = re.sub(r'[/\\:\*\?\"<>\|\x00]', '_', name)
    cleaned = re.sub(r'\s+', ' ', cleaned).strip().strip('.')
    return cleaned if cleaned else 'Video'

def format_speed(b):
    if not b:
        return ''
    if b >= 1024 * 1024:
        return f"{b / (1024 * 1024):.1f} MB/s"
    elif b >= 1024:
        return f"{b / 1024:.0f} KB/s"
    return f"{b:.0f} B/s"

def format_eta(seconds):
    if seconds is None:
        return ''
    m, s = divmod(int(seconds), 60)
    return f"{m:02d}:{s:02d}"

class NonCollidingYDL(yt_dlp.YoutubeDL):
    def __init__(self, params=None, separate_folders=True, base_dir='.', prevent_collision=True):
        super().__init__(params)
        self.separate_folders = separate_folders
        self.base_dir = os.path.abspath(base_dir)
        self.prevent_collision = prevent_collision
        self.current_title = 'Video'
        self.current_target_dir = self.base_dir
        self.current_filename = ''

    def prepare_filename(self, info_dict, dir_type='', *, outtmpl=None, warn=False):
        if dir_type or outtmpl:
            return super().prepare_filename(info_dict, dir_type=dir_type, outtmpl=outtmpl, warn=warn)
        
        raw_title = info_dict.get('title') or 'Video'
        safe_title = sanitize_name(raw_title)
        self.current_title = safe_title
        ext = info_dict.get('ext') or 'mp4'

        if self.separate_folders:
            folder = os.path.join(self.base_dir, safe_title)
            if self.prevent_collision:
                idx = 1
                while os.path.exists(folder) and len(os.listdir(folder)) > 0:
                    folder = os.path.join(self.base_dir, f"{safe_title} ({idx})")
                    idx += 1
            os.makedirs(folder, exist_ok=True)
            self.current_target_dir = folder
            final_path = os.path.join(folder, f"{safe_title}.{ext}")
            if self.prevent_collision:
                idx = 1
                while os.path.exists(final_path):
                    final_path = os.path.join(folder, f"{safe_title} ({idx}).{ext}")
                    idx += 1
        else:
            final_path = os.path.join(self.base_dir, f"{safe_title}.{ext}")
            if self.prevent_collision:
                idx = 1
                while os.path.exists(final_path):
                    final_path = os.path.join(self.base_dir, f"{safe_title} ({idx}).{ext}")
                    idx += 1
            self.current_target_dir = self.base_dir

        self.current_filename = os.path.basename(final_path)
        return final_path

def main():
    parser = argparse.ArgumentParser(description="FilmDown Engine")
    parser.add_argument("--urls-file", required=True, help="File containing URLs to download")
    parser.add_argument("--dest", default=os.path.expanduser("~/Desktop/ALPTUĞ İÇERİK"), help="Destination directory")
    parser.add_argument("--separate-folders", action="store_true", default=False, help="Create separate folder per video")
    parser.add_argument("--prevent-collision", action="store_true", default=False, help="Auto-increment duplicate names")
    args = parser.parse_args()

    dest_dir = os.path.expanduser(args.dest)
    os.makedirs(dest_dir, exist_ok=True)

    with open(args.urls_file, "r", encoding="utf-8") as f:
        urls = [line.strip() for line in f if line.strip() and not line.strip().startswith("#")]

    total_count = len(urls)
    if total_count == 0:
        print(json.dumps({"type": "all_done", "total": 0, "success_count": 0, "failed_count": 0}), flush=True)
        return

    success_count = 0
    failed_count = 0

    print(json.dumps({"type": "batch_start", "total": total_count}), flush=True)

    # Check for ffmpeg
    ffmpeg_bin = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
    if not os.path.exists(ffmpeg_bin) and os.path.exists("/usr/local/bin/ffmpeg"):
        ffmpeg_bin = "/usr/local/bin/ffmpeg"

    for idx, url in enumerate(urls, 1):
        print(json.dumps({"type": "item_start", "index": idx, "total": total_count, "url": url}), flush=True)

        current_percent = 0.0

        def hook(d):
            nonlocal current_percent
            status = d.get('status')
            if status == 'downloading':
                tot = d.get('total_bytes') or d.get('total_bytes_estimate') or 0
                downloaded = d.get('downloaded_bytes') or 0
                speed = d.get('speed') or 0
                eta = d.get('eta')
                if tot > 0:
                    current_percent = min(round((downloaded / tot) * 100.0, 1), 99.9)
                speed_str = format_speed(speed)
                eta_str = format_eta(eta)
                print(json.dumps({
                    "type": "item_progress",
                    "index": idx,
                    "total": total_count,
                    "percent": current_percent,
                    "speed": speed_str,
                    "eta": eta_str
                }), flush=True)
            elif status == 'finished':
                print(json.dumps({
                    "type": "item_processing",
                    "index": idx,
                    "total": total_count,
                    "message": "Ses ve video birleştiriliyor..."
                }), flush=True)

        ydl_opts = {
            'format': 'bestvideo+bestaudio/best',
            'merge_output_format': 'mp4',
            'paths': {'home': dest_dir, 'temp': dest_dir},
            'quiet': True,
            'no_warnings': True,
            'noprogress': True,
            'progress_hooks': [hook],
            'ignoreerrors': False
        }

        if os.path.exists(ffmpeg_bin):
            ydl_opts['ffmpeg_location'] = ffmpeg_bin

        try:
            ydl = NonCollidingYDL(
                params=ydl_opts,
                separate_folders=args.separate_folders,
                base_dir=dest_dir,
                prevent_collision=args.prevent_collision
            )
            ydl.download([url])
            success_count += 1
            print(json.dumps({
                "type": "item_complete",
                "index": idx,
                "total": total_count,
                "title": ydl.current_title,
                "folder": ydl.current_target_dir,
                "filename": ydl.current_filename
            }), flush=True)
        except Exception as e:
            failed_count += 1
            err_msg = str(e)
            print(json.dumps({
                "type": "item_error",
                "index": idx,
                "total": total_count,
                "error": err_msg
            }), flush=True)

    print(json.dumps({
        "type": "all_done",
        "total": total_count,
        "success_count": success_count,
        "failed_count": failed_count
    }), flush=True)

if __name__ == "__main__":
    main()
