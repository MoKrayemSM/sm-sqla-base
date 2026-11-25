# syntax=docker/dockerfile:1.6
#
# sm-sqla-base — the single source of the SQL Anywhere 17 client runtime.
#
# This image owns ONE thing: the extracted, pruned SQLA 17 client at
# /opt/sqlanywhere17 (lib64 driver .so files + res charset/message files).
# It deliberately does NOT bake in Node, a build toolchain, the `sqlanywhere`
# npm binding, or unixODBC — those diverge between consumers:
#
#   * smAdm / smNode / smsys / smLogin / smPublicApis
#       use the `sqlanywhere` npm NATIVE BINDING (node-gyp against SQLANY17).
#   * SmAttachments (sm-aws)
#       uses unixODBC + /etc/odbcinst.ini pointing at libdbodbc17_r.so;
#       it has NO `sqlanywhere` dependency at all.
#
# So every consumer just does, in its own Dockerfile, ONE line instead of a
# whole sqla-installer stage:
#
#   COPY --from=sm-sqla-base:17-bookworm /opt/sqlanywhere17 /opt/sqlanywhere17
#
# and then layers ITS OWN mechanism (node binding OR ODBC) on top.
#
# Build:
#   docker build --build-arg SQLA_TARBALL=sqla17_client_linux_x86x64.tar.gz \
#                -t sm-sqla-base:17-bookworm .
# (or: make build)

# ───────────────────────────── Stage 1: install + prune ─────────────────────────────
# bookworm (glibc 2.36, Debian 12) matches the node:20-bookworm(-slim) bases the
# consumer apps run on, so the driver .so files are ABI-compatible downstream.
FROM debian:bookworm-slim AS installer

ARG SQLA_TARBALL=sqla17_client_linux_x86x64.tar.gz
ARG SQLA_DIR=/opt/sqlanywhere17

# libaio1 is the only shared-lib prereq the silent installer needs to run.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates libaio1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/sqla
COPY ${SQLA_TARBALL} /tmp/sqla/sqla.tar.gz

RUN tar -xzf sqla.tar.gz \
    && INSTALL_DIR="$(find . -maxdepth 2 -type f -name setup -printf '%h\n' | head -n1)" \
    && cd "$INSTALL_DIR" \
    && ./setup -silent -I_accept_the_license_agreement -sqlany-dir ${SQLA_DIR} \
    && rm -rf /tmp/sqla

# Strip everything except the 64-bit driver libs and charset/error resources.
# Keep lib64 (driver .so files) and res (charset/error message files).
RUN cd ${SQLA_DIR} && \
    find . -mindepth 1 -maxdepth 1 \
        ! -name lib64 ! -name res \
        -exec rm -rf {} +


# ───────────────────────────── Stage 2: artifact image ─────────────────────────────
# Minimal final image whose ONLY payload is the pruned client. Consumers pull it
# with `COPY --from`; nothing here ever runs as a container in production.
FROM debian:bookworm-slim

ARG SQLA_DIR=/opt/sqlanywhere17
ENV SQLANY17=${SQLA_DIR} \
    LD_LIBRARY_PATH=${SQLA_DIR}/lib64

# libaio1 so the image is self-verifiable (ldd the driver) without pulling deps.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libaio1 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=installer ${SQLA_DIR} ${SQLA_DIR}

# Sanity layer: fail the build if the core driver lib is missing or unresolved.
RUN test -f "${SQLA_DIR}/lib64/libdbodbc17_r.so" \
    && test -d "${SQLA_DIR}/res" \
    && ldd "${SQLA_DIR}/lib64/libdbodbc17_r.so" | grep -qv 'not found'

CMD ["sh", "-c", "echo 'sm-sqla-base is a COPY --from source image, not a runnable service.' && ls -1 ${SQLANY17}"]
