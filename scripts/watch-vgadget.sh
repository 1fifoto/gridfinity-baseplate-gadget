#!/usr/bin/env sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
dist_dir="$project_dir/dist"
pid_file="$dist_dir/build-watch.pid"
log_file="$dist_dir/build-watch.log"

fingerprint() {
  cksum \
    "$project_dir/Gridfinity_Baseplate.lua" \
    "$project_dir/Gridfinity_Baseplate.htm" \
    "$project_dir/README.md" \
    "$project_dir/scripts/build-vgadget.sh" | cksum | awk '{print $1 ":" $2}'
}

run_watcher() {
  previous=""
  while true; do
    current=$(fingerprint)
    if [ "$current" != "$previous" ]; then
      if "$project_dir/scripts/build-vgadget.sh"; then
        previous="$current"
      else
        echo "Build failed; waiting for the next change." >&2
      fi
    fi
    sleep 1
  done
}

case "${1:-run}" in
  start)
    mkdir -p "$dist_dir"
    if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
      echo "Build watcher is already running (PID $(cat "$pid_file"))."
      exit 0
    fi
    nohup "$0" run >"$log_file" 2>&1 &
    watcher_pid=$!
    echo "$watcher_pid" >"$pid_file"
    echo "Started build watcher (PID $watcher_pid). Log: $log_file"
    ;;
  stop)
    if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
      kill "$(cat "$pid_file")"
      echo "Stopped build watcher."
    else
      echo "Build watcher is not running."
    fi
    rm -f "$pid_file"
    ;;
  status)
    if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
      echo "Build watcher is running (PID $(cat "$pid_file"))."
    else
      echo "Build watcher is not running."
      exit 1
    fi
    ;;
  run)
    run_watcher
    ;;
  *)
    echo "Usage: $0 {start|stop|status|run}" >&2
    exit 2
    ;;
esac
