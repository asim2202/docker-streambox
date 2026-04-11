# StreamBox

A Docker container that streams a virtual 1080p60 desktop to any RTMP server. Built for Unraid with Intel iGPU hardware encoding, but works on any Docker host.

## Why This Exists

StreamBox runs a headless Linux desktop inside Docker that is continuously captured and streamed via RTMP. You control the desktop through VNC (browser or native client) or SSH. Anything you do on the desktop -- browse the web, play media, run apps -- gets streamed live.

The primary use case is 24/7 unattended streaming of web content (e.g. tod.tv, YouTube) to a private RTMP server for restreaming/recording.

---

## Architecture

```
Xvfb (virtual display :99, 1920x1080x24)
  |
  +-- Fluxbox (window manager)
  +-- Chromium (browser with DRM/Widevine)
  +-- VLC (media playback)
  +-- Stream Control Panel (Tk GUI)
  |
  +-- x11grab --> FFmpeg h264_vaapi --> RTMP server
  |
  +-- x11vnc --> noVNC (web) / VNC client
  |
  +-- PulseAudio (virtual audio sink --> FFmpeg)
```

**FFmpeg captures the Xvfb display at 60fps**, encodes it with Intel VA-API hardware encoding (h264_vaapi), muxes with AAC audio from the PulseAudio virtual sink, and pushes to your RTMP endpoint. All encoding happens on the iGPU -- CPU is only used for x11grab capture and audio.

---

## Key Design Decisions (and Why)

### Chromium instead of Firefox
- **Debian Bookworm's Firefox ESR has no VA-API support** -- it's compiled without it. `strings` search on libxul.so confirmed zero vaapi references.
- Firefox used 500%+ CPU decoding video in software. Chromium with GPU compositing uses ~60-130%.
- Chromium supports Widevine DRM for protected content (tod.tv, Netflix, etc.).

### Chromium launched with `--disable-features=VaapiVideoDecoder`
- DRM content (Widevine) **will not play** when VA-API video decoding is enabled in Chromium. The DRM pipeline conflicts with hardware decode.
- This flag disables VA-API for *video decode only*. GPU compositing/rasterization still works (`--enable-gpu-rasterization --use-gl=egl`).
- The trade-off is software video decoding (~60-130% CPU) but DRM content actually plays.

### FFmpeg 7.1.3 (BtbN static build) instead of Debian's FFmpeg 5.1
- **Debian's FFmpeg 5.1 has a VA-API memory leak.** In testing, FFmpeg VSZ grew from 1GB to 9.2GB in under an hour, speed dropped below 1x, and the RTMP server disconnected.
- FFmpeg 7.1.3 from [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds) stays flat at ~115-135MB RSS for 6+ hours.
- The BtbN build is a static binary -- it doesn't link against the system's libva. Instead, we upgrade libva from Debian Trixie so the system VA-API driver is new enough for the GPU.

### libva 2.22 from Debian Trixie (apt pinning)
- FFmpeg 7.1.3 requires `vaMapBuffer2` which doesn't exist in Bookworm's libva 2.17.
- We add the Trixie repo with apt pinning (priority 100 for everything, priority 500 for libva/intel-media-va-driver/libigdgmm only). This upgrades *only* the VA-API stack without touching any other Bookworm packages.
- Resulting stack: libva 2.22 + intel-media-va-driver from Trixie, everything else from Bookworm.

### CQP rate control (`-qp 26`) instead of CBR/VBR
- The Intel UHD 630 iGPU **only supports CQP mode** via VA-API. Attempts to use CBR (`-b:v`) or VBR (`-maxrate`) are rejected by the hardware.
- QP 26 produces ~6-12 Mbps depending on content complexity (static desktop ~6 Mbps, full-motion video ~12 Mbps).
- QP scale: lower = better quality, higher = smaller files. Range 18-28 is typical. QP 23 ~= 15 Mbps, QP 26 ~= 10 Mbps, QP 28 ~= 8 Mbps.

### `-map 0:v -map 1:a` explicit stream mapping
- Without explicit mapping, FLV container may order streams in a way that confuses downstream RTMP servers/transcoders.
- Some RTMP servers (Node-Media-Server with QSV transcoding) assume stream #0 is video. If audio arrives first, the transcoder tries to decode audio as video with QSV and crashes.
- This flag guarantees video is always stream #0 in the FLV output.

### `-max_muxing_queue_size 1024`
- Prevents "Too many packets buffered for output stream" errors that cause FFmpeg to crash during long streams.
- Default queue size is too small when there are timing differences between video and audio capture.

### `--shm-size=2g`
- Chromium and other browsers use `/dev/shm` for shared memory. Default Docker shm is 64MB which causes browser tab crashes.
- 2GB is sufficient for multiple browser tabs with video playback.

### `--device=/dev/dri:/dev/dri`
- Passes the Intel iGPU into the container for VA-API hardware encoding.
- Required for `h264_vaapi` encoder. Without it, falls back to software x264 (much higher CPU).

---

## Ports

| Port | Service | Description |
|------|---------|-------------|
| 6080 | noVNC | Web-based VNC -- access the desktop in your browser |
| 5900 | VNC | Native VNC client (TightVNC, RealVNC, etc.) |
| 2222 | SSH | CLI access: `ssh root@<IP> -p 2222` |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RTMP_URL` | `rtmp://localhost/live` | RTMP ingest URL |
| `STREAM_KEY` | `stream` | Stream key (appended to RTMP_URL) |
| `VNC_PASSWORD` | `streambox` | VNC access password |
| `SSH_PASSWORD` | `streambox` | SSH root password |
| `DISPLAY_WIDTH` | `1920` | Virtual display width |
| `DISPLAY_HEIGHT` | `1080` | Virtual display height |
| `FPS` | `60` | Stream framerate (30 or 60) |
| `VIDEO_BITRATE` | `4500k` | Bitrate for x264 software encoder (ignored for VA-API) |
| `AUDIO_BITRATE` | `128k` | AAC audio bitrate |
| `ENCODER` | `qsv` | `qsv` for Intel VA-API hw encoding, `x264` for software |
| `ENCODER_PRESET` | `veryfast` | x264 preset (only used if ENCODER=x264) |
| `TZ` | `America/New_York` | Container timezone |

## Volumes

| Path | Description |
|------|-------------|
| `/config` | Persistent storage for browser profiles, VNC config, etc. |
| `/media` | Optional: mount media files for VLC playback (read-only) |

---

## Quick Start

### Docker CLI
```bash
docker run -d \
  --name streambox \
  --shm-size=2g \
  --device=/dev/dri:/dev/dri \
  -p 6080:6080 \
  -p 5900:5900 \
  -p 2222:2222 \
  -e RTMP_URL=rtmp://your-server/live \
  -e STREAM_KEY=your-key \
  -e VNC_PASSWORD=changeme \
  -e SSH_PASSWORD=changeme \
  -e TZ=America/New_York \
  -v /mnt/user/appdata/streambox:/config \
  -v /mnt/user/media:/media:ro \
  ghcr.io/asim2202/docker-streambox:latest
```

### Unraid
1. Go to **Docker** tab > **Add Container** > **Template Repositories**
2. Add: `https://github.com/asim2202/docker-streambox`
3. Find **StreamBox** in the template dropdown
4. Fill in RTMP URL, stream key, passwords
5. Ensure **Extra Parameters** contains: `--shm-size=2g --device=/dev/dri:/dev/dri`
6. Click **Apply**

---

## Stream Control

### From the Desktop (VNC)
- **Control Panel** auto-starts with live stats, Start/Stop/Restart buttons
- **Right-click menu** has Stream Control submenu

### From SSH
```bash
ssh root@<IP> -p 2222

stream-start     # Start streaming
stream-stop      # Stop streaming
stream-restart   # Restart stream
stream-status    # Show stream status and stats
```

### Monitoring
- **Healthcheck** runs every 10 minutes, logging fps, speed, memory, drops, CPU, temp to `/var/log/streambox/healthcheck.log`
- **Log rotation** trims any log over 10MB to last 1000 lines every 5 minutes
- FFmpeg progress stats written to `/tmp/streambox/ffmpeg-progress.log` (tmpfs, not disk)

---

## Troubleshooting

### Stream at 1-2 fps with massive frame drops
**Cause:** RTMP server backpressure. Usually the downstream server's transcoder is failing (e.g. QSV decode errors) or a stale session is blocking the new publisher.
**Fix:** Restart your RTMP server to clear stale sessions. Verify the RTMP server can handle the incoming h264 stream (some servers try to re-encode and fail if they don't have GPU access).

### FFmpeg memory growing over time
**Cause:** If using Debian's built-in FFmpeg 5.1, it has a confirmed VA-API memory leak (grows to 9GB+ in ~1 hour).
**Fix:** This image uses FFmpeg 7.1.3 from BtbN builds which has the fix. Memory should stay flat at ~115-135MB. If you see growth, check with `ps -p $(cat /tmp/streambox/ffmpeg.pid) -o rss`.

### DRM content won't play in Chromium
**Cause:** VA-API video decode conflicts with Widevine DRM.
**Fix:** Chromium must be launched with `--disable-features=VaapiVideoDecoder`. The desktop shortcut and Fluxbox menu already include this flag. Don't remove it or DRM sites (tod.tv, Netflix) will show black/error.

### Chromium high CPU (100-500%)
**Expected:** DRM video decoding is done in software (see above). The CdmServiceBroker process handles DRM decryption and will use 20-30% CPU. Total Chromium CPU for 1080p DRM video is ~60-130%.
**Not expected:** If CPU is 500%+, VA-API video decode might have been re-enabled. Check Chromium's launch flags.

### "FFMPEG DEAD" in healthcheck but container is running
**Cause:** FFmpeg crashed or was killed. It runs as a background process launched by `start-stream.sh`, not directly by supervisord (autorestart=false).
**Fix:** Run `stream-restart` via SSH, or restart the container. The stream auto-starts on container boot.

### Docker vdisk growing
**Cause:** Logs, browser cache, or temporary files accumulating inside the container.
**Fix:** Log rotation handles `/var/log/streambox/`. For browser cache, periodically clean `/root/.cache/chromium/`. FFmpeg writes nothing to disk -- progress file is on tmpfs.

### vainfo shows errors
**Expected output:**
```
libva info: VA-API version 1.22.0
vainfo: Driver version: Intel iHD driver for Intel(R) Gen Graphics
vainfo: Supported profile and entrypoints
      VAProfileH264Main               : VAEntrypointEncSlice
```
If you see "va_openDriver() returns -1", the GPU isn't passed through. Ensure `--device=/dev/dri:/dev/dri` is set.

---

## File Layout

```
/opt/streambox/
  entrypoint.sh        # Container init: passwords, timezone, PulseAudio config
  start-stream.sh      # FFmpeg launcher (VA-API or x264 fallback)
  stop-stream.sh       # Kills FFmpeg gracefully
  restart-stream.sh    # Stop + start
  stream-status.sh     # Current stream stats
  stream-panel.py      # Tk GUI control panel
  healthcheck.sh       # Stats logger (every 10 min)
  log-rotate.sh        # Trim large logs (every 5 min)

/var/log/streambox/    # All logs (rotated automatically)
/tmp/streambox/        # Runtime state (PID files, progress, config)
```

---

## Building from Source

```bash
git clone https://github.com/asim2202/docker-streambox.git
cd docker-streambox
docker build -t streambox .
```

The GitHub Actions workflow (`.github/workflows/build-and-push.yml`) automatically builds and pushes to `ghcr.io/asim2202/docker-streambox:latest` on push to main.

---

## Hardware Tested

- **CPU:** Intel i9-9900K
- **iGPU:** Intel UHD Graphics 630
- **Platform:** Unraid 6.x
- **Proven stable:** 6+ hours continuous 1080p60 stream, FFmpeg memory flat at ~130MB, 0 duplicate frames

## Version History

- **v2.0.0** - Major rewrite: Chromium (DRM support), FFmpeg 7.1.3 (memory leak fix), libva 2.22 from Trixie, healthcheck, log rotation, stream-order fix
- **v1.0.0** - Initial release: Firefox ESR, Debian FFmpeg 5.1, basic streaming
