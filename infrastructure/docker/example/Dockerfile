# Home Lab — Phase 05 teaching image.
#
# Deliberately small and deliberately boring. Its job is to demonstrate three
# things this project cares about, not to be useful:
#
#   1. Running as a NON-ROOT user.
#   2. Why instruction ORDER decides what gets rebuilt.
#   3. That a secret in an early layer survives being deleted in a later one.
#
# Build:  docker build -t homelab-example:1 .
# Run:    docker run --rm homelab-example:1

FROM alpine:3.22

# --- Layer ordering ------------------------------------------------------
#
# Each instruction produces a layer, and a layer is only rebuilt if it or
# something before it changed. So the rule is: least-likely-to-change first.
#
# Installing packages goes ABOVE copying source, because source changes on
# every edit and packages almost never do. Reverse these two and every one
# character change to app.sh re-runs apk, which is slow and pointless.
RUN apk add --no-cache tini

# --- A non-root user -----------------------------------------------------
#
# Without USER, this container runs as root -- and on a rootful daemon with no
# user-namespace remapping, that root is the HOST's root (same user namespace,
# uid 0 == uid 0). Only capabilities and seccomp stand in between. Proven on
# the reference node in guide/05-docker/README.md.
#
# So: create an unprivileged account and switch to it. ADR-011 in container
# form, and the single cheapest security control in this file.
RUN addgroup -g 10001 -S app \
 && adduser  -u 10001 -S app -G app

# Source last: this is the layer that actually changes.
COPY --chown=app:app app.sh /app/app.sh
RUN chmod 0555 /app/app.sh

USER app:app

# tini as PID 1 so signals and zombie processes are handled properly. A shell
# script as PID 1 does not reap children and often ignores SIGTERM, which is
# why `docker stop` on a naive image takes ten seconds and then kills it.
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/app/app.sh"]
