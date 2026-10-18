# docker-rclone-sync

Perform an [rclone](http://rclone.org) command based on a cron schedule, with [healthchecks.io](https://healthchecks.io) monitoring.

## Usage
```
docker create \
  --name=rclone \
  --env CLEAN_EMPTY_DIRS="0" \
  --env COMMAND="sync" \
  --env COMMAND_OPTS="-v" \
  --env CRON="0 * * * *" \
  --env CRON_ENABLED="1" \
  --env DESTINATION="gdrive:media" \
  --env HEALTH_URL=https://hc-ping.com/your-check-uuid \
  --env SOURCE=/source \
  --env TZ="Europe/Amsterdam" \
  --volume <path to data>:/config \
  drvdijk/rclone-sync:latest
```

## Parameters
The parameters are split into two halves, separated by a colon, the left hand side representing the host and the right the container side.
```
--volume /config - config file for rclone
--env CLEAN_EMPTY_DIRS - Defaults to "0". If "1", removes empty directories from SOURCE before running rclone. Deletes things in your source, so it's opt-in.
--env COMMAND - The command to run. Defaults to "sync"
--env COMMAND_OPTS - additional options for the rclone command. Defaults to `-v`
--env CRON - cron schedule, defaults to hourly
--env CRON_ENABLED - Defaults to "0". If disabled, rclone runs once when the container is started and the container's exit code is rclone's exit code
--env DESTINATION - The destination on the rclone remote
--env HEALTH_URL - healthchecks.io ping URL, see below. Optional; without it nothing is pinged
--env SOURCE - The local source directory
--env TZ - the timezone to use for the cron schedule and log timestamps. Defaults to `Europe/Amsterdam`
```

See [rclone docs](https://rclone.org/commands/) for `COMMAND`/`COMMAND_OPTS` syntax and additional options.

## Healthchecks.io monitoring
If `HEALTH_URL` is set, each run pings it like this:
- `$HEALTH_URL/start` just before rclone starts, so healthchecks.io can show how long the run takes.
- `$HEALTH_URL` (no suffix) when rclone exits successfully.
- `$HEALTH_URL/<exit code>` when rclone exits with a non-zero status, with the last ~50 lines of rclone's output as the request body. `$HEALTH_URL/fail` is used instead for failures that aren't rclone's own exit (for example, the script being killed, or another run already holding the lock).

A failed ping (network error, healthchecks.io unreachable, etc.) is only logged as a warning — it never fails the run itself.

## Logging
All output goes to the container's stdout/stderr, so `docker logs` (or `docker logs -f` to follow) shows everything, both for a one-off run and for cron-triggered runs. There's no log file growing inside the container. Every line is prefixed with a timestamp, same as before.

## Image tags
- `:edge` — built from the latest commit on `master`. Not meant for production use, but handy for testing a fix before a release.
- `:latest` and `:X.Y.Z` — built from a published GitHub release tagged `vX.Y.Z`.
- The version number tracks the rclone version the image is built on (see `ARG RCLONE_VERSION` in the `Dockerfile`). If the image or scripts change without an rclone bump, the version gets a `-N` suffix (e.g. `1.75.2-1`, `1.75.2-2`), reset back to no suffix on the next rclone bump.

Pushes on other branches are built and linted in CI, but not pushed to Docker Hub.

### Making a release
1. Bump `ARG RCLONE_VERSION` in the `Dockerfile` if needed, following the versioning scheme above.
2. If you bumped `RCLONE_VERSION`, check whether its Alpine base moved too, and re-pin `curl`/`dcron` to match: the `rclone/rclone` image's Alpine version isn't tied to any particular rclone version (e.g. rclone 1.67.0 ships on Alpine 3.20, 1.75.2 on Alpine 3.24), so the exact package versions pinned in the `Dockerfile` can stop existing in the new release's repo and fail the build.
   ```bash
   docker run --rm --entrypoint sh rclone/rclone:<new-version> -c "apk update >/dev/null; apk info curl dcron"
   ```
   Update the `curl=`/`dcron=` pins in the `Dockerfile` to whatever that prints.
3. Merge to `master` (CI pushes `:edge`).
4. Tag the release commit `vX.Y.Z` and publish a GitHub release for that tag — CI then builds and pushes `:X.Y.Z` and `:latest`.

It's based on the official [`rclone/rclone`](https://hub.docker.com/r/rclone/rclone) Alpine image. For shell access while the container is running, `docker exec -it rclone /bin/sh`.
