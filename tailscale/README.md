# Tailscale — VPN access to this Mac mini

Runs as a Docker container (dockge-managed, like the rest of the homelab).

```bash
docker compose up -d
docker exec tailscale tailscale status
```

| | |
|---|---|
| Tailnet name | `luna` (was `homelab-mac`) |
| Tailnet IP | `100.103.226.10` |
| Proxies to | `192.168.31.58` (the Mac's LAN IP, hardcoded in `serve.json`) |

Secrets live in `.env` (gitignored); node state in `config/` (gitignored — it
contains `tailscaled.state` with the node key, never commit it).

---

## What's exposed

**Only the ports listed in `serve.json`** — the Mac itself is not a tailnet node,
the container is, so an unlisted port simply isn't there. Each entry is a TCP
forwarder that terminates in the container and re-dials the Mac's LAN IP:

| Port | Service |
|---|---|
| 22 | ssh (needs macOS Remote Login — see below) |
| 5001 | dockge |
| 8000 | oMLX LLM server |
| 8081 | speedtest-tracker |
| 61208 | glances |
| 8096 | jellyfin (native) |
| 5055 | jellyseerr — request UI |
| 8989 / 7878 / 6767 | sonarr / radarr / bazarr |
| 8082 / 9696 | qbittorrent / prowlarr (via gluetun) |

To add one, add a `"<port>": { "TCPForward": "192.168.31.58:<port>" }` line and
`docker compose up -d --force-recreate`. Only services bound to **all**
interfaces work; anything on `127.0.0.1` is unreachable via the LAN IP by design.

`8082`/`9696` are published by the gluetun container, so they only answer while
the VPN tunnel is up — that's the kill switch working, not a fault.

Plus, as a **subnet router**, the whole home LAN `192.168.31.0/24` — router, NAS,
printers, any other host — and an **exit node** for routing internet traffic
through the house.

### ⚠️ Routes need one-time approval

Advertised but **not yet active**. Until approved, subnet + exit-node traffic
won't flow (direct access to the Mac via the tailnet IP works regardless):

<https://login.tailscale.com/admin/machines> → `luna` → **⋯** → *Edit route
settings* → enable the subnet route and "Use as exit node".

Check from here with:

```bash
docker exec tailscale tailscale status --json | python3 -c \
  "import sys,json;s=json.load(sys.stdin)['Self'];print(s.get('PrimaryRoutes'),s.get('ExitNodeOption'))"
```

`PrimaryRoutes: None` / `ExitNodeOption: False` means still unapproved.

### What is NOT reachable

Services bound to `127.0.0.1` on the Mac stay invisible, because the proxy
forwards to the Mac's *LAN* address:

| Port | Service | Why |
|---|---|---|
| 2375 | dockerproxy | loopback-only **by design** — it's a Docker socket, exposing it would hand out root-equivalent control. Leave it. |
| 52549 | colima/limactl | internal |
| 6061 | ssh tunnel | internal |

## SSH

`ssh luna` (or `ssh 100.103.226.10`) needs **both** halves, or it hangs/refuses:

1. **sshd running on the Mac** — macOS Remote Login is off by default:
   ```bash
   sudo systemsetup -setremotelogin on     # System Settings → General → Sharing → Remote Login
   ```
2. **port 22 forwarded** — it's in `serve.json`, applied on container start.

If `:22` is ever refused (Tailscale SSH reserves it when enabled tailnet-wide),
map a different tailnet port to it instead — `"2222": { "TCPForward":
"192.168.31.58:22" }` — and use `ssh -p 2222 luna`.

Note the Mac sees every SSH connection as coming from the *container*, not your
laptop, since serve re-dials. Per-source-IP rules and `last` will show a Docker
address. The host key is the Mac's real one, though.

## Reaching the LLM server from a laptop

Once the laptop is on the same tailnet:

```bash
export OMLX_HOST=100.103.226.10        # or: luna
export OMLX_KEY=<key from ../unsloth/.env>
../omlx/claude-remote.sh
```

Unlike the LAN address, this works from anywhere, not just the home WiFi.

## Why this compose differs from the original

The previous `tailscale/docker-compose.yaml` (commit `3a69f34`) was written for a
**Linux** host and cannot work on macOS. Three things had to change:

**1. `/dev/net/tun` must be a device, not a volume.** The original bind-mounted
it. Bind mounts resolve on the *Mac* filesystem, which has no such device;
`devices:` resolves inside Docker's Linux VM, which does. Verified with
`docker run --rm --device /dev/net/tun alpine ls -l /dev/net/tun`.

**2. `network_mode: host` doesn't do what you want here.** Under Docker Desktop
the "host" is the Linux VM, not the Mac — so a host-network container still
cannot expose services bound on macOS. This is almost certainly why the original
setup never worked and Twingate was adopted instead in `f5b8274`.

The replacement is per-port TCP forwarders declared in **`serve.json`**
(`TS_SERVE_CONFIG`). `TS_DEST_IP` — the env-only way to proxy every port to the
host — was tried first and does **not** work under Docker Desktop on macOS: the
DNAT applies correctly inside the container (rule counters increment, packets get
masqueraded, ts-forward ACCEPTs them) but the VM's network layer only passes
container-*originated* connections out to the LAN, not *forwarded* ones. Silent
hang, SYN retries, backend never sees a thing. `tailscale serve` sidesteps it by
terminating the connection in the container and opening a fresh outbound one.

If you ever need true all-ports access, run the **native** client on the Mac
(`brew install tailscale`) so the Mac itself is the node and no proxy exists.

**3. `TS_USERSPACE=false` must be explicit.** The image defaults to userspace
networking, and `TS_DEST_IP` is rejected in that mode with
`TS_DEST_IP is not supported with TS_USERSPACE`. Omitting the variable is not
enough — it has to be set to `false`.

## Why not the official installer

```bash
curl -fsSL https://tailscale.com/install.sh | sh   # ← Linux only
```

On macOS this script detects Darwin, sets `PACKAGETYPE=appstore` and delegates
to the App Store. It installs **no CLI**, so a chained `tailscale up --auth-key=...`
fails with "command not found".

The native alternative is `brew install tailscale` (formula, not cask — the GUI
app needs a logged-in desktop session, the formula runs `tailscaled` as a root
LaunchDaemon via `sudo brew services start tailscale`). That works fine and gives
kernel-mode networking on the Mac itself, but it needs `sudo` and sits outside
the docker-compose/dockge convention the rest of this homelab uses. Docker was
chosen for consistency.

## Caveats

- **The Mac itself is not a tailnet member** — the *container* is. The Mac can't
  route to `100.x` addresses. That's fine for serving, but if you ever want the
  mini to reach other tailnet nodes, you'd need the native client instead.
- **Userspace vs kernel**: we use kernel mode, which is faster, but it requires
  the tun device and `NET_ADMIN`/`NET_RAW`.
- **The Mac's LAN IP is hardcoded** in `serve.json` (`192.168.31.58`, once per
  port — compose can't interpolate into a mounted file). If the DHCP lease
  changes, every forwarder breaks: set a DHCP reservation on the router, or
  `sed -i '' 's/192\.168\.31\.58/<new>/g' serve.json` and recreate. `MAC_LAN_IP`
  in `.env` is now unused.
- **Two VPNs now run here.** Twingate (`../twingate/`) is still active and does
  the same job. Decide whether to keep both; Twingate has per-user resource
  grants, which is the better tool for giving *other people* access without
  sharing the LLM API key.

## Auth keys

`TAILSCALE_AUTH_KEY` in `.env` is single-use by default and is consumed on first
join — the node stays authenticated via `config/tailscaled.state` afterwards.
Rotate keys at <https://login.tailscale.com/admin/settings/keys>.
