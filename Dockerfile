FROM alpine:3.16

COPY data/ /data/
WORKDIR /data
ENV KILL_SWITCH=iptables
ENV USE_VPN_DNS=on
ENV VPN_LOG_LEVEL=3
ARG BUILD_DATE
ARG IMAGE_VERSION
LABEL build-date=$BUILD_DATE
LABEL image-version=$IMAGE_VERSION

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories && \
    chmod a+x scripts/* && \
    apk add --no-cache \
        bash \
        bind-tools \
        dante-server \
        iptables \
        openvpn \
        nftables \
        shadow \
        tinyproxy

HEALTHCHECK CMD ping -c 3 1.1.1.1 || exit 1

ENTRYPOINT [ "scripts/start.sh" ]