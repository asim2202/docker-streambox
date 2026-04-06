#!/usr/bin/env python3
"""StreamBox Control Panel - Desktop GUI for managing RTMP stream."""

import tkinter as tk
from tkinter import scrolledtext
import subprocess
import os
import time
import threading


class StreamPanel:
    def __init__(self, root):
        self.root = root
        self.root.title("StreamBox Control")
        self.root.geometry("420x520")
        self.root.resizable(False, False)
        self.root.attributes("-topmost", True)
        self.root.configure(bg="#1a1a2e")

        self.is_running = False
        self.start_time = None

        self._build_ui()
        self._update_loop()

    def _build_ui(self):
        bg = "#1a1a2e"
        fg = "#e0e0e0"
        accent = "#0f3460"
        btn_bg = "#16213e"

        # Title bar
        title_frame = tk.Frame(self.root, bg="#0f3460", pady=8)
        title_frame.pack(fill="x")
        tk.Label(
            title_frame, text="StreamBox Control Panel",
            bg="#0f3460", fg="white", font=("Helvetica", 14, "bold")
        ).pack()

        # Status indicator
        status_frame = tk.Frame(self.root, bg=bg, pady=10)
        status_frame.pack(fill="x")

        self.status_label = tk.Label(
            status_frame, text="OFFLINE", font=("Helvetica", 20, "bold"),
            bg=bg, fg="#e74c3c"
        )
        self.status_label.pack()

        self.uptime_label = tk.Label(
            status_frame, text="", font=("Helvetica", 11),
            bg=bg, fg=fg
        )
        self.uptime_label.pack()

        # Stats frame
        stats_frame = tk.LabelFrame(
            self.root, text="Stream Stats", bg=bg, fg=fg,
            font=("Helvetica", 10, "bold"), padx=10, pady=5
        )
        stats_frame.pack(fill="x", padx=10, pady=5)

        self.stats_labels = {}
        for label in ["FPS", "Bitrate", "Frames", "Dropped"]:
            row = tk.Frame(stats_frame, bg=bg)
            row.pack(fill="x", pady=1)
            tk.Label(
                row, text=f"{label}:", bg=bg, fg="#8899aa",
                font=("Helvetica", 10), width=10, anchor="w"
            ).pack(side="left")
            val = tk.Label(
                row, text="--", bg=bg, fg=fg,
                font=("Courier", 10), anchor="w"
            )
            val.pack(side="left", fill="x")
            self.stats_labels[label] = val

        # RTMP target
        target_frame = tk.LabelFrame(
            self.root, text="Stream Target", bg=bg, fg=fg,
            font=("Helvetica", 10, "bold"), padx=10, pady=5
        )
        target_frame.pack(fill="x", padx=10, pady=5)

        rtmp_url = os.environ.get("RTMP_URL", "not set")
        stream_key = os.environ.get("STREAM_KEY", "not set")
        # Mask the stream key
        masked_key = stream_key[:4] + "****" if len(stream_key) > 4 else "****"

        self.target_label = tk.Label(
            target_frame, text=f"{rtmp_url}/{masked_key}",
            bg=bg, fg="#8899aa", font=("Courier", 9), wraplength=380
        )
        self.target_label.pack(fill="x")

        # Buttons
        btn_frame = tk.Frame(self.root, bg=bg, pady=10)
        btn_frame.pack(fill="x", padx=10)

        btn_style = dict(
            font=("Helvetica", 11, "bold"), width=10, height=2,
            relief="flat", cursor="hand2"
        )

        self.start_btn = tk.Button(
            btn_frame, text="Start", bg="#27ae60", fg="white",
            command=self._start_stream, activebackground="#2ecc71",
            **btn_style
        )
        self.start_btn.pack(side="left", expand=True, padx=3)

        self.stop_btn = tk.Button(
            btn_frame, text="Stop", bg="#e74c3c", fg="white",
            command=self._stop_stream, activebackground="#c0392b",
            **btn_style
        )
        self.stop_btn.pack(side="left", expand=True, padx=3)

        self.restart_btn = tk.Button(
            btn_frame, text="Restart", bg="#f39c12", fg="white",
            command=self._restart_stream, activebackground="#e67e22",
            **btn_style
        )
        self.restart_btn.pack(side="left", expand=True, padx=3)

        # Log viewer
        log_frame = tk.LabelFrame(
            self.root, text="FFmpeg Log (last 8 lines)", bg=bg, fg=fg,
            font=("Helvetica", 10, "bold"), padx=5, pady=5
        )
        log_frame.pack(fill="both", expand=True, padx=10, pady=(5, 10))

        self.log_text = scrolledtext.ScrolledText(
            log_frame, height=6, bg="#0d1117", fg="#8b949e",
            font=("Courier", 8), wrap="word", state="disabled",
            insertbackground=fg
        )
        self.log_text.pack(fill="both", expand=True)

    def _run_cmd(self, cmd):
        """Run a shell command in a background thread."""
        def _exec():
            try:
                subprocess.run(cmd, shell=True, timeout=10)
            except Exception:
                pass
        threading.Thread(target=_exec, daemon=True).start()

    def _start_stream(self):
        self._run_cmd("/opt/streambox/start-stream.sh")

    def _stop_stream(self):
        self._run_cmd("/opt/streambox/stop-stream.sh")

    def _restart_stream(self):
        self._run_cmd("/opt/streambox/restart-stream.sh")

    def _check_status(self):
        """Check if FFmpeg is running."""
        pidfile = "/tmp/streambox/ffmpeg.pid"
        try:
            if os.path.exists(pidfile):
                with open(pidfile) as f:
                    pid = int(f.read().strip())
                os.kill(pid, 0)  # Check if process exists
                return True
        except (ProcessLookupError, ValueError, PermissionError):
            pass
        return False

    def _read_progress(self):
        """Read FFmpeg progress stats."""
        stats = {"FPS": "--", "Bitrate": "--", "Frames": "--", "Dropped": "--"}
        progress_file = "/tmp/streambox/ffmpeg-progress.log"
        try:
            if os.path.exists(progress_file):
                with open(progress_file) as f:
                    content = f.read()
                lines = content.strip().split("\n")
                # Parse the most recent values
                for line in reversed(lines):
                    if "=" not in line:
                        continue
                    key, val = line.split("=", 1)
                    key = key.strip()
                    val = val.strip()
                    if key == "fps" and stats["FPS"] == "--":
                        stats["FPS"] = val
                    elif key == "bitrate" and stats["Bitrate"] == "--":
                        # Convert kbits/s to Mbps
                        try:
                            kbits = float(val.replace("kbits/s", "").strip())
                            stats["Bitrate"] = f"{kbits / 1000:.2f} Mbps"
                        except (ValueError, AttributeError):
                            stats["Bitrate"] = val
                    elif key == "frame" and stats["Frames"] == "--":
                        stats["Frames"] = val
                    elif key == "drop_frames" and stats["Dropped"] == "--":
                        stats["Dropped"] = val
        except Exception:
            pass
        return stats

    def _get_uptime(self):
        """Get stream uptime."""
        start_file = "/tmp/streambox/stream-start-time"
        try:
            if os.path.exists(start_file):
                with open(start_file) as f:
                    start = int(f.read().strip())
                elapsed = int(time.time()) - start
                hours = elapsed // 3600
                minutes = (elapsed % 3600) // 60
                seconds = elapsed % 60
                return f"{hours:02d}:{minutes:02d}:{seconds:02d}"
        except Exception:
            pass
        return ""

    def _read_log(self):
        """Read last lines of FFmpeg log."""
        logfile = "/var/log/streambox/ffmpeg.log"
        try:
            if os.path.exists(logfile):
                with open(logfile) as f:
                    lines = f.readlines()
                return "".join(lines[-8:])
        except Exception:
            pass
        return ""

    def _update_loop(self):
        """Update UI every 2 seconds."""
        self.is_running = self._check_status()

        if self.is_running:
            self.status_label.config(text="LIVE", fg="#27ae60")
            uptime = self._get_uptime()
            self.uptime_label.config(text=f"Uptime: {uptime}" if uptime else "")

            stats = self._read_progress()
            for key, val in stats.items():
                self.stats_labels[key].config(text=val)
        else:
            self.status_label.config(text="OFFLINE", fg="#e74c3c")
            self.uptime_label.config(text="")
            for label in self.stats_labels.values():
                label.config(text="--")

        # Update log
        log_content = self._read_log()
        self.log_text.config(state="normal")
        self.log_text.delete("1.0", "end")
        self.log_text.insert("1.0", log_content)
        self.log_text.config(state="disabled")
        self.log_text.see("end")

        self.root.after(2000, self._update_loop)


if __name__ == "__main__":
    root = tk.Tk()
    app = StreamPanel(root)
    root.mainloop()
