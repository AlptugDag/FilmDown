#!/usr/bin/env python3
"""
FilmDown - Ultra High Quality Video & Stream Downloader
Powered by Alptuğ Dağ
"""

import os
import sys
import shutil
import threading
import subprocess
import warnings
import json
import tkinter as tk
from tkinter import ttk, filedialog, messagebox

# Silence deprecation and runtime warnings
warnings.filterwarnings('ignore')
os.environ['PYTHONWARNINGS'] = 'ignore'

APP_NAME = "FilmDown"
APP_VERSION = "2.0.0"
AUTHOR = "Alptuğ Dağ"

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
ENGINE_SCRIPT = os.path.join(CURRENT_DIR, "src", "engine.py")
if not os.path.exists(ENGINE_SCRIPT):
    ENGINE_SCRIPT = os.path.join(CURRENT_DIR, "engine.py")

class ModernProgressDialog(ttk.Frame):
    def __init__(self, parent, *args, **kwargs):
        super().__init__(parent, *args, **kwargs)

class FilmDownApp:
    def __init__(self, root):
        self.root = root
        self.root.title(f"{APP_NAME} — Powered by {AUTHOR}")
        self.root.geometry("660x520")
        self.root.minsize(580, 460)

        # Style & Theme
        style = ttk.Style()
        try:
            style.theme_use('aqua')
        except Exception:
            style.theme_use('clam')

        self.proc = None
        self.is_downloading = False

        self._build_ui()

    def _build_ui(self):
        main_frame = ttk.Frame(self.root, padding=16)
        main_frame.pack(fill=tk.BOTH, expand=True)

        # Header
        header = ttk.Frame(main_frame)
        header.pack(fill=tk.X, pady=(0, 12))

        title_lbl = ttk.Label(header, text="FilmDown", font=("Helvetica", 18, "bold"))
        title_lbl.pack(anchor="w")

        sub_lbl = ttk.Label(header, text=f"Yüksek Kaliteli Video ve Medya İndirici • Sürüm {APP_VERSION}", foreground="#666666")
        sub_lbl.pack(anchor="w")

        # URL Input Section
        url_frame = ttk.LabelFrame(main_frame, text=" Bağlantı Listesi (Her satıra bir adres) ", padding=10)
        url_frame.pack(fill=tk.BOTH, expand=True, pady=(0, 10))

        self.url_text = tk.Text(url_frame, height=6, font=("Menlo", 11), wrap="none", relief="solid", borderwidth=1)
        self.url_text.pack(fill=tk.BOTH, expand=True)

        # Settings Section
        opts_frame = ttk.LabelFrame(main_frame, text=" İndirme Ayarları ve Hedef Klasör ", padding=10)
        opts_frame.pack(fill=tk.X, pady=(0, 10))

        # Target Dir Row
        dir_row = ttk.Frame(opts_frame)
        dir_row.pack(fill=tk.X, pady=(0, 8))

        ttk.Label(dir_row, text="Hedef Klasör:").pack(side=tk.LEFT)

        default_dest = os.path.expanduser("~/Desktop/ALPTUĞ İÇERİK")
        if not os.path.exists(default_dest):
            default_dest = os.path.expanduser("~/Downloads")

        self.dest_var = tk.StringVar(value=default_dest)
        self.dest_entry = ttk.Entry(dir_row, textvariable=self.dest_var)
        self.dest_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=8)

        browse_btn = ttk.Button(dir_row, text="Gözat...", command=self._browse_dir)
        browse_btn.pack(side=tk.LEFT)

        # Options Checkboxes
        toggles_row = ttk.Frame(opts_frame)
        toggles_row.pack(fill=tk.X)

        self.sep_folders_var = tk.BooleanVar(value=True)
        sep_check = ttk.Checkbutton(toggles_row, text="Her video için ayrı klasör oluştur", variable=self.sep_folders_var)
        sep_check.pack(side=tk.LEFT, padx=(0, 16))

        self.no_collision_var = tk.BooleanVar(value=True)
        col_check = ttk.Checkbutton(toggles_row, text="Aynı isimli videoların üzerine yazma (Otomatik numaralandır)", variable=self.no_collision_var)
        col_check.pack(side=tk.LEFT)

        # Progress Section (Loading Bar)
        prog_frame = ttk.LabelFrame(main_frame, text=" Durum ", padding=10)
        prog_frame.pack(fill=tk.X, pady=(0, 12))

        self.progress_bar = ttk.Progressbar(prog_frame, mode="determinate", maximum=100)
        self.progress_bar.pack(fill=tk.X, pady=(0, 6))

        self.status_var = tk.StringVar(value="İndirmeye hazır.")
        self.status_lbl = ttk.Label(prog_frame, textvariable=self.status_var, foreground="#333333")
        self.status_lbl.pack(anchor="w")

        # Bottom Action Bar
        act_frame = ttk.Frame(main_frame)
        act_frame.pack(fill=tk.X)

        open_btn = ttk.Button(act_frame, text="Klasörü Aç", command=self._open_dir)
        open_btn.pack(side=tk.LEFT)

        clear_btn = ttk.Button(act_frame, text="Temizle", command=self._clear_input)
        clear_btn.pack(side=tk.LEFT, padx=8)

        self.action_btn = ttk.Button(act_frame, text="İndirmeyi Başlat", command=self._toggle_download)
        self.action_btn.pack(side=tk.RIGHT)

    def _browse_dir(self):
        folder = filedialog.askdirectory(initialdir=self.dest_var.get())
        if folder:
            self.dest_var.set(folder)

    def _open_dir(self):
        target = self.dest_var.get()
        if os.path.exists(target):
            if sys.platform == "darwin":
                subprocess.run(["open", target])
            elif sys.platform == "win32":
                os.startfile(target)
            else:
                subprocess.run(["xdg-open", target])

    def _clear_input(self):
        if not self.is_downloading:
            self.url_text.delete("1.0", tk.END)
            self.progress_bar["value"] = 0
            self.status_var.set("İndirmeye hazır.")

    def _toggle_download(self):
        if self.is_downloading:
            self._stop_download()
        else:
            self._start_download()

    def _stop_download(self):
        if self.proc:
            try:
                self.proc.terminate()
            except Exception:
                pass
        self.is_downloading = False
        self.action_btn.config(text="İndirmeyi Başlat")
        self.status_var.set("İndirme işlemi kullanıcı tarafından durduruldu.")

    def _start_download(self):
        raw = self.url_text.get("1.0", tk.END).strip()
        urls = [line.strip() for line in raw.splitlines() if line.strip() and not line.strip().startswith("#")]

        if not urls:
            messagebox.showwarning("Eksik Bilgi", "Lütfen en az bir video bağlantısı girin.")
            return

        dest = self.dest_var.get().strip()
        if not dest:
            messagebox.showwarning("Eksik Bilgi", "Lütfen geçerli bir hedef klasör seçin.")
            return

        os.makedirs(dest, exist_ok=True)

        self.is_downloading = True
        self.action_btn.config(text="Durdur")
        self.progress_bar["value"] = 0
        self.status_var.set("İndirme işlemi hazırlanıyor...")

        threading.Thread(target=self._run_worker, args=(urls, dest), daemon=True).start()

    def _run_worker(self, urls, dest):
        temp_file = os.path.expanduser(f"~/.filmdown_urls_{os.getpid()}.txt")
        try:
            with open(temp_file, "w", encoding="utf-8") as f:
                f.write("\n".join(urls))

            cmd = [
                sys.executable,
                "-W", "ignore",
                ENGINE_SCRIPT,
                "--urls-file", temp_file,
                "--dest", dest
            ]
            if self.sep_folders_var.get():
                cmd.append("--separate-folders")
            if self.no_collision_var.get():
                cmd.append("--prevent-collision")

            env = os.environ.copy()
            env["PYTHONWARNINGS"] = "ignore"
            extra_paths = ["/opt/homebrew/bin", "/usr/local/bin", os.path.expanduser("~/.local/bin")]
            env["PATH"] = ":".join(extra_paths) + ":" + env.get("PATH", "")

            self.proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                bufsize=1,
                env=env
            )

            for line in self.proc.stdout:
                line = line.strip()
                if not line:
                    continue
                try:
                    data = json.loads(line)
                    self._handle_event(data)
                except Exception:
                    pass

            self.proc.wait()
        except Exception as e:
            self.root.after(0, lambda: self.status_var.set(f"Hata: {e}"))
        finally:
            if os.path.exists(temp_file):
                try:
                    os.remove(temp_file)
                except Exception:
                    pass
            self.root.after(0, self._on_finish)

    def _handle_event(self, data):
        evt_type = data.get("type")
        if evt_type == "item_progress":
            idx = data.get("index", 1)
            total = data.get("total", 1)
            pct = data.get("percent", 0.0)
            spd = data.get("speed", "")
            eta = data.get("eta", "")

            overall = (float(idx - 1) + (pct / 100.0)) / float(total) * 100.0
            msg = f"Video {idx} / {total} — %{pct:.1f}"
            if spd: msg += f" • {spd}"
            if eta: msg += f" • Kalan: {eta}"

            self.root.after(0, lambda: self._update_progress(overall, msg))
        elif evt_type == "item_processing":
            idx = data.get("index", 1)
            total = data.get("total", 1)
            msg = data.get("message", "İşleniyor...")
            self.root.after(0, lambda: self.status_var.set(f"Video {idx} / {total} — {msg}"))
        elif evt_type == "item_complete":
            idx = data.get("index", 1)
            total = data.get("total", 1)
            title = data.get("title", "Video")
            overall = (float(idx) / float(total)) * 100.0
            self.root.after(0, lambda: self._update_progress(overall, f"Video {idx} / {total} tamamlandı: {title}"))
        elif evt_type == "all_done":
            tot = data.get("total", 0)
            succ = data.get("success_count", 0)
            msg = f"Tüm indirmeler tamamlandı ({succ} / {tot} video kaydedildi)." if succ == tot else f"İşlem tamamlandı ({succ} / {tot} video kaydedildi)."
            self.root.after(0, lambda: self._update_progress(100.0, msg))

    def _update_progress(self, val, msg):
        self.progress_bar["value"] = val
        self.status_var.set(msg)

    def _on_finish(self):
        self.is_downloading = False
        self.action_btn.config(text="İndirmeyi Başlat")

def main():
    root = tk.Tk()
    app = FilmDownApp(root)
    root.mainloop()

if __name__ == "__main__":
    main()
