#!/bin/bash
# StreamBox healthcheck - logs system stats every 10 minutes
LOGFILE="/var/log/streambox/healthcheck.log"
> "$LOGFILE"

while true; do
    TS=$(date "+%H:%M:%S")
    PID=$(cat /tmp/streambox/ffmpeg.pid 2>/dev/null)

    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        RSS=$(ps -p "$PID" -o rss --no-headers 2>/dev/null | tr -d " ")
        RSS_MB=$((RSS / 1024))
        FPS=$(grep "^fps=" /tmp/streambox/ffmpeg-progress.log 2>/dev/null | tail -1 | cut -d= -f2)
        SPEED=$(grep "^speed=" /tmp/streambox/ffmpeg-progress.log 2>/dev/null | tail -1 | cut -d= -f2 | tr -d " ")
        UPTIME=$(grep "^out_time=" /tmp/streambox/ffmpeg-progress.log 2>/dev/null | tail -1 | cut -d= -f2 | cut -d. -f1)
        DUP=$(grep "^dup_frames=" /tmp/streambox/ffmpeg-progress.log 2>/dev/null | tail -1 | cut -d= -f2)
        DROP=$(grep "^drop_frames=" /tmp/streambox/ffmpeg-progress.log 2>/dev/null | tail -1 | cut -d= -f2)
        CHR_CPU=$(ps aux | grep "[c]hromium" | awk '{sum+=$3} END {printf "%.0f", sum}')
        LOAD=$(awk '{print $1}' /proc/loadavg)
        MEM=$(free -m | awk '/Mem:/ {print $3}')
        TEMPS=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -rn | head -1)
        TEMP=$((TEMPS / 1000))

        echo "[$TS] stream=$UPTIME fps=$FPS speed=$SPEED ffmpeg_mem=${RSS_MB}MB dup=$DUP drop=$DROP chrome=${CHR_CPU}% load=$LOAD ram=${MEM}MB temp=${TEMP}C" >> "$LOGFILE"
    else
        echo "[$TS] FFMPEG DEAD" >> "$LOGFILE"
    fi

    sleep 600
done
