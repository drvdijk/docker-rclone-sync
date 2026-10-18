#!/bin/sh

# fail fast; treat unset variables as errors
set -e -u

ts() { date +'%Y/%m/%d %H:%M:%S'; }

# Configure the timezone
cp "/usr/share/zoneinfo/$TZ" /etc/localtime
echo "$TZ" > /etc/timezone

# CONFIG_OPTS is intentionally unquoted below: it's a user-supplied,
# possibly multi-word string of rclone flags (e.g. "--config /x.conf"), and
# relies on word splitting to be passed through as separate arguments.
if rclone $CONFIG_OPTS config show 2>/dev/null | grep -q "empty config"; then
  echo "$(ts) Empty rclone config, only showing version"
  rclone version
  exit 0
fi

if [ "${CRON_ENABLED:-0}" != "1" ]; then
  echo "$(ts) Running rclone once"
  # Replace this shell with rclone.sh so its exit code becomes the
  # container's exit code instead of disappearing into a pipe.
  exec /rclone.sh
fi

echo "$(ts) Setting up cron ($CRON)"
crontab -d 2>/dev/null || true
# Cron jobs don't inherit the container's stdout/stderr by default, so they
# write to /rclone.log rather than disappearing silently. Redirect
# explicitly to PID 1's file descriptors instead, so job output (with its
# own timestamps from rclone.sh) reaches `docker logs` and nothing grows a
# log file inside the container.
echo "$CRON /rclone.sh >>/proc/1/fd/1 2>>/proc/1/fd/2" > /crontab
crontab /crontab

# This script is PID 1 in the container. The kernel only applies the
# default action (terminate) for a signal sent to PID 1 if that process has
# installed its own handler for it — otherwise the signal is silently
# ignored. Plain `sh` doesn't install one, so without this trap `docker
# stop` would hang for its full timeout and then SIGKILL instead of
# stopping promptly.
CROND_PID=""
on_signal() {
  echo "$(ts) Received signal, stopping cron"
  [ -n "$CROND_PID" ] && kill -TERM "$CROND_PID" 2>/dev/null
  wait "$CROND_PID" 2>/dev/null
  exit 143
}
trap on_signal TERM INT

echo "$(ts) Starting cron in the foreground"
# Foreground, as a child of this script (not exec'd): busybox crond calls
# setpgid() on startup in foreground mode, which fails with "Operation not
# permitted" if it runs as PID 1. Running it as a plain child avoids that,
# while still ending the container if the cron daemon dies, since this is
# the last thing entrypoint.sh does.
#
# No -d/-l: crond's own debug/syslog logging is either very noisy (-d dumps
# its internal schedule bitmaps on every start) or goes nowhere (there's no
# syslogd in this image). The job output itself still reaches `docker logs`
# via the explicit /proc/1/fd redirection on the crontab line above.
crond -f &
CROND_PID=$!
wait "$CROND_PID"
