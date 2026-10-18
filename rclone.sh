#!/bin/sh

# fail fast; treat unset variables as errors
set -e -u

ts() { date +'%Y/%m/%d %H:%M:%S'; }

# Locking code retrieved from http://stackoverflow.com/a/1985512 on 2017-03-17
LOCK_FILE=/tmp/$(md5sum "$0" | awk '{print $1}').lock
LOCK_FD=99
_lock() {
  flock -"$1" "$LOCK_FD"
}
_no_more_locking() {
  _lock u
  _lock xn && rm -f "$LOCK_FILE"
}
lock() {
  eval "exec $LOCK_FD>\"$LOCK_FILE\""
  # Obtain an exclusive lock immediately or fail
  _lock xn
}

# Ping healthchecks.io at $HEALTH_URL<path>, optionally attaching a file as
# the request body. A failed ping is only logged; it must never fail the
# run itself.
ping_health() {
  [ -z "${HEALTH_URL:-}" ] && return 0
  path="$1"
  body_file="${2:-}"
  if [ -n "$body_file" ]; then
    curl -fsS --retry 3 -m 10 --data-binary "@$body_file" "${HEALTH_URL}${path}" >/dev/null 2>&1 \
      || echo "$(ts) WARNING: ping to ${HEALTH_URL}${path} failed"
  else
    curl -fsS --retry 3 -m 10 "${HEALTH_URL}${path}" >/dev/null 2>&1 \
      || echo "$(ts) WARNING: ping to ${HEALTH_URL}${path} failed"
  fi
}

STARTED=0
FINAL_PING_SENT=0
CLEANED=0
OUTPUT_FILE=""
FIFO=""
RCLONE_PID=""

# Runs on any exit, including one triggered by a signal below. Idempotent
# because the TERM/INT handlers call `exit`, which re-fires this trap.
cleanup() {
  rc=$?
  [ "$CLEANED" = "1" ] && return "$rc"
  CLEANED=1
  if [ "$STARTED" = "1" ] && [ "$FINAL_PING_SENT" = "0" ]; then
    echo "$(ts) rclone.sh exiting unexpectedly (exit $rc)"
    ping_health "/fail"
  fi
  [ -n "$OUTPUT_FILE" ] && rm -f "$OUTPUT_FILE" "$OUTPUT_FILE.tail"
  [ -n "$FIFO" ] && rm -f "$FIFO"
  _no_more_locking
  return "$rc"
}
on_signal() {
  # Forward the signal to rclone itself: it's running as a backgrounded
  # child (see below), so without this it would be left running as an
  # orphan after this script exits instead of shutting down with it.
  echo "$(ts) Received signal, stopping rclone"
  [ -n "$RCLONE_PID" ] && kill -TERM "$RCLONE_PID" 2>/dev/null || true
  exit "$1"
}
trap cleanup EXIT
trap 'on_signal 143' TERM
trap 'on_signal 130' INT

# Only run one copy of the script at a time
echo "$(ts) Checking process lock"
lock || { echo "$(ts) Another run is already in progress, exiting"; exit 1; }

if [ "${CLEAN_EMPTY_DIRS:-0}" = "1" ]; then
  # Clean up empty directories in order to speed up rclone
  echo "$(ts) Tidying empty directories in $SOURCE"
  find "$SOURCE" -mindepth 2 -depth -not -path '*/.*' -type d -exec rmdir -p --ignore-fail-on-non-empty {} \;
fi

OUTPUT_FILE=$(mktemp)
FIFO=$(mktemp -u)
mkfifo "$FIFO"

echo "$(ts) rclone $CONFIG_OPTS $COMMAND $COMMAND_OPTS $SOURCE $DESTINATION"

STARTED=1
ping_health "/start"

# tee reads from the FIFO so output both streams live to stdout (so
# `docker logs -f` shows progress) and gets captured to OUTPUT_FILE for the
# failure-ping body below.
tee "$OUTPUT_FILE" < "$FIFO" &
TEE_PID=$!

# rclone runs backgrounded (writing into the FIFO) purely so we can capture
# its PID via $! — that's what lets on_signal() above forward a TERM/INT to
# the real rclone process, and lets us read its exit code directly via
# `wait` instead of through a pipe (sh has no PIPESTATUS/pipefail, so `$?`
# after a `| tee` pipeline would give tee's exit code, not rclone's).
#
# CONFIG_OPTS/COMMAND/COMMAND_OPTS are intentionally unquoted below: they're
# user-supplied, possibly multi-word strings of rclone flags, and rely on
# word splitting to be passed through as separate arguments.
set +e
rclone $CONFIG_OPTS $COMMAND $COMMAND_OPTS "$SOURCE" "$DESTINATION" >"$FIFO" 2>&1 &
RCLONE_PID=$!
wait "$RCLONE_PID"
RCLONE_EXIT=$?
set -e

wait "$TEE_PID" 2>/dev/null || true

if [ "$RCLONE_EXIT" = "0" ]; then
  echo "$(ts) rclone finished successfully"
  FINAL_PING_SENT=1
  ping_health ""
else
  echo "$(ts) rclone failed with exit code $RCLONE_EXIT"
  tail -n 50 "$OUTPUT_FILE" > "$OUTPUT_FILE.tail"
  FINAL_PING_SENT=1
  ping_health "/$RCLONE_EXIT" "$OUTPUT_FILE.tail"
fi

exit "$RCLONE_EXIT"
