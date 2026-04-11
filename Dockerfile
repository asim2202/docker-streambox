FROM debian:trixie

LABEL maintainer="StreamBox"
LABEL description="Virtual desktop with RTMP streaming, VNC, and SSH access"

# Prevent interactive prompts during install
ENV DEBIAN_FRONTEND=noninteractive

# Default environment variables
ENV DISPLAY=:99
ENV DISPLAY_WIDTH=1920
ENV DISPLAY_HEIGHT=1080
ENV DISPLAY_DEPTH=24
ENV FPS=60
ENV VIDEO_BITRATE=4500k
ENV AUDIO_BITRATE=128k
ENV ENCODER_PRESET=veryfast
ENV ENCODER=qsv
ENV RTMP_URL=rtmp://localhost/live
ENV STREAM_KEY=stream
ENV VNC_PASSWORD=streambox
ENV SSH_PASSWORD=streambox
ENV TZ=America/New_York
ENV PULSE_SERVER=/tmp/pulse-socket
ENV HOME=/root

# VA-API environment for hardware acceleration
ENV LIBVA_DRIVER_NAME=iHD

# Install all packages — single repo, no mixing
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Virtual display
    xvfb \
    # Window manager
    fluxbox \
    # VNC
    x11vnc \
    # Web terminal
    xterm \
    # Audio
    pulseaudio \
    # SSH
    openssh-server \
    # Process manager
    supervisor \
    # Browser with DRM support
    chromium \
    # Media player
    vlc \
    # Python for control panel
    python3 \
    python3-tk \
    # Media encoding (Trixie ships FFmpeg 7.x with VA-API support)
    ffmpeg \
    # VA-API hardware acceleration (Intel iGPU)
    intel-media-va-driver \
    vainfo \
    # Utilities
    ca-certificates \
    wget \
    curl \
    net-tools \
    procps \
    dbus-x11 \
    fonts-liberation \
    fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

# Patch VLC to allow running as root
RUN sed -i 's/geteuid/getppid/' /usr/bin/vlc

# Install noVNC and websockify
RUN mkdir -p /opt/novnc/utils/websockify \
    && wget -qO- https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz | tar xz --strip-components=1 -C /opt/novnc \
    && wget -qO- https://github.com/novnc/websockify/archive/refs/tags/v0.11.0.tar.gz | tar xz --strip-components=1 -C /opt/novnc/utils/websockify \
    && ln -s /opt/novnc/vnc.html /opt/novnc/index.html

# Configure SSH
RUN mkdir -p /var/run/sshd \
    && sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config \
    && ssh-keygen -A

# Configure PulseAudio for headless operation
RUN mkdir -p /root/.config/pulse \
    && echo "default-server = unix:/tmp/pulse-socket" > /root/.config/pulse/client.conf \
    && echo "autospawn = no" >> /root/.config/pulse/client.conf

# Create directories
RUN mkdir -p /root/.fluxbox \
    /root/Desktop \
    /var/log/streambox \
    /tmp/streambox \
    /config

# Copy configuration files
COPY config/supervisord.conf /etc/supervisor/conf.d/streambox.conf
COPY config/fluxbox-menu /root/.fluxbox/menu
COPY config/fluxbox-startup /root/.fluxbox/startup
COPY config/stream-panel.desktop /root/Desktop/StreamPanel.desktop
COPY config/chromium.desktop /root/Desktop/Chromium.desktop

# Copy scripts
COPY scripts/entrypoint.sh /opt/streambox/entrypoint.sh
COPY scripts/start-stream.sh /opt/streambox/start-stream.sh
COPY scripts/stop-stream.sh /opt/streambox/stop-stream.sh
COPY scripts/restart-stream.sh /opt/streambox/restart-stream.sh
COPY scripts/stream-status.sh /opt/streambox/stream-status.sh
COPY scripts/stream-panel.py /opt/streambox/stream-panel.py
COPY scripts/healthcheck.sh /opt/streambox/healthcheck.sh
COPY scripts/log-rotate.sh /opt/streambox/log-rotate.sh

# Make scripts executable
RUN chmod +x /opt/streambox/*.sh /opt/streambox/*.py

# Create convenience symlinks
RUN ln -s /opt/streambox/start-stream.sh /usr/local/bin/stream-start \
    && ln -s /opt/streambox/stop-stream.sh /usr/local/bin/stream-stop \
    && ln -s /opt/streambox/restart-stream.sh /usr/local/bin/stream-restart \
    && ln -s /opt/streambox/stream-status.sh /usr/local/bin/stream-status

# Expose ports
EXPOSE 6080 5900 2222

# Volume for persistent config
VOLUME /config

ENTRYPOINT ["/opt/streambox/entrypoint.sh"]
