FROM radpenguin/rclone:latest

ARG BUILD_DATE
ENV VERSION 1.0.0
LABEL build_version="RadPenguin version:- ${VERSION} Build-date:- ${BUILD_DATE}"

ENV CLEAN_EMPTY_DIRS=1
ENV COMMAND=sync
ENV COMMAND_OPTS=-v
ENV CONFIG_OPTS="--config /config/rclone.conf"
ENV CRON="0 * * * *"
ENV DESTINATION=
ENV HEALTH_URL=
ENV SOURCE=/source
ENV TZ="America/Edmonton"

RUN \
  echo "**** install runtime packages ****" && \
  apk add --no-cache \
    curl \
    dcron && \
  echo "**** cleanup ****" && \
  rm -rf /tmp/*

COPY entrypoint.sh /
COPY rclone.sh /

VOLUME ["/config"]

ENTRYPOINT ["/entrypoint.sh"]
