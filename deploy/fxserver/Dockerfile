# FXServer (FiveM) – Linux/proot-Build in einem schlanken Debian-Image.
# Die konkrete Artifact-URL wird als Build-Arg FX_URL uebergeben (siehe .env),
# damit die Version bewusst gepinnt ist und nicht ungewollt springt.

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl xz-utils tar libatomic1 procps \
    && rm -rf /var/lib/apt/lists/*

# FX_URL = Link zur fx.tar.xz eines EMPFOHLENEN Builds von
# https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/
# (auf der Seite einen gruen markierten/"recommended" Build waehlen, mind. so
#  neu, dass er zu sv_enforceGameBuild 3717 passt – aktueller = besser).
ARG FX_URL
RUN test -n "$FX_URL" || (echo "FX_URL fehlt – in .env setzen!" && exit 1) \
    && mkdir -p /opt/cfx && cd /opt/cfx \
    && curl -fSL "$FX_URL" -o fx.tar.xz \
    && tar xf fx.tar.xz \
    && rm fx.tar.xz \
    && chmod +x run.sh

WORKDIR /opt/cfx
# Start kommt aus docker-compose.yml (run.sh + txAdminPort).
CMD ["bash", "/opt/cfx/run.sh"]
