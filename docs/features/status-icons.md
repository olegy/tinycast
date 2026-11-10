# Status icons

Small emoji at the right of the launcher's search field that show a state which changes on its own,
so the macOS menu bar can do without the menu-bar item that used to show it. Each icon may run one
Custom Command on click. The feature lives in `Features/StatusIcons/`.

The feature ships **off**. **Settings → Status Icons** carries the switch and one section per
source. v1 has one source, **DNS**: 🔒 while every DNS resolver is local — a dnscrypt-proxy on
`127.0.0.1`, say — 🌐 while one is the provider's, and 🤷 when there is none to read.

## Invariants

- **No timers.** A source is event-driven: DNS subscribes to `SCDynamicStore`'s
  `State:/Network/Global/DNS` key, and reads once when the subscription starts. A subscription
  lives only while the feature and its source are both on; `StatusIconCoordinator.applyEnabled()`
  starts and stops it, and the monitor stops itself on `deinit`.
- **The icons never change how the palette behaves.** Selection, keys, Escape, Compact and the
  bottom bar are exactly what they are with the feature off. An icon is a mouse target and a
  `.help()` tooltip, nothing else; it never takes focus or a key.
- **Only the root search shows them**, in the expanded palette, after the search field and before
  the header's trailing gutter. `RootPaletteView.showsStatusIcons` gates them: the field ends where
  they begin, and they step aside while an argument strip (`headerAccessory`) owns the row.
- **The bottom bar is not theirs.** Its left side is for status messages — an extension's toast
  today, a screen's item count later.
- **Everything stays in the feature folder.** `StatusIconStrip` draws each icon as an emoji inside
  a compact `.rounded` `BarButton`, so hover and press darken it exactly like the footer's hints;
  nothing is added to `DesignSystem/`.
- **A click runs through `CustomCommandCoordinator.runCustomCommand(id:)`**, the funnel the
  launcher and hotkeys use, so the feature switch, the command's `isEnabled`, confirmation and
  arguments all apply, and the palette closes as it does for any command. With no command chosen,
  Custom Commands off, or the command deleted or disabled, the icon is not a button: it keeps its
  tooltip and has no hover fill.

## Layout

| File | Role |
| --- | --- |
| `Model/StatusReading.swift` | What one icon draws: an emoji and its tooltip |
| `Model/DNSStatus.swift` | Classifies resolvers against the Local resolvers list, parses that list |
| `Service/DNSResolverMonitor.swift` | The `SCDynamicStore` subscription, delivered on the main queue |
| `UI/StatusIconCoordinator.swift` | Current readings, `applyEnabled()`, click → command |
| `UI/StatusIconStrip.swift` | The row of icons in the search bar |
| `Settings/StatusIconsSettingsView.swift` | The pane |

There is no `Store`: the state is one reading the coordinator holds. Add one when a second source
arrives. `status-icons-test` compiles `Model/`.

## DNS

`DNSStatus.classify` is `.local` when every resolver is in the Local resolvers list, `.external`
when any is not, and `.noServers` when there are none. The list is the setting's comma-separated
text (`127.0.0.1, ::1` by default), trimmed and lowercased, so an IPv6 address matches whatever its
case.

| State | Emoji | Tooltip |
| --- | --- | --- |
| local | 🔒 | `DNS: 127.0.0.1 — local` |
| external | 🌐 | `DNS: 192.168.1.1 — not local` |
| no servers | 🤷 | `DNS: no servers` |

**Known limitation:** `State:/Network/Global/DNS` holds the primary service's resolvers. A VPN that
installs a scoped resolver of its own, for its domains only, is not reflected.

## Settings

`statusIconsEnabled`, `statusDNSEnabled` and `statusDNSLocalResolvers` are in settings backups and
in `settings.json` (`statusIcons.enabled`, `statusIcons.dnsEnabled`,
`statusIcons.dnsLocalResolvers`). `statusDNSCommand`, the chosen command's UUID, travels in backups
with the commands it names, but stays out of `settings.json` like every other reference to a custom
command. The picker lists enabled commands only; a stored command that is gone or disabled reads as
Nothing.
