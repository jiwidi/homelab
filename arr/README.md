# Media automation — Prowlarr → Sonarr/Radarr → qBittorrent → Jellyfin

Track shows and movies, download them automatically over a VPN, organise them
into a clean library, and stream to anyone on the tailnet.

```
                  ┌───────────┐
                  │ Prowlarr  │  public torrent indexers
                  └─────┬─────┘  (behind the VPN)
                        │ syncs indexers
          ┌─────────────┴─────────────┐
          ▼                           ▼
     ┌─────────┐                 ┌─────────┐
     │ Sonarr  │ TV              │ Radarr  │ movies
     └────┬────┘                 └────┬────┘
          └──────────┬────────────────┘
                     ▼ sends releases
            ┌──────────────────┐
            │   qBittorrent    │ inside gluetun's netns
            │  → Mullvad WG    │ kill switch: tunnel down = no traffic
            └────────┬─────────┘
                     ▼ downloads to
              /data/torrents/{tv,movies}
                     │ hardlink import + rename (instant, no extra space)
                     ▼
              /data/media/{tv,movies}
                     │
                     ▼
              ┌────────────┐        ┌─────────────┐
              │  Jellyfin  │◀───────│ Jellyseerr  │ request UI
              │  (native)  │        └─────────────┘
              └────────────┘
```

| Service | Port | Notes |
|---|---|---|
| Jellyfin | 8096 | **Native macOS app**, not in this compose file |
| Jellyseerr | 5055 | Request UI — the front door for everyone else |
| Sonarr | 8989 | TV |
| Radarr | 7878 | Movies |
| Bazarr | 6767 | Subtitles |
| qBittorrent | 8082 | Published by **gluetun** |
| Prowlarr | 9696 | Published by **gluetun** |

## Two design decisions worth knowing

**Jellyfin runs natively, not in Docker.** Docker Desktop can't pass the Apple
GPU through to containers, so a containerised Jellyfin would have no
VideoToolbox and would transcode on CPU only. Same reason `llama-cpp` is
bare-metal in this repo. Consequence: containers reach it at
`host.docker.internal:8096`, and it reads `$MEDIA_ROOT/media` straight off the
host filesystem with no bind mount.

⚠️ The Homebrew cask installs `Jellyfin.app` — a menu-bar app, **not** a daemon.
It only runs while someone is logged into the desktop. After a reboot with no
login, Jellyfin will be down. Add it to System Settings → General → Login Items,
and enable auto-login, if you want it to survive unattended restarts.

**One `/data` mount, not two.** qBittorrent, Sonarr, Radarr and Bazarr all get
the single mount `$MEDIA_ROOT:/data`, holding both `torrents/` and `media/`.
Sonarr/Radarr decide whether they can hardlink by comparing mount points, so
splitting this into `/downloads` + `/media` silently disables hardlinking and
turns every import into a full byte copy — double the disk, minutes instead of
milliseconds. Verified working on this host (APFS through VirtioFS).

## VPN

Only qBittorrent and Prowlarr sit behind Mullvad. Sonarr/Radarr/Bazarr/Jellyseerr
talk to APIs and metadata sites where a VPN buys nothing.

Because they share gluetun's network namespace they have **no hostname of their
own** on the docker network. Sonarr/Radarr must be pointed at `gluetun:8082`,
**not** `qbittorrent:8082`.

Verify the tunnel:

```bash
curl -s https://ipinfo.io/ip                                   # your home IP
docker exec gluetun sh -c 'wget -qO- https://am.i.mullvad.net/json'  # must differ,
                                                               # mullvad_exit_ip: true
docker exec qbittorrent sh -c 'wget -qO- https://ipinfo.io/ip' # must equal gluetun's
```

⚠️ **No port forwarding.** Mullvad removed it in July 2023 with no workaround, so
qBittorrent sits in "not connectable": downloads are unaffected, but you only
reach peers who accept inbound connections and seeding ratio suffers. Fine for
public trackers; it would matter on private ones.

⚠️ **Key and address are a matched pair.** `WIREGUARD_ADDRESSES` is assigned by
Mullvad per key. Regenerating the key gets you a new address — update both
together or the tunnel comes up silently and passes no traffic at all
(WireGuard gives no error; the symptom is DNS timeouts in `docker logs gluetun`).

## First-run wiring

1. **qBittorrent** (`:8082`) — user `admin`, temporary password is printed in
   `docker logs qbittorrent`. Set a permanent one immediately in
   Tools → Options → Web UI. Then set default save path `/data/torrents`.
2. **Prowlarr** (`:9696`) — add public indexers, then Settings → Apps → add
   Sonarr (`http://sonarr:8989`) and Radarr (`http://radarr:7878`) with their
   API keys, and Sync App Indexers.
3. **Sonarr** (`:8989`) / **Radarr** (`:7878`) — add download client
   qBittorrent at host `gluetun`, port `8082`. Root folders `/data/media/tv`
   and `/data/media/movies`.
4. **Jellyfin** (`:8096`) — libraries at `~/Videos/library/media/tv` and
   `~/Videos/library/media/movies`. Optionally add `~/Videos/insta360` as a
   "Home Videos" library.
5. **Jellyseerr** (`:5055`) — connect to Jellyfin at
   `http://host.docker.internal:8096`, then Sonarr/Radarr by container name.

## Remote access

Ports are exposed on the tailnet by `../tailscale/serve.json`. Everyone gets
Jellyfin at `luna:8096` and Jellyseerr at `luna:5055`.

## Config

Secrets live in `.env` (gitignored, mode 600); app state in `config/`
(gitignored). Nothing here touches `/Volumes/red`.

| Variable | Purpose |
|---|---|
| `WIREGUARD_PRIVATE_KEY` | Mullvad `.conf` → `[Interface] PrivateKey` |
| `WIREGUARD_ADDRESSES` | Mullvad `.conf` → `[Interface] Address`, **IPv4 only** |
| `MULLVAD_CITY` | Exit location (default Stockholm) |
| `MEDIA_ROOT` | Host path mounted as `/data` |
