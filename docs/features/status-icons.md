# Status icons

Small tiles at the left of the palette's bottom bar that show a state which changes on its own, so
the macOS menu bar can do without the menu-bar item that used to show it. Each icon may run one
Custom Command on click. The feature lives in `Features/StatusIcons/`.

The feature ships **off**. **Settings → Status Icons** carries the switch and one section per
source. v1 has one source, **DNS**: a lock that is closed while every DNS resolver is local — a
dnscrypt-proxy on `127.0.0.1`, say — and open on an orange-tinted tile otherwise.

## Invariants

- **No timers.** A source is event-driven: DNS subscribes to `SCDynamicStore`'s
  `State:/Network/Global/DNS` key, and reads once when the subscription starts. A subscription
  lives only while the feature and its source are both on; `StatusIconCoordinator.applyEnabled()`
  starts and stops it, and the monitor stops itself on `deinit`.
- **The icons never change how the palette behaves.** Selection, keys, Escape, Compact and the
  action group on the right are exactly what they are with the feature off. An icon is a mouse
  target and a tooltip, nothing else; it never takes focus or a key.
- **Only the root search shows them**, in the expanded palette. `RootPaletteView.bottomBarLeading`
  is the screen's slot on the left of the bar, chosen by `vm.mode`; another screen may put its own
  facts there later without touching this feature.
- **The action hints win the width.** The action group keeps `.fixedSize()`; the strip sits in a
  `ViewThatFits` and gives way whole when the bar runs short, rather than squeezing a tile.
- **Everything stays in the feature folder.** The tile is drawn by `StatusIconStrip` from `Theme`'s
  base tokens (`controlSurface`, `warning`, `textSecondary`/`textPrimary`) and the `metrics` scale;
  nothing is added to `DesignSystem/`, and `SymbolTile` stays the extensions' own.
- **A click runs through `CustomCommandCoordinator.runCustomCommand(id:)`**, the funnel the
  launcher and hotkeys use, so the feature switch, the command's `isEnabled`, confirmation and
  arguments all apply, and the palette closes as it does for any command. With no command chosen,
  Custom Commands off, or the command deleted or disabled, the tile is not a button: it keeps its
  tooltip and has no hover highlight.

## Layout

| File | Role |
| --- | --- |
| `Model/StatusReading.swift` | What one icon draws: symbol, tone (`.normal`/`.attention`), tooltip |
| `Model/DNSStatus.swift` | Classifies resolvers against the Local resolvers list, parses that list |
| `Service/DNSResolverMonitor.swift` | The `SCDynamicStore` subscription, delivered on the main queue |
| `UI/StatusIconCoordinator.swift` | Current readings, `applyEnabled()`, click → command |
| `UI/StatusIconStrip.swift` | The row of tiles in the bottom bar |
| `Settings/StatusIconsSettingsView.swift` | The pane |

There is no `Store`: the state is one reading the coordinator holds. Add one when a second source
arrives. `status-icons-test` compiles `Model/`.

## DNS

`DNSStatus.classify` is `.local` when every resolver is in the Local resolvers list, `.external`
when any is not, and `.noServers` when there are none. The list is the setting's comma-separated
text (`127.0.0.1, ::1` by default), trimmed and lowercased, so an IPv6 address matches whatever its
case.

| State | Glyph | Tile | Tooltip |
| --- | --- | --- | --- |
| local | `lock.fill` | neutral | `DNS: 127.0.0.1 — local` |
| external | `lock.open.fill` | orange-tinted | `DNS: 192.168.1.1 — not local` |
| no servers | `lock.open.fill` | neutral | `DNS: no servers` |

No servers is offline rather than a leak, so it asks for no attention.

**Known limitation:** `State:/Network/Global/DNS` holds the primary service's resolvers. A VPN that
installs a scoped resolver of its own, for its domains only, is not reflected.

## Settings

`statusIconsEnabled`, `statusDNSEnabled` and `statusDNSLocalResolvers` are in settings backups and
in `settings.json` (`statusIcons.enabled`, `statusIcons.dnsEnabled`,
`statusIcons.dnsLocalResolvers`). `statusDNSCommand`, the chosen command's UUID, travels in backups
with the commands it names, but stays out of `settings.json` like every other reference to a custom
command. The picker lists enabled commands only; a stored command that is gone or disabled reads as
Nothing.
