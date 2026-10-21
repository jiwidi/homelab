# Tailscale — runs on the UniFi gateway

There is no Tailscale stack here anymore. The UniFi Cloud Gateway Fiber runs
Tailscale itself as **`ucg-fiber`** (`100.123.251.41`), via the unofficial
[tailscale-unifi](https://github.com/SierraSoftworks/tailscale-unifi) package,
so remote access depends only on the router being up.

Its config lives in the private `unifi-gateway` repo. To change routes: edit
`tailscale/settings.env` there, push, then

```bash
ssh root@100.123.251.41 /data/unifi-gateway/sync.sh
```

New routes need one-time approval: <https://login.tailscale.com/admin/machines>
→ `ucg-fiber` → *Edit route settings*.

## What's reachable from the tailnet

Single-host subnet routes (not whole LANs), plus `ucg-fiber` as an opt-in exit
node:

**sol** — `192.168.2.92` (`gamelab` network)

| Port | Service |
|---|---|
| 22 | SSH — `ssh jiwidi@192.168.2.92` |
| 5001 | Dockge |
| 139 / 445 | Samba |
| game ports | see the gamelab repo |

**truenas** — `192.168.1.60` (`galaxy` network)

| Port | Service |
|---|---|
| 22 | SSH |
| 80 / 443 | TrueNAS web UI |
| 139 / 445 | SMB — `smb://192.168.1.60` / `\\192.168.1.60` |
| 30013 / 30014 | Jellyfin (HTTP / HTTPS) |
| 30357 | Seerr |
| 30025 / 30113 / 30046 / 30050 | Radarr / Sonarr / Bazarr / Prowlarr |
| 30096 | Transmission web UI |

**The gateway itself** — `100.123.251.41` (SSH as root, admin UI on 443).

⚠️ Radarr/Sonarr/Bazarr/Prowlarr have no auth by default and Transmission has
no password. Anyone on the tailnet can reach them — set Forms auth / a password
on each, or restrict the routes with a tailnet ACL.

Clients on Linux must opt in with `tailscale up --accept-routes`
(macOS/iOS/Windows accept routes by default).

With the default SNAT, routed traffic reaches sol and the NAS from the
gateway's LAN address (`192.168.2.1` / `192.168.1.1`), not the client's tailnet
IP — so sol's `who`/logs show the gateway, and UniFi firewall zones need no
extra rules. `gamelab` stays isolated from `galaxy`.

## Finder → Network on a Mac

Bonjour/mDNS is multicast and doesn't cross the tailnet, so the NAS won't
auto-appear in Finder away from home. [`macos/nas-bonjour.sh`](macos/nas-bonjour.sh)
installs a LaunchAgent that announces it locally, so **TrueNAS (Tailscale)**
shows up under Finder → Network anywhere.

## History

1. **luna (Mac mini)** — Tailscale in Docker with per-port `serve.json`
   forwarders, needed because Docker Desktop's VM dropped forwarded traffic.
2. **sol** — Tailscale in Docker (`network_mode: host`) as the subnet router.
   Two gotchas worth remembering if it ever runs there again: set
   `TS_DEBUG_FIREWALL_MODE=nftables` (Debian 13's Docker uses iptables-nft with
   `FORWARD` policy `DROP`, and the image defaults to legacy iptables, so every
   routed packet was silently dropped), and enable IPv6 forwarding in
   `/etc/sysctl.d/` for an exit node.
3. **ucg-fiber** — current. Removed the dependency on any server being up.
