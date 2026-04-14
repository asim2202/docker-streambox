#!/bin/bash
# Start FFmpeg RTMP stream

PIDFILE="/tmp/streambox/ffmpeg.pid"
LOGFILE="/var/log/streambox/ffmpeg.log"
PROGRESSFILE="/tmp/streambox/ffmpeg-progress.log"

# Source config
source /tmp/streambox/config 2>/dev/null

# Ensure DISPLAY is set
export DISPLAY="${DISPLAY:-:99}"

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

# Select encoder
# IMPORTANT: PulseAudio input MUST be opened before x11grab. PulseAudio takes
# ~1.3s to connect; opening it first means both inputs are producing by the
# time FFmpeg starts muxing. If x11grab opens first, video runs 1.3s ahead
# of audio, flooding the FLV with audio-only silence packets that choke
# downstream RTMP transcoders (drops to 2fps).
ENCODER="${ENCODER:-qsv}"

if [ "$ENCODER" = "qsv" ] && [ -e /dev/dri/renderD128 ]; then
    echo "[stream] Using Intel VA-API hardware encoder"
    # CQP mode: qp=23 is good quality (lower=better, 18-28 typical range)
    # Video is input 1 (x11grab), audio is input 0 (pulse)
    VIDEO_CODEC_ARGS="-vaapi_device /dev/dri/renderD128 \
        -filter_complex [1:v]format=nv12,hwupload[vout] \
        -map [vout] -map 0:a \
        -c:v h264_vaapi \
        -qp 23 \
        -g $((FPS * 2)) \
        -keyint_min ${FPS}"
else
    if [ "$ENCODER" = "qsv" ]; then
        echo "[stream] WARNING: QSV requested but /dev/dri/renderD128 not found, falling back to x264"
    fi
    echo "[stream] Using x264 software encoder"
    # Video is input 1 (x11grab), audio is input 0 (pulse)
    VIDEO_CODEC_ARGS="-map 1:v -map 0:a \
        -c:v libx264 \
        -preset ${ENCODER_PRESET:-veryfast} \
        -tune zerolatency \
        -b:v ${VIDEO_BITRATE} \
        -maxrate ${VIDEO_BITRATE} \
        -bufsize $((${VIDEO_BITRATE%k} * 2))k \
        -pix_fmt yuv420p \
        -g $((FPS * 2)) \
        -keyint_min ${FPS} \
        -threads 0"
fi

# Start FFmpeg
# Audio input (pulse) opens first — see comment above for why
ffmpeg \
    -thread_queue_size 1024 \
    -f pulse \
    -i virtual_speaker.monitor \
    -thread_queue_size 1024 \
    -f x11grab \
    -video_size "${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}" \
    -framerate "${FPS}" \
    -draw_mouse 1 \
    -i "${DISPLAY}" \
    ${VIDEO_CODEC_ARGS} \
    -c:a aac \
    -b:a "${AUDIO_BITRATE}" \
    -ar 44100 \
    -ac 2 \
    -af "aresample=async=1000:min_hard_comp=0.1:first_pts=0" \
    -max_muxing_queue_size 1024 \
    -f flv \
    -progress "$PROGRESSFILE" \
    "${RTMP_URL}/${STREAM_KEY}" \
    >> "$LOGFILE" 2>&1 &

echo $! > "$PIDFILE"
echo "[stream] FFmpeg started (PID: $(cat $PIDFILE))"

# Write start time
date +%s > /tmp/streambox/stream-start-time
