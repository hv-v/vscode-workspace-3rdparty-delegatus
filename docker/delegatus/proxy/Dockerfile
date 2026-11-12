# syntax=docker/dockerfile:1.7
#
# Egress proxy for the Delegatus container: the only way its agents reach the
# internet. tinyproxy answers CONNECT to port 443 of the hosts in `allow` and
# refuses everything else (tinyproxy.conf). It runs as nobody on a read-only
# root filesystem; see docker-compose.yml.

FROM alpine:3.20

RUN apk add --no-cache tinyproxy=1.11.2-r0

COPY tinyproxy.conf /etc/tinyproxy/tinyproxy.conf
COPY allow /etc/tinyproxy/allow

USER 65534:65534
EXPOSE 3128
ENTRYPOINT ["/usr/bin/tinyproxy", "-d", "-c", "/etc/tinyproxy/tinyproxy.conf"]
