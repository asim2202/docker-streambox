#!/bin/bash
# Stop FFmpeg RTMP stream

PIDFILE="/tmp/streambox/ffmpeg.pid"

if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "[stream] Stopping FFmpeg (PID: $PID)..."
        kill "$PID"
        # Wait up to 5 seconds for graceful shutdown
        for i in $(seq 1 10); do
            if ! kill -0 "$PID" 2>/dev/null; then
                break
            fi
            sleep 0.5
        done
        # Force kill if still running
        if kill -0 "$PID" 2>/dev/null; then
            echo "[stream] Force killing FFmpeg..."
            kill -9 "$PID"
        fi
        echo "[stream] FFmpeg stopped"
    else
        echo "[stream] FFmpeg process not found (stale PID file)"
    fi
    rm -f "$PIDFILE"
    rm -f /tmp/streambox/stream-start-time
else
    echo "[stream] No stream is running"
fi
