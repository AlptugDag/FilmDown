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

warnings.filterwarnings('ignore')
os.environ['PYTHONWARNINGS'] = 'ignore'

APP_NAME = "FilmDown"
APP_VERSION = "2.1.0"
AUTHOR = "Alptuğ Dağ"

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
ENGINE_SCRIPT = os.path.join(CURRENT_DIR, "src", "engine.py")
if not os.path.exists(ENGINE_SCRIPT):
    ENGINE_SCRIPT = os.path.join(CURRENT_DIR, "engine.py")

class FilmDownApp:
    def __init__(self, root):
        self.root = root
        self.root.title(f"{APP_NAME} — Powered by {AUTHOR}")
        # Fixed window size, responsive internal layout
        self.root.geometry("660x610")
        self.root.resizable(False, False)

        style = ttk.Style()
        try:
            style.theme_use('aqua')
        except Exception:
            style.theme_use('clam')

        default_desktop = os.path.expanduser("~/Desktop/ALPTUĞ İÇERİK")
        if not os.path.exists(default_desktop):
            default_desktop = os.path.expanduser("~/Downloads")
        self.default_dest = default_desktop

        self.queue = []  # list of {"url": str, "dest": str}
        self.proc = None
        self.is_downloading = False

        self._build_ui()

    def _build_ui(self):
        main_frame = ttk.Frame(self.root, padding=16)
        main_frame.pack(fill=tk.BOTH, expand=True)

        # Header
        header = ttk.Frame(main_frame)
        header.pack(fill=tk.X, pady=(0, 10))

        title_lbl = ttk.Label(header, text="FilmDown", font=("Helvetica", 18, "bold"))
        title_lbl.pack(anchor="w")

        sub_lbl = ttk.Label(header, text=f"Yüksek Kaliteli Video ve Medya İndirici • Sürüm {APP_VERSION}", foreground="#666666")
        sub_lbl.pack(anchor="w")

        # Default Destination Card
        dest_card = ttk.LabelFrame(main_frame, text=" Varsayılan Hedef Klasör ", padding=10)
        dest_card.pack(fill=tk.X, pady=(0, 10))

        dir_row = ttk.Frame(dest_card)
        dir_row.pack(fill=tk.X, pady=(0, 6))

        self.dest_var = tk.StringVar(value=self.default_dest)
        dest_lbl = ttk.Label(dir_row, textvariable=self.dest_var, font=("Helvetica", 11))
        dest_lbl.pack(side=tk.LEFT, fill=tk.X, expand=True)

        browse_btn = ttk.Button(dir_row, text="Gözat...", command=self._browse_default_dest)
        browse_btn.pack(side=tk.RIGHT)

        toggles_row = ttk.Frame(dest_card)
        toggles_row.pack(fill=tk.X)

        self.sep_folders_var = tk.BooleanVar(value=True)
        sep_check = ttk.Checkbutton(toggles_row, text="Her video için ayrı alt klasör oluştur", variable=self.sep_folders_var)
        sep_check.pack(side=tk.LEFT)

        col_lbl = ttk.Label(toggles_row, text="Çakışma koruması devrede", foreground="#888888")
        col_lbl.pack(side=tk.RIGHT)

        # Add URL Bar
        add_frame = ttk.Frame(main_frame)
        add_frame.pack(fill=tk.X, pady=(0, 10))

        self.url_entry = ttk.Entry(add_frame, font=("Menlo", 11))
        self.url_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 8))
        self.url_entry.bind("<Return>", lambda e: self._add_from_entry())

        add_btn = ttk.Button(add_frame, text="Ekle", command=self._add_from_entry)
        add_btn.pack(side=tk.LEFT, padx=(0, 6))

        paste_btn = ttk.Button(add_frame, text="Panodan Ekle", command=self._paste_clipboard)
        paste_btn.pack(side=tk.LEFT)

        # Queue List Card
        queue_card = ttk.LabelFrame(main_frame, text=" İndirme Listesi (Her video için ayrı hedef klasör seçilebilir) ", padding=10)
        queue_card.pack(fill=tk.BOTH, expand=True, pady=(0, 10))

        # Canvas + Scrollbar for Queue
        canvas_frame = ttk.Frame(queue_card)
        canvas_frame.pack(fill=tk.BOTH, expand=True)

        self.canvas = tk.Canvas(canvas_frame, highlightthickness=0)
        scrollbar = ttk.Scrollbar(canvas_frame, orient="vertical", command=self.canvas.yview)
        self.scrollable_frame = ttk.Frame(self.canvas)

        self.scrollable_frame.bind(
            "<Configure>",
            lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all"))
        )
        self.canvas_window = self.canvas.create_window((0, 0), window=self.scrollable_frame, anchor="nw")
        self.canvas.bind("<Configure>", lambda e: self.canvas.itemconfig(self.canvas_window, width=e.width))

        self.canvas.configure(yscrollcommand=scrollbar.set)
        self.canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        # Progress / Status Card
        prog_frame = ttk.LabelFrame(main_frame, text=" Durum ", padding=10)
        prog_frame.pack(fill=tk.X, pady=(0, 10))

        self.progress_bar = ttk.Progressbar(prog_frame, mode="determinate", maximum=100)
        self.progress_bar.pack(fill=tk.X, pady=(0, 6))

        self.status_var = tk.StringVar(value="İndirmeye hazır.")
        self.status_lbl = ttk.Label(prog_frame, textvariable=self.status_var, foreground="#333333")
        self.status_lbl.pack(anchor="w")

        # Bottom Bar
        act_frame = ttk.Frame(main_frame)
        act_frame.pack(fill=tk.X)

        open_btn = ttk.Button(act_frame, text="Klasörü Aç", command=self._open_dir)
        open_btn.pack(side=tk.LEFT)

        clear_btn = ttk.Button(act_frame, text="Tümünü Temizle", command=self._clear_queue)
        clear_btn.pack(side=tk.LEFT, padx=8)

        self.action_btn = ttk.Button(act_frame, text="İndirmeyi Başlat", command=self._toggle_download)
        self.action_btn.pack(side=tk.RIGHT)

        self._render_queue()

    def _browse_default_dest(self):
        folder = filedialog.askdirectory(initialdir=self.dest_var.get())
        if folder:
            self.dest_var.set(folder)
            self.default_dest = folder

    def _browse_item_dest(self, idx):
        if self.is_downloading or idx >= len(self.queue):
            return
        folder = filedialog.askdirectory(initialdir=self.queue[idx]["dest"])
        if folder:
            self.queue[idx]["dest"] = folder
            self._render_queue()

    def _add_from_entry(self):
        raw = self.url_entry.get().strip()
        if raw:
            self._add_urls(raw)
            self.url_entry.delete(0, tk.END)

    def _paste_clipboard(self):
        try:
            clip = self.root.clipboard_get()
            if clip:
                self._add_urls(clip)
        except Exception:
            pass

    def _add_urls(self, text):
        lines = [line.strip() for line in text.splitlines() if line.strip() and not line.strip().startswith("#")]
        for u in lines:
            if not any(item["url"] == u for item in self.queue):
                self.queue.append({"url": u, "dest": self.dest_var.get()})
        self._render_queue()
        self.status_var.set(f"{len(self.queue)} video indirilmeye hazır.")

    def _remove_item(self, idx):
        if self.is_downloading or idx >= len(self.queue):
            return
        del self.queue[idx]
        self._render_queue()
        if not self.queue:
            self.status_var.set("İndirmeye hazır.")
        else:
            self.status_var.set(f"{len(self.queue)} video kuyrukta.")

    def _clear_queue(self):
        if not self.is_downloading:
            self.queue.clear()
            self._render_queue()
            self.progress_bar["value"] = 0
            self.status_var.set("İndirmeye hazır.")

    def _render_queue(self):
        for widget in self.scrollable_frame.winfo_children():
            widget.destroy()

        if not self.queue:
            empty_lbl = ttk.Label(self.scrollable_frame, text="Kuyrukta video bulunmuyor.\nYukarıdan ekleyebilir veya 'Panodan Ekle'yi kullanabilirsiniz.", justify=tk.CENTER, foreground="#888888")
            empty_lbl.pack(pady=40, fill=tk.BOTH, expand=True)
            return

        for idx, item in enumerate(self.queue):
            row = ttk.Frame(self.scrollable_frame, padding=4)
            row.pack(fill=tk.X, pady=2)

            num_lbl = ttk.Label(row, text=f"{idx + 1}.", font=("Helvetica", 10, "bold"), width=3)
            num_lbl.pack(side=tk.LEFT)

            info_col = ttk.Frame(row)
            info_col.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=4)

            url_lbl = ttk.Label(info_col, text=item["url"], font=("Menlo", 10))
            url_lbl.pack(anchor="w")

            dest_lbl = ttk.Label(info_col, text=f"Hedef: {item['dest']}", foreground="#666666", font=("Helvetica", 9))
            dest_lbl.pack(anchor="w")

            btn_folder = ttk.Button(row, text="Klasör Seç", command=lambda i=idx: self._browse_item_dest(i))
            btn_folder.pack(side=tk.RIGHT, padx=4)
            if self.is_downloading:
                btn_folder.config(state="disabled")

            btn_del = ttk.Button(row, text="Sil", width=4, command=lambda i=idx: self._remove_item(i))
            btn_del.pack(side=tk.RIGHT)
            if self.is_downloading:
                btn_del.config(state="disabled")

    def _open_dir(self):
        target = self.queue[0]["dest"] if self.queue else self.dest_var.get()
        if os.path.exists(target):
            if sys.platform == "darwin":
                subprocess.run(["open", target])
            elif sys.platform == "win32":
                os.startfile(target)
            else:
                subprocess.run(["xdg-open", target])

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
        self._render_queue()

    def _start_download(self):
        if not self.queue:
            messagebox.showwarning("Eksik Bilgi", "Lütfen önce en az bir video bağlantısı ekleyin.")
            return

        self.is_downloading = True
        self.action_btn.config(text="Durdur")
        self.progress_bar["value"] = 0
        self.status_var.set("İndirme işlemi hazırlanıyor...")
        self._render_queue()

        threading.Thread(target=self._run_worker, daemon=True).start()

    def _run_worker(self):
        temp_file = os.path.expanduser(f"~/.filmdown_queue_{os.getpid()}.json")
        try:
            with open(temp_file, "w", encoding="utf-8") as f:
                json.dump(self.queue, f)

            cmd = [
                sys.executable,
                "-W", "ignore",
                ENGINE_SCRIPT,
                "--queue-file", temp_file,
                "--dest", self.dest_var.get()
            ]
            if self.sep_folders_var.get():
                cmd.append("--separate-folders")

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
            self.root.after(0, lambda: self.status_var.set(f"Video {idx} / {total} — \(msg\)"))
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
        self._render_queue()

def main():
    root = tk.Tk()
    app = FilmDownApp(root)
    root.mainloop()

if __name__ == "__main__":
    main()
