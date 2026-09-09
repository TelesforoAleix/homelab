# Infrastructure

Host-level and deployment infrastructure lives here as phases introduce it. Do not add tooling
without a concrete phase requirement.

## `docker/`

Phase 05 introduced the Docker/Compose baseline and a small teaching image. It is not a deployed
service stack: the final Phase 05 state has zero containers, images, volumes and build cache items.

Use [`docker/README.md`](docker/README.md) for the example image and the container conventions that
future phases inherit.
