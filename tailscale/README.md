# Tailscale — VPN access to sol (and the NAS)

Runs as a Docker container (dockge-managed, like the rest of the homelab) in
`network_mode: host`, so **sol itself is the tailnet node**.

```bash
docker compose up -d
docker exec tailscale tailscale status
```

| | |
|---|---|
| Tailnet name | `sol` |
| Tailnet IP | `100.110.134.79` |
| LAN IP | `192.168.2.92` (`gamelab` network) |
| Subnet route | `192.168.1.60/32` — the TrueNAS box on `galaxy` |

Secrets live in `.env` (gitignored); node state in `config/` (gitignored — it
contains `tailscaled.state` with the node key, never commit it).

## What's exposed

**Everything bound on sol**, at `sol:<port>` — ssh 22, samba 139/445, dockge
5001, the game servers, etc. No port list to maintain: unlike the old Mac
setup, there is no VM between the container and the host.

**Every port on the NAS**, at `192.168.1.60:<port>`, via the `/32` subnet
route (only the NAS, not the rest of `galaxy`):

| Port | Service |
|---|---|
| 22 | SSH |
| 80 / 443 | TrueNAS web UI |
| 139 / 445 | SMB — `smb://192.168.1.60` / `\\192.168.1.60` |
| 30013 / 30014 | Jellyfin (HTTP / HTTPS) |
| 30357 | Seerr |
| 30025 / 30113 / 30046 / 30050 | Radarr / Sonarr / Bazarr / Prowlarr |
| 30096 | Transmission web UI |

⚠️ Radarr/Sonarr/Bazarr/Prowlarr have no auth by default and Transmission has
no password. Anyone on the tailnet who can use the route can reach them — set
Forms auth / a password on each, or restrict the route with a tailnet ACL.

Discovery ports (mDNS 5353, WS-Discovery 3702/5357) are multicast and don't
cross a routed tailnet, so the NAS won't auto-appear in Finder/Explorer;
connect by IP.

### ⚠️ Prerequisite: gamelab → galaxy firewall rule

sol is on the `gamelab` network, which the UniFi gateway isolates from
`galaxy` — sol cannot even ping the NAS. Until that changes, the route is
advertised but carries nothing. Add a UniFi firewall rule allowing
**source 192.168.2.92 → destination 192.168.1.60** (any port, or just the ones
above). Keep the rest of the isolation: sol runs internet-facing game servers.

Test from sol: `timeout 2 bash -c '</dev/tcp/192.168.1.60/445' && echo ok`

### ⚠️ Routes need one-time approval

<https://login.tailscale.com/admin/machines> → `sol` → **⋯** → *Edit route
settings* → enable `192.168.1.60/32` and "Use as exit node".

Clients on Linux must opt in with `tailscale up --accept-routes`
(macOS/iOS/Windows accept routes by default).

### Firewall backend: nftables

`TS_DEBUG_FIREWALL_MODE=nftables` in the compose file is required. Debian 13's
Docker uses iptables-nft with `FORWARD` policy `DROP`; the tailscale image
autodetects *legacy* iptables, so its accept rules land in the wrong table and
Docker drops every subnet-routed packet. Symptom: tailnet clients time out on
`192.168.1.60` while sol itself reaches the NAS fine, and the drop counter in
`docker exec tailscale iptables-nft -L FORWARD -v -n` climbs.

### IPv6 forwarding (exit node)

`sysctls:` can't be set with `network_mode: host`, so forwarding is a host
setting. IPv4 is already on (docker enables it); IPv6 needs root, once:

```bash
echo -e 'net.ipv4.ip_forward = 1\nnet.ipv6.conf.all.forwarding = 1' \
  | sudo tee /etc/sysctl.d/99-tailscale.conf && sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
```

Until then tailscale logs "Subnet routing is enabled, but IP forwarding is
disabled" (it's the IPv6 half); the IPv4 NAS route and IPv4 exit traffic work.

## Auth keys

`TAILSCALE_AUTH_KEY` in `.env` is consumed on first join — the node stays
authenticated via `config/tailscaled.state` afterwards. Rotate keys at
<https://login.tailscale.com/admin/settings/keys>.

## History

The Mac mini ran this as `luna` with per-port `serve.json` forwarders to
`192.168.31.58`, needed because Docker Desktop's VM dropped forwarded traffic.
`luna` still exists in the tailnet (offline) — remove it in the admin console
once the Mac is retired so it stops offering a stale exit node.
