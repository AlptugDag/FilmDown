#!/usr/bin/env python3
"""
FilmDown - Ultra High Quality Video & Stream Downloader
Powered by Alptuğ Dağ
"""

import os
import sys
import shutil
import subprocess
import threading
import tkinter as tk
from tkinter import ttk, filedialog, messagebox

APP_NAME = "FilmDown"
APP_VERSION = "1.0.0"
AUTHOR = "Alptuğ Dağ"

def find_binary(name):
    paths = [
        shutil.which(name),
        f"/opt/homebrew/bin/{name}",
        f"/usr/local/bin/{name}",
        f"/Library/Frameworks/Python.framework/Versions/3.10/bin/{name}",
        os.path.expanduser(f"~/Library/Python/3.10/bin/{name}"),
        os.path.expanduser(f"~/Library/Python/3.9/bin/{name}"),
    ]
    for p in paths:
        if p and os.path.exists(p) and os.access(p, os.X_OK):
            return p
    return name

YT_DLP_BIN = find_binary("yt-dlp")
FFMPEG_BIN = find_binary("ffmpeg")

class FilmDownApp:
    def __init__(self, root):
        self.root = root
        self.root.title(f"{APP_NAME} — Powered by {AUTHOR}")
        self.root.geometry("700x590")
        self.root.minsize(600, 500)

        # Style & Theme
        style = ttk.Style()
        try:
            style.theme_use('aqua')
        except Exception:
            style.theme_use('clam')

        # Header Frame (Branding)
        header_frame = ttk.Frame(root)
        header_frame.pack(fill="x", padx=16, pady=(12, 6))

        title_label = ttk.Label(header_frame, text=f"🎬 {APP_NAME}", font=("Helvetica", 18, "bold"))
        title_label.pack(side="left")

        powered_label = ttk.Label(
            header_frame, 
            text=f"⚡ Powered by {AUTHOR}", 
            font=("Helvetica", 11, "bold"), 
            foreground="#555555"
        )
        powered_label.pack(side="right", pady=4)

        # System Status Banner
        ytdlp_status = "✅ yt-dlp hazır" if shutil.which(YT_DLP_BIN) or os.path.exists(YT_DLP_BIN) else "⚠️ yt-dlp bulunamadı"
        ffmpeg_status = "✅ ffmpeg hazır" if shutil.which(FFMPEG_BIN) or os.path.exists(FFMPEG_BIN) else "⚠️ ffmpeg bulunamadı"

        status_bar = ttk.Frame(root)
        status_bar.pack(fill="x", padx=16, pady=(0, 6))
        ttk.Label(
            status_bar, 
            text=f"Sistem: {ytdlp_status}  •  {ffmpeg_status}  •  v{APP_VERSION}", 
            font=("Helvetica", 10), 
            foreground="#666666"
        ).pack(side="left")

        # URL Input Section
        url_frame = ttk.LabelFrame(root, text=" Video / M3U8 Adresleri (Her satıra bir link) ")
        url_frame.pack(fill="both", expand=True, padx=16, pady=4)

        self.url_text = tk.Text(url_frame, height=7, wrap="none", font=("Menlo", 11))
        self.url_text.pack(fill="both", expand=True, padx=8, pady=8)

        # Download Directory Section
        dir_frame = ttk.LabelFrame(root, text=" İndirilecek Klasör ")
        dir_frame.pack(fill="x", padx=16, pady=4)

        default_dir = os.path.expanduser("~/Desktop/ALPTUĞ İÇERİK")
        if not os.path.exists(default_dir):
            default_dir = os.path.expanduser("~/Movies")

        self.dir_var = tk.StringVar(value=default_dir)
        self.dir_entry = ttk.Entry(dir_frame, textvariable=self.dir_var, font=("Helvetica", 11))
        self.dir_entry.pack(side="left", fill="x", expand=True, padx=(8, 4), pady=8)

        self.browse_btn = ttk.Button(dir_frame, text="Gözat...", command=self.browse_dir)
        self.browse_btn.pack(side="right", padx=(4, 8), pady=8)

        # Subfolder (Optional)
        sub_frame = ttk.Frame(root)
        sub_frame.pack(fill="x", padx=16, pady=4)
        ttk.Label(sub_frame, text="Alt Klasör Adı (opsiyonel):").pack(side="left")
        self.subdir_var = tk.StringVar(value="")
        self.subdir_entry = ttk.Entry(sub_frame, textvariable=self.subdir_var)
        self.subdir_entry.pack(side="left", fill="x", expand=True, padx=(8, 0))

        # Controls & Action
        ctrl_frame = ttk.Frame(root)
        ctrl_frame.pack(fill="x", padx=16, pady=8)

        self.download_btn = ttk.Button(ctrl_frame, text="⬇️ En Yüksek Kalitede İndir", command=self.start_download)
        self.download_btn.pack(side="left", padx=(0, 10))

        self.clear_btn = ttk.Button(ctrl_frame, text="Temizle", command=self.clear_all)
        self.clear_btn.pack(side="left", padx=(0, 10))

        self.status_label = ttk.Label(ctrl_frame, text="Hazır", foreground="gray", font=("Helvetica", 10, "bold"))
        self.status_label.pack(side="left", fill="x", expand=True)

        # Log & Progress Console
        log_frame = ttk.LabelFrame(root, text=" Canlı İlerleme & Çıktı Günlüğü ")
        log_frame.pack(fill="both", expand=True, padx=16, pady=(4, 6))

        self.log_text = tk.Text(log_frame, height=8, state="disabled", font=("Menlo", 10), bg="#181818", fg="#d4d4d4")
        self.log_text.pack(fill="both", expand=True, padx=8, pady=8)

        # Footer
        footer_frame = ttk.Frame(root)
        footer_frame.pack(fill="x", padx=16, pady=(0, 8))
        ttk.Label(
            footer_frame, 
            text=f"FilmDown • Developed & Powered by {AUTHOR} • All Rights Reserved", 
            font=("Helvetica", 9), 
            foreground="#888888"
        ).pack(side="right")

    def browse_dir(self):
        chosen = filedialog.askdirectory(initialdir=self.dir_var.get() or os.path.expanduser("~"))
        if chosen:
            self.dir_var.set(chosen)

    def clear_all(self):
        self.url_text.delete("1.0", tk.END)
        self.subdir_var.set("")
        self.log_text.config(state="normal")
        self.log_text.delete("1.0", tk.END)
        self.log_text.config(state="disabled")
        self.status_label.config(text="Hazır", foreground="gray")

    def log(self, message):
        self.log_text.config(state="normal")
        self.log_text.insert(tk.END, message + "\n")
        self.log_text.see(tk.END)
        self.log_text.config(state="disabled")

    def start_download(self):
        raw_urls = self.url_text.get("1.0", tk.END).splitlines()
        urls = [u.strip() for u in raw_urls if u.strip()]
        if not urls:
            messagebox.showwarning("Eksik Bilgi", "Lütfen en az bir video URL'si girin.")
            return

        save_dir = self.dir_var.get().strip()
        if not save_dir:
            messagebox.showwarning("Eksik Bilgi", "Lütfen bir indirme klasörü seçin.")
            return

        sub = self.subdir_var.get().strip()
        if sub:
            save_dir = os.path.join(save_dir, sub)

        try:
            os.makedirs(save_dir, exist_ok=True)
        except Exception as e:
            messagebox.showerror("Hata", f"Klasör oluşturulamadı: {e}")
            return

        self.download_btn.config(state="disabled")
        self.status_label.config(text="İndirme işlemi başlatılıyor...", foreground="#0066cc")

        threading.Thread(target=self._download_worker, args=(urls, save_dir), daemon=True).start()

    def _download_worker(self, urls, save_dir):
        total = len(urls)
        success_count = 0

        env = os.environ.copy()
        extra_paths = ["/opt/homebrew/bin", "/usr/local/bin", "/Library/Frameworks/Python.framework/Versions/3.10/bin"]
        env["PATH"] = ":".join(extra_paths) + ":" + env.get("PATH", "")

        for i, url in enumerate(urls, 1):
            self.log(f"[{i}/{total}] Başlatılıyor: {url}")
            output_template = os.path.join(save_dir, "%(title)s.%(ext)s")

            cmd = [
                YT_DLP_BIN,
                "--no-check-certificates",
                "-f", "bestvideo+bestaudio/best",
                "--merge-output-format", "mp4/mkv",
                "-o", output_template,
                url
            ]

            try:
                proc = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1,
                    env=env
                )
                for line in proc.stdout:
                    clean = line.strip()
                    if clean:
                        if "[download]" in clean and "%" in clean:
                            self.status_label.config(text=f"[{i}/{total}] {clean}")
                        self.log(clean)
                proc.wait()

                if proc.returncode == 0:
                    self.log(f"✅ İndirme tamamlandı: {url}\n")
                    success_count += 1
                else:
                    self.log(f"❌ İndirme başarısız (Kod {proc.returncode}): {url}\n")
            except Exception as e:
                self.log(f"❌ Çalıştırma hatası: {str(e)}\n")

        self.download_btn.config(state="normal")
        if success_count == total:
            self.status_label.config(text=f"Tüm indirmeler tamamlandı ({success_count}/{total})!", foreground="green")
            messagebox.showinfo("Başarılı", f"{total} adet video başarıyla kaydedildi:\n{save_dir}\n\nFilmDown - Powered by {AUTHOR}")
        else:
            self.status_label.config(text=f"{success_count}/{total} video tamamlandı.", foreground="orange")
            messagebox.showwarning("Bitti", f"{total} videodan {success_count} tanesi indirildi.")

def main():
    root = tk.Tk()
    app = FilmDownApp(root)
    root.mainloop()

if __name__ == "__main__":
    main()
