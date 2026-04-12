#!/bin/bash
set -e

# VA-API hardware acceleration
export LIBVA_DRIVER_NAME=iHD

echo "========================================="
echo "  StreamBox - Starting Up"
echo "========================================="

# Set SSH password
echo "root:${SSH_PASSWORD}" | chpasswd
echo "[entrypoint] SSH password configured"

# Set VNC password
mkdir -p /root/.vnc
x11vnc -storepasswd "${VNC_PASSWORD}" /root/.vnc/passwd
echo "[entrypoint] VNC password configured"

# Set timezone
ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime
echo "${TZ}" > /etc/timezone
echo "[entrypoint] Timezone set to ${TZ}"

echo "[entrypoint] Display: ${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}x${DISPLAY_DEPTH}"

# Create PulseAudio config
mkdir -p /tmp/pulse
cat > /tmp/pulse/default.pa << 'EOF'
load-module module-native-protocol-unix socket=/tmp/pulse-socket
load-module module-null-sink sink_name=virtual_speaker sink_properties=device.description="Virtual_Speaker"
load-module module-virtual-source source_name=virtual_mic master=virtual_speaker.monitor
set-default-sink virtual_speaker
set-default-source virtual_mic
EOF
echo "[entrypoint] PulseAudio configured with virtual sink"

# Ensure log directory exists
mkdir -p /var/log/streambox
mkdir -p /tmp/streambox

# Write stream config for scripts to read
cat > /tmp/streambox/config << EOF
RTMP_URL=${RTMP_URL}
STREAM_KEY=${STREAM_KEY}
DISPLAY_WIDTH=${DISPLAY_WIDTH}
DISPLAY_HEIGHT=${DISPLAY_HEIGHT}
FPS=${FPS}
VIDEO_BITRATE=${VIDEO_BITRATE}
AUDIO_BITRATE=${AUDIO_BITRATE}
EOF

echo "[entrypoint] Stream target: ${RTMP_URL}/${STREAM_KEY}"
echo "[entrypoint] Resolution: ${DISPLAY_WIDTH}x${DISPLAY_HEIGHT} @ ${FPS}fps"
echo "[entrypoint] Video bitrate: ${VIDEO_BITRATE} | Audio bitrate: ${AUDIO_BITRATE}"
echo "========================================="
echo "  Launching services via Supervisor..."
echo "========================================="

exec /usr/bin/supervisord -n -c /etc/supervisor/conf.d/streambox.conf
