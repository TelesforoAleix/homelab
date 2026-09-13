#!/usr/bin/env bash
# Phase 15.1 S3 call 4: attended utility call with the rotated key, unattended exhausted. Run once.
M=/tmp/homelab-agent/p151-s3-call4c.done
[ -e "$M" ] && { echo "STOP: call 4 already attempted: $(cat "$M")"; exit 2; }
date -u +%FT%TZ | tee "$M"
curl -sS --max-time 300 -H 'X-Homelab-Client: p151-s3-new-key-independence' -H 'Content-Type: application/json' \
  -d '{"v":1,"kind":"question","role":"utility","question":"Reply with exactly S3-ROTATED-OK."}' \
  http://127.0.0.1:8766/v1/request
echo
