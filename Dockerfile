FROM docker.io/library/alpine:3.22 AS build
WORKDIR /build

ARG AMNEZIAWG_TOOLS_REPO=https://github.com/amnezia-vpn/amneziawg-tools.git
ARG AMNEZIAWG_GO_REPO=https://github.com/amnezia-vpn/amneziawg-go.git

RUN apk add --no-cache \
    bash \
    build-base \
    git \
    go \
    linux-headers

RUN git clone --depth 1 "$AMNEZIAWG_GO_REPO" amneziawg-go && \
    git clone --depth 1 "$AMNEZIAWG_TOOLS_REPO" amneziawg-tools && \
    make -C amneziawg-go && \
    make -C amneziawg-tools/src && \
    sed -i 's|\[\[ $proto == -4 \]\] && cmd sysctl -q net\.ipv4\.conf\.all\.src_valid_mark=1|[[ $proto == -4 ]] \&\& [[ $(sysctl -n net.ipv4.conf.all.src_valid_mark) != 1 ]] \&\& cmd sysctl -q net.ipv4.conf.all.src_valid_mark=1|' \
      amneziawg-tools/src/wg-quick/linux.bash

FROM docker.io/library/alpine:3.22

RUN apk add --no-cache \
    bash \
    dumb-init \
    ip6tables \
    iproute2 \
    iptables \
    iptables-legacy \
    kmod \
    nftables \
    openresolv && \
    mkdir -p /etc/wireguard /etc/amnezia && \
    ln -s /etc/wireguard /etc/amnezia/amneziawg && \
    for dir in /usr/sbin /sbin; do \
      if [ -x "$dir/iptables-legacy" ]; then \
        ln -sf iptables-legacy "$dir/iptables"; \
        ln -sf iptables-legacy-restore "$dir/iptables-restore"; \
        ln -sf iptables-legacy-save "$dir/iptables-save"; \
      fi; \
      if [ -x "$dir/ip6tables-legacy" ]; then \
        ln -sf ip6tables-legacy "$dir/ip6tables"; \
        ln -sf ip6tables-legacy-restore "$dir/ip6tables-restore"; \
        ln -sf ip6tables-legacy-save "$dir/ip6tables-save"; \
      fi; \
    done

COPY --from=build /build/amneziawg-go/amneziawg-go /usr/bin/amneziawg-go
COPY --from=build /build/amneziawg-tools/src/wg /usr/bin/awg
COPY --from=build /build/amneziawg-tools/src/wg-quick/linux.bash /usr/bin/awg-quick
COPY docker/awg-client-entrypoint.sh /usr/local/bin/awg-client-entrypoint

RUN chmod +x /usr/bin/amneziawg-go /usr/bin/awg /usr/bin/awg-quick /usr/local/bin/awg-client-entrypoint

ENV AWG_CONFIG_DIR=/etc/wireguard

HEALTHCHECK --interval=1m --timeout=5s --retries=3 CMD /usr/bin/timeout 5s /bin/sh -c "awg show | grep -q interface || exit 1"

LABEL org.opencontainers.image.source=https://github.com/wg-easy/wg-easy

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/usr/local/bin/awg-client-entrypoint"]
