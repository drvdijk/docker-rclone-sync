FROM rclone/rclone:1.66.0

ARG BUILD_DATE
ENV VERSION 1.0.0
LABEL build-version="drvdijk rclone-sync version:- ${VERSION} Build-date:- ${BUILD_DATE}"

ENV CLEAN_EMPTY_DIRS=1
ENV COMMAND=sync
ENV COMMAND_OPTS=-v
ENV CONFIG_OPTS="--config /config/rclone.conf"
ENV CRON="0 * * * *"
ENV DESTINATION=
ENV HEALTH_URL=
ENV SOURCE=/source
ENV TZ="Europe/Amsterdam"

RUN \
  echo "**** install runtime packages ****" && \
  apk add --no-cache \
    curl=8.5.0-r0 \
    dcron=4.5-r9 && \
  echo "**** cleanup ****" && \
  rm -rf /tmp/*

COPY entrypoint.sh /
COPY rclone.sh /

VOLUME ["/config"]

ENTRYPOINT ["/entrypoint.sh"]
