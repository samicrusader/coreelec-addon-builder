# CoreELEC binary-addon SDK: a CoreELEC checkout with the cross toolchain and
# common addon dependencies already built. Build from the repo root:
#
#   docker build -f docker/Dockerfile --build-arg SDK=coreelec-21-amlogic-ng-arm -t coreelec-addon-builder .
#
# Run (see README):
#
#   docker run --rm -v <addon>:/addon:ro -v <out>:/out coreelec-addon-builder

FROM ubuntu:24.04

ARG SDK=coreelec-21-amlogic-ng-arm
ARG SDK_PRUNE=yes

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Host packages CoreELEC's scripts/checkdeps asks for, plus git/ca-certificates.
RUN apt-get update \
 && apt-get install --yes --no-install-recommends \
      bash bc bzip2 ca-certificates diffutils file g++ gawk gcc git gperf gzip \
      lzop make patch patchutils perl python3 rdfind rpcsvc-proto sed tar \
      unzip wget xz-utils zip zstd \
      libc6-dev libncurses-dev libjson-perl libparse-yapp-perl \
      libxml-parser-perl xfonts-utils xsltproc default-jre-headless \
 && rm -rf /var/lib/apt/lists/*

# CoreELEC refuses to build as root. Reuse the image's uid 1000 user.
RUN usermod -l builder -d /home/builder -m ubuntu \
 && groupmod -n builder ubuntu \
 && mkdir -p /build /out \
 && chown builder:builder /build /out

COPY --chown=builder:builder scripts/ /opt/sdk/scripts/
COPY --chown=builder:builder sdk/${SDK}/ /opt/sdk/${SDK}/
RUN ln -s /opt/sdk/${SDK} /opt/sdk/current \
 && chmod +x /opt/sdk/scripts/*.sh

USER builder
WORKDIR /build

# One layer: build everything and prune it before the layer is committed, so
# the intermediate build trees never end up in the image.
RUN SDK_PRUNE=${SDK_PRUNE} /opt/sdk/scripts/prepare-sdk.sh /opt/sdk/current

ENTRYPOINT ["/opt/sdk/scripts/build-addon.sh"]
CMD []
