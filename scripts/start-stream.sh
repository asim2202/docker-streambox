#!/bin/bash
# Start FFmpeg RTMP stream

PIDFILE="/tmp/streambox/ffmpeg.pid"
LOGFILE="/var/log/streambox/ffmpeg.log"
PROGRESSFILE="/tmp/streambox/ffmpeg-progress.log"

# Source config
source /tmp/streambox/config 2>/dev/null

# Check if already running
if [ -f "$PIDFILE" ] && kill -0 "$(cat $PIDFILE)" 2>/dev/null; then
    echo "[stream] FFmpeg is already running (PID: $(cat $PIDFILE))"
    exit 0
fi

echo "[stream] Starting RTMP stream..."
echo "[stream] Target: ${RTMP_URL}/${STREAM_KEY}"
echo "[stream] Resolution: ${DISPLAY_WIDTH}x${DISPLAY_HEIGHT} @ ${FPS}fps"
echo "[stream] Video: ${VIDEO_BITRATE} | Audio: ${AUDIO_BITRATE}"

# Clear progress file
> "$PROGRESSFILE"

# Start FFmpeg
# - Capture X11 display
# - Capture PulseAudio virtual speaker monitor
# - Encode with libx264 veryfast preset
# - Stream to RTMP
ffmpeg \
    -f x11grab \
    -video_size "${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}" \
    -framerate "${FPS}" \
    -i "${DISPLAY}" \
    -f pulse \
    -i virtual_speaker.monitor \
    -c:v libx264 \
    -preset veryfast \
    -tune zerolatency \
    -b:v "${VIDEO_BITRATE}" \
    -maxrate "${VIDEO_BITRATE}" \
    -bufsize "$((${VIDEO_BITRATE%k} * 2))k" \
    -pix_fmt yuv420p \
    -g $((FPS * 2)) \
    -keyint_min "${FPS}" \
    -c:a aac \
    -b:a "${AUDIO_BITRATE}" \
    -ar 44100 \
    -ac 2 \
    -f flv \
    -progress "$PROGRESSFILE" \
    "${RTMP_URL}/${STREAM_KEY}" \
    >> "$LOGFILE" 2>&1 &

echo $! > "$PIDFILE"
echo "[stream] FFmpeg started (PID: $(cat $PIDFILE))"

# Write start time
date +%s > /tmp/streambox/stream-start-time
