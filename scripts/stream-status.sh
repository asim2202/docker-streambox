#!/bin/bash
# Check stream status and display stats

PIDFILE="/tmp/streambox/ffmpeg.pid"
PROGRESSFILE="/tmp/streambox/ffmpeg-progress.log"
STARTFILE="/tmp/streambox/stream-start-time"

if [ -f "$PIDFILE" ] && kill -0 "$(cat $PIDFILE)" 2>/dev/null; then
    PID=$(cat "$PIDFILE")
    echo "Status: LIVE"
    echo "PID: $PID"

    # Calculate uptime
    if [ -f "$STARTFILE" ]; then
        START=$(cat "$STARTFILE")
        NOW=$(date +%s)
        ELAPSED=$((NOW - START))
        HOURS=$((ELAPSED / 3600))
        MINUTES=$(( (ELAPSED % 3600) / 60 ))
        SECONDS=$((ELAPSED % 60))
        printf "Uptime: %02d:%02d:%02d\n" $HOURS $MINUTES $SECONDS
    fi

    # Show progress stats if available
    if [ -f "$PROGRESSFILE" ]; then
        FRAME=$(grep -oP 'frame=\K\d+' "$PROGRESSFILE" | tail -1)
        FPS_VAL=$(grep -oP 'fps=\K[\d.]+' "$PROGRESSFILE" | tail -1)
        BITRATE=$(grep -oP 'bitrate=\K[\d.]+kbits/s' "$PROGRESSFILE" | tail -1)
        DROPPED=$(grep -oP 'drop_frames=\K\d+' "$PROGRESSFILE" | tail -1)
        [ -n "$FRAME" ] && echo "Frames: $FRAME"
        [ -n "$FPS_VAL" ] && echo "FPS: $FPS_VAL"
        [ -n "$BITRATE" ] && echo "Bitrate: $BITRATE"
        [ -n "$DROPPED" ] && echo "Dropped: $DROPPED"
    fi

    # Source config for target info
    source /tmp/streambox/config 2>/dev/null
    echo "Target: ${RTMP_URL}/${STREAM_KEY}"
else
    echo "Status: OFFLINE"
fi
