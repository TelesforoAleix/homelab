# Configuration

Non-secret shared configuration and examples belong here. Never commit live credentials.

## `netplan/`

`50-wifi.example.yaml` is a **redacted example** of the reference node's network configuration
(ADR-016). The real file lives on the server at `/etc/netplan/`, stores the Wi-Fi passphrase in
cleartext, must be mode `0600`, and must never be committed.
