# Configuration

Non-secret shared configuration and examples belong here. Never commit live credentials.

## `netplan/`

`50-wifi.example.yaml` is a **redacted example** of the reference node's network configuration
(ADR-016). The real file lives on the server at `/etc/netplan/`, stores the Wi-Fi passphrase in
cleartext, must be mode `0600`, and must never be committed.

## `ssh/`

`10-homelab-hardening.conf` is the real sshd configuration applied to the server (ADR-018), and
contains no secret. `homelab.ssh-config.example` is a template for the operator's `~/.ssh/config`,
with placeholders where the tailnet name goes.

Neither private nor public SSH keys, `authorized_keys`, `known_hosts`, nor a real `~/.ssh/config`
belong in this repository. `.gitignore` carries patterns for all of them as a safety net.

See [`ssh/README.md`](ssh/README.md) for how these are applied — in particular that the drop-in's
`10-` prefix is a security control, and that installing it requires `systemctl reload ssh`.

## `docker/`

`daemon.json` configures Docker log rotation only: `json-file` with `max-size: 10m` and
`max-file: 3`. It exists because Docker logs land on the root logical volume, and this machine's
volume group has no free extents.

See [`docker/README.md`](docker/README.md).

## `sysctl/`

`99-homelab-swappiness.conf` lowers `vm.swappiness` to `10`, closing the Phase 01 item that Phase 05
inherited. It keeps swap available as a safety net while making the server prefer reclaiming cache
before moving active processes to swap.
