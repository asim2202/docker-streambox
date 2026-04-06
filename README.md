# StreamBox

A Docker container that provides a virtual desktop environment for RTMP streaming. Built for Unraid but works on any Docker host.

## Features

- **Virtual Desktop** - Full 1080p desktop with Fluxbox window manager
- **RTMP Streaming** - Stream the desktop to any RTMP server at up to 1080p 60fps via FFmpeg
- **Web VNC (noVNC)** - Access and control the desktop from any browser
- **Native VNC** - Connect with any VNC client
- **SSH Access** - Full CLI access for remote management
- **Stream Control Panel** - Built-in GUI with live stats, start/stop/restart controls
- **Firefox + VLC** - Browse the web or play media files
- **PulseAudio** - Virtual audio sink for streaming audio content

## Ports

| Port | Service | Description |
|------|---------|-------------|
| 6080 | noVNC | Web-based VNC (access in browser) |
| 5900 | VNC | Native VNC client access |
| 2222 | SSH | CLI access (`ssh root@host -p 2222`) |

## Quick Start (Docker CLI)

```bash
docker run -d \
  --name streambox \
  --shm-size=2g \
  -p 6080:6080 \
  -p 5900:5900 \
  -p 2222:2222 \
  -e RTMP_URL=rtmp://your-server/live \
  -e STREAM_KEY=your-key \
  -e VNC_PASSWORD=changeme \
  -e SSH_PASSWORD=changeme \
  -e TZ=America/New_York \
  -v /path/to/config:/config \
  -v /path/to/media:/media:ro \
  ghcr.io/asim2202/docker-streambox:latest
```

## Unraid Installation

1. Go to **Docker** tab in Unraid
2. Click **Add Container** > **Template Repositories**
3. Add: `https://github.com/asim2202/docker-streambox`
4. Click **Save**, then find **StreamBox** in the template dropdown
5. Fill in your RTMP URL, stream key, and passwords
6. Click **Apply**

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RTMP_URL` | `rtmp://localhost/live` | RTMP server URL |
| `STREAM_KEY` | `stream` | Stream key appended to RTMP URL |
| `VNC_PASSWORD` | `streambox` | Password for VNC access |
| `SSH_PASSWORD` | `streambox` | Password for SSH root access |
| `DISPLAY_WIDTH` | `1920` | Virtual display width |
| `DISPLAY_HEIGHT` | `1080` | Virtual display height |
| `FPS` | `60` | Stream framerate |
| `VIDEO_BITRATE` | `4500k` | Video bitrate |
| `AUDIO_BITRATE` | `128k` | Audio bitrate |
| `TZ` | `America/New_York` | Timezone |

## Stream Control

### From the Desktop (VNC)
- **Control Panel** - Auto-starts on the desktop with live stats and Start/Stop/Restart buttons
- **Right-click menu** - Stream Control submenu with all options

### From SSH
```bash
ssh root@your-server -p 2222

stream-start     # Start streaming
stream-stop      # Stop streaming
stream-restart   # Restart stream
stream-status    # Show stream status and stats
```

### Stream Auto-Start
The stream automatically starts when the container boots. Use the control panel or SSH commands to manage it.

## Nginx Proxy Manager (NPM) Setup

To access the desktop remotely via a domain:

1. In NPM, add a new **Proxy Host**
2. Set **Domain**: `stream.yourdomain.com` (or any subdomain)
3. Set **Forward Hostname/IP**: your Unraid server IP (e.g. `192.168.1.100`)
4. Set **Forward Port**: `6080`
5. **Enable WebSocket Support** (required for noVNC)
6. Optionally enable SSL with Let's Encrypt

Then access at: `https://stream.yourdomain.com`

### Embedding in a Website

```html
<iframe
  src="https://stream.yourdomain.com/vnc.html?autoconnect=true&resize=scale"
  width="100%"
  height="100%"
  style="border: none;">
</iframe>
```

## Building from Source

```bash
git clone https://github.com/asim2202/docker-streambox.git
cd docker-streambox
docker build -t streambox .
```

## Volumes

| Path | Description |
|------|-------------|
| `/config` | Persistent configuration storage |
| `/media` | Optional: mount media files for VLC playback (read-only) |

## Shared Memory

The `--shm-size=2g` flag is important. Firefox and Chrome require adequate shared memory. Without it, browser tabs may crash.
