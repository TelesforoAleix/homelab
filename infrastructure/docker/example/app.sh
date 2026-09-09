#!/bin/sh
# Reports who it is running as, which is the entire point of the image.
echo "greetings from the Home Lab example image"
echo "uid=$(id -u) gid=$(id -g) user=$(id -un)"
if [ "$(id -u)" -eq 0 ]; then
  echo "STATUS: running as ROOT -- on a rootful daemon this is the host's root"
else
  echo "STATUS: running as a non-root user, which is what we want"
fi
