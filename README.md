[English](README.md) · [Русский](README.ru.md)

# Aikon

Aikon shows the status of AI coding sessions inside your IDE. Right now it
works with Claude in VS Code.

![Aikon in the menu bar](docs/demo.gif)

Every folder with a session is in the menu, with its state and the time since
the last activity. Click a line and that folder's VS Code window comes to the
front.

## Install

1. Download `Aikon.zip` from [Releases](../../releases), unzip it, drag **Aikon**
   into Applications.
2. macOS will say the app is damaged or comes from an unidentified developer.
   Clear the quarantine flag:

   ```sh
   xattr -cr /Applications/Aikon.app
   ```

3. Launch Aikon. Open **Settings → Status hook → Install**.

Step 3 is what makes the difference between *"Claude is busy"* and *"Claude asked
you something and stopped"*. The hook adds one line to `~/.claude/settings.json`,
backs the file up first, and leaves your other hooks alone. Remove it from the
same screen.

## What it reads

Session transcripts from the folder set in Settings (`~/.claude/projects` by
default) and the list of folders VS Code has open. Both already sit on your disk.

Aikon makes one network request: to GitHub, at most once every three days, to check for a
newer release. Turn it off in Settings and it's gone entirely. Nothing else
goes out — no analytics, no project names, no session text.

## Requirements

macOS 14 or newer, VS Code, Claude Code.

Only VS Code for now. Cursor, Zed and JetBrains each keep their open windows in
a different place, so each needs its own bit of code. There is an open issue if you want to help.

## Build from source

```sh
swift build -c release
bash scripts/install.sh
```

No dependencies, about 2 MB when built.

## Author

**Anna Dorogova**

[GitHub](https://github.com/blinbirka) ·
[adorogova.com](https://adorogova.com) ·
[LinkedIn](https://www.linkedin.com/in/annadorogova/) ·
[dorogova.ann@gmail.com](mailto:dorogova.ann@gmail.com)

MIT licence.
