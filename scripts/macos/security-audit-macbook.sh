#!/usr/bin/env bash
#
# Phase 13 S1 -- the MacBook half of the read-only audit.
#
# Run on:  the MacBook
# Usage:   bash scripts/macos/security-audit-macbook.sh 2>&1 | tee /tmp/s1-audit-macbook.txt
# Phase:   13 -- Security hardening. Brief §7.1, last sentence.
#
# Collects what can only be seen from the client side: the GitHub account's SSH keys
# (the node key must appear exactly once, by title), the Tailscale ACL as it stands, the
# tailnet's view of the node, and proof that both SSH aliases work concurrently -- the
# case 18.2 broke. Changes nothing. Every block prints what it collects first.

set -u
say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
note() { printf -- '-- %s\n' "$*"; }
run()  { printf '$ %s\n' "$*"; "$@" 2>&1 || note "exit $?"; }
have() { command -v "$1" >/dev/null 2>&1; }

say "GitHub: SSH keys on the owner's account, by title (expect 'homelab node — 2026-09-12' once)"
if have gh; then
  run gh api user/keys --jq '.[] | "\(.title)\t\(.created_at)\t\(.key[0:40])..."'
  say "GitHub: deploy keys on the three push-target repositories (expect none -- 18.2 §6.2 chose an account key)"
  for r in oncla factory-ops brain; do
    owner=$(gh api user --jq .login 2>/dev/null)
    run gh api "repos/$owner/$r/keys" --jq '.[] | "\(.title)\tread_only=\(.read_only)"'
  done
else
  note "gh not installed"
fi

say "Tailscale: the ACL / policy file as it stands (this is the input to brief §6.7)"
TS=/Applications/Tailscale.app/Contents/MacOS/Tailscale
have tailscale || { [ -x "$TS" ] && tailscale() { "$TS" "$@"; }; }
if have tailscale || [ -x "$TS" ]; then
  run tailscale status
  run tailscale status --json --peers=false
  note "The policy file itself is not readable from the CLI. Open the admin console"
  note "  https://login.tailscale.com/admin/acls/file  and paste the whole policy below."
  note "It is configuration, not a secret (brief §9) -- it will be committed under config/tailscale/."
else
  note "tailscale CLI not found"
fi

say "SSH: both aliases, concurrently -- the 18.2 regression test (brief §5, §8 row 4)"
run ssh -o BatchMode=yes -o ConnectTimeout=10 homelab true
# Open the tunnel alias in the background, then test the forward-free alias while it is up.
ssh -o BatchMode=yes -o ConnectTimeout=10 -N homelab-workbench & TUN=$!
sleep 3
if kill -0 "$TUN" 2>/dev/null; then
  note "homelab-workbench session is up (pid $TUN)"
  run ssh -o BatchMode=yes -o ConnectTimeout=10 homelab true
  run curl -m 5 -s -o /dev/null -w 'workbench via tunnel: HTTP %{http_code}\n' http://127.0.0.1:8765/
  kill "$TUN" 2>/dev/null; wait "$TUN" 2>/dev/null
else
  note "homelab-workbench did not stay up (ExitOnForwardFailure? port 8765 busy locally?)"
fi

say "SSH: client config for the two aliases (hostnames only; no key material is printed)"
run ssh -G homelab
note "(look at hostname, identityfile, identitiesonly, localforward)"
run ssh -G homelab-workbench

say "SSH: is the client key the only one, and is it in the agent?"
run ls -la "$HOME/.ssh"
run ssh-add -l

say "Tools this phase will need on the MacBook: age (second key, §6.8)"
run age --version

say "DONE. Nothing was changed. Paste the whole output back, plus the ACL policy from the admin console."
