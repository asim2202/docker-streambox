#!/bin/bash
# Log rotation - trims any log over 10MB to last 1000 lines
while true; do
    for logfile in /var/log/streambox/*.log; do
        SIZE=$(stat -c%s "$logfile" 2>/dev/null)
        if [ "$SIZE" -gt 10485760 ] 2>/dev/null; then
            tail -1000 "$logfile" > "${logfile}.tmp"
            mv "${logfile}.tmp" "$logfile"
        fi
    done
    sleep 300
done
