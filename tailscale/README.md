# Tailscale — VPN access to sol

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

Secrets live in `.env` (gitignored); node state in `config/` (gitignored — it
contains `tailscaled.state` with the node key, never commit it).

## What's exposed

**Everything bound on sol**, at `sol:<port>` — ssh 22, samba 139/445, dockge
5001, the game servers, etc. No port list to maintain: unlike the old Mac
setup, there is no VM between the container and the host.

sol advertises **no subnet routes and no exit node**. Those live on the UniFi
gateway — see below.

## The NAS and the exit node: on the gateway, not here

The UniFi Cloud Gateway Fiber runs Tailscale itself as **`ucg-fiber`**
(`100.123.251.41`), via the unofficial
[tailscale-unifi](https://github.com/SierraSoftworks/tailscale-unifi) package.
It is the subnet router for the NAS (`192.168.1.60/32`) and the house's exit
node, so remote access depends only on the router being up — not on sol. Its
config lives in the private `unifi-gateway` repo (edit, push, then
`ssh root@100.123.251.41 /data/unifi-gateway/sync.sh`).

Every NAS port is reachable from the tailnet at `192.168.1.60:<port>`:

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

Clients on Linux must opt in with `tailscale up --accept-routes`
(macOS/iOS/Windows accept routes by default).

Discovery ports (mDNS 5353, WS-Discovery 3702/5357) are multicast and don't
cross a routed tailnet, so the NAS won't auto-appear in Finder/Explorer on its
own. On a Mac, [`macos/nas-bonjour.sh`](macos/nas-bonjour.sh) installs a
LaunchAgent that announces it locally, so **TrueNAS (Tailscale)** shows up
under Finder → Network anywhere. Elsewhere, connect by IP
(`smb://192.168.1.60`).

sol sits on the `gamelab` network, which the gateway isolates from `galaxy`
(sol runs internet-facing game servers). Since sol no longer routes to the
NAS, it needs no firewall exception to reach it.

## If sol ever routes again

Notes from when sol was the subnet router, in case routes move back here:

- **`TS_DEBUG_FIREWALL_MODE=nftables` is required.** Debian 13's Docker uses
  iptables-nft with `FORWARD` policy `DROP`; the tailscale image autodetects
  *legacy* iptables, so its accept rules land in the wrong table and Docker
  drops every subnet-routed packet. Symptom: tailnet clients time out while sol
  itself reaches the target fine, and the drop counter in
  `docker exec tailscale iptables-nft -L FORWARD -v -n` climbs.
- **IPv6 forwarding** for an exit node is a host setting (`sysctls:` can't be
  set with `network_mode: host`). IPv4 is already on via docker; IPv6 needs:
  ```bash
  echo -e 'net.ipv4.ip_forward = 1\nnet.ipv6.conf.all.forwarding = 1' \
    | sudo tee /etc/sysctl.d/99-tailscale.conf && sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
  ```
- Reaching anything on `galaxy` from sol needs a UniFi firewall rule
  `192.168.2.92 → <target>`.

## Auth keys

`TAILSCALE_AUTH_KEY` in `.env` is consumed on first join — the node stays
authenticated via `config/tailscaled.state` afterwards. Rotate keys at
<https://login.tailscale.com/admin/settings/keys>.

## History

The Mac mini ran this as `luna` with per-port `serve.json` forwarders to
`192.168.31.58`, needed because Docker Desktop's VM dropped forwarded traffic.
sol then served as the subnet router until it moved to the gateway.
