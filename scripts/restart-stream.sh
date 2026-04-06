#!/bin/bash
# Restart FFmpeg RTMP stream

echo "[stream] Restarting stream..."
/opt/streambox/stop-stream.sh
sleep 1
/opt/streambox/start-stream.sh
