# Agent notes

This repository is a Windows port of [omacut](https://github.com/omacom/omacut)
kept as **upstream + patches**, not as a copy. There is no omacut source here:
`bin/prepare-source.ps1` assembles it in `work/` from upstream at
`UPSTREAM_VERSION`, plus `overlay/` and `patches/`.

Read [PORT.md](PORT.md) before changing anything. It holds the layout, the
rules about what goes in a patch and what goes in the overlay, the intent
behind every patch (enough to rewrite one from scratch), and the procedure
for moving to a new upstream release.

Never commit `work/`, and never leave a change only in `work/`. Export it with
`bin/export-patches.ps1`.
