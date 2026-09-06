# aikon-hook.sh moved

The hook script now lives at `Sources/Aikon/Resources/hook/aikon-hook.sh` so
SwiftPM bundles it inside `Aikon.app` (`Bundle.module`). That is the single
source — do not recreate a copy here.

Installing/uninstalling the hook and patching `~/.claude/settings.json` is
now done by the app itself: `Sources/Aikon/HookInstaller.swift`
(`HookInstaller.install()` / `.uninstall()` / `.state()`). The old
`settings-patch.py` and `scripts/uninstall-hook.sh` are gone; their logic
was ported to Swift there.
