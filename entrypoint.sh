#!/bin/sh

# fail fast
set -e -u

# Configure the timezone
cp /usr/share/zoneinfo/$TZ /etc/localtime
echo $TZ > /etc/timezone

# Configure rclone
if [[ $( rclone $CONFIG_OPTS config show | grep "empty config" | wc -l ) != "0" ]]; then
  echo "$( date +'%Y/%m/%d %H:%M:%S' ) Empty rclone config, only showing version"
  rclone version
fi

# Trim the log
echo "" > /rclone.log

if [[ "$CRON_ENABLED" != "1" ]]; then
  echo "$( date +'%Y/%m/%d %H:%M:%S' ) Running rclone"
  /rclone.sh | tee /rclone.log 2>&1
else
  # Setup a crontab for the root user
  echo "$( date +'%Y/%m/%d %H:%M:%S' ) Setting up cron"
  crontab -d
  echo "$CRON /rclone.sh >> /rclone.log 2>&1" > /crontab
  crontab /crontab

  # Setup cron schedule
  echo "$( date +'%Y/%m/%d %H:%M:%S' ) Starting cron"
  crond -b -l warn -L /rclone.log

  # Wait forever
  while [ 1 ]; do
    tail -f /rclone.log
  done
fi
