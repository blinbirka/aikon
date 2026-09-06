# Security

Aikon is a solo hobby project. There is no security team and no SLA, but
reports are read and taken seriously.

## Reporting a vulnerability

Open an issue at https://github.com/blinbirka/aikon/issues, or email
[dorogova.ann@gmail.com](mailto:dorogova.ann@gmail.com) (the address listed
in [README.md](README.md)) if you'd rather not file it publicly.

There is no fixed response time to promise. Include what you found, how to
reproduce it, and the version of Aikon (Settings shows it).

## Scope

In scope: the Aikon app itself (this repository) and the install/build
scripts in `scripts/`.

Out of scope: Claude Code, VS Code, and GitHub's API. Report issues with
those to their own maintainers.

## What Aikon actually does with your data

This is what the code does, not a promise beyond what's checked in:

- It reads Claude Code session transcript files from disk, locally, from the
  folder set in Settings (`~/.claude/projects` by default). It also reads
  the list of folders VS Code currently has open. Neither leaves the
  machine.
- It makes exactly one network request: an unauthenticated `GET` to
  `api.github.com` to check for the latest release, at most once every three
  days. It carries no auth header, no cookies, and no body. It can be
  switched off entirely in Settings. Off means no request is made, not
  "made and ignored".
- It sends no telemetry and no analytics of any kind.
- Before it registers its session-status hook, it backs up
  `~/.claude/settings.json` and only then adds its own hook entry, leaving
  the rest of the file alone.
