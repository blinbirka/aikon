# Aikon — notes for coding agents

A macOS menu-bar app that shows the state of Claude Code sessions. Swift 6,
SwiftUI, SwiftPM, no third-party dependencies.

## Install it in one command

```sh
bash scripts/install.sh
```

Builds a universal release, assembles and signs `Aikon.app`, replaces
`/Applications/Aikon.app`, and checks the signature afterwards. The script
refuses to run and says why if the machine is missing something.

Requirements it checks: macOS 14+, Xcode command line tools, Swift 6.0+.

The app has no Dock icon (`LSUIElement`); after installing, look in the menu
bar. Login-at-startup and the session-status hook are switched on inside the
app's own Settings window, not by the installer.

## Everyday commands

```sh
swift build -c release      # build
swift test                  # full suite, fast, no network, no fixtures on disk
bash scripts/bundle.sh 0.1.0   # build + assemble + sign build/Aikon.app
bash scripts/release.sh 0.1.0  # the zip that goes to a GitHub release
```

`scripts/release.sh` builds from `git archive HEAD` inside a temp directory
outside `$HOME`. That is deliberate: SwiftPM bakes the build directory's
absolute path into the binary, so building a release from a checkout under
`/Users/<name>` ships that name inside the app where `strings` finds it. Keep
the copy-out-of-home step and the `$HOME` check at the end of that script.

Uncommitted changes never reach a release build. Commit first, then release.

## Layout

| Path | What lives there |
|---|---|
| `Sources/Aikon/` | the app; one type per file, named after the file |
| `Sources/Aikon/Resources/hook/aikon-hook.sh` | the hook the app installs into `~/.claude/settings.json` |
| `Sources/Aikon/Resources/*.lproj/` | English and Russian interface strings |
| `Tests/AikonTests/` | the whole suite, one file per source file |
| `scripts/` | build, bundle, release, install |

## House rules

- **Everything in the repository is in English** — code, comments, test names,
  commit messages. The interface itself is bilingual through the string files.
- **Every user-visible string goes through `L.string` / `L.format`** and must
  exist in both `en.lproj` and `ru.lproj`. A guard test walks every source file
  and fails on a missing key, and forbids `NSLocalizedString`,
  `String(localized:)` and `bundle: .module` anywhere outside `L.swift`.
- **Comments say why, not what.** The code says what.
- **The app is signed ad-hoc at the end of `bundle.sh`, after every file is in
  place.** Copying anything into the bundle afterwards invalidates the
  signature, and macOS then refuses the app as damaged with no way around it.
- **The update check is a single unauthenticated GET to the GitHub releases
  API, at most once every three days, switchable off in Settings.** Nothing
  else leaves the machine. If that ever changes, `README.md`, `README.ru.md`,
  `SECURITY.md` and the About screen all have to change with it.

## Known limits

- Editors: VS Code and its forks (Cursor, Windsurf, VSCodium). Zed and the
  JetBrains IDEs keep their open windows somewhere else and are not supported
  yet — issue #1.
- Apple Silicon and Intel, macOS 14 and newer.
