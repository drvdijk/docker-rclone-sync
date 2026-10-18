ARG RCLONE_VERSION=1.75.2
FROM rclone/rclone:${RCLONE_VERSION}

ARG BUILD_DATE
ENV VERSION=1.0.0
LABEL build-version="drvdijk rclone-sync version:- ${VERSION} Build-date:- ${BUILD_DATE}"

ENV CLEAN_EMPTY_DIRS=0
ENV COMMAND=sync
ENV COMMAND_OPTS=-v
ENV CONFIG_OPTS="--config /config/rclone.conf"
ENV CRON_ENABLED=0
ENV CRON="0 * * * *"
#ENV DESTINATION=
#ENV HEALTH_URL=
ENV SOURCE=/source
ENV TZ="Europe/Amsterdam"

RUN \
  echo "**** install runtime packages ****" && \
  apk add --no-cache \
    curl=8.22.0-r0 \
    dcron=4.6-r0 && \
  echo "**** cleanup ****" && \
  rm -rf /tmp/*

COPY entrypoint.sh /
COPY rclone.sh /

VOLUME ["/config"]

ENTRYPOINT ["/entrypoint.sh"]
