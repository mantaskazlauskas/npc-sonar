# Development

Notes for working on NPC Sonar itself. To install and use the addon, see the
[README](README.md).

## Testing locally

`python deploy.py` copies `NpcSonar/` into a WoW install's
`Interface/AddOns` folder, replacing any copy already there. It lists the WoW
versions it finds (Retail, Classic, PTR and so on) and asks which one to use.

The WoW folder is set by `WOW_ROOT` at the top of the script
(`D:\Games\World of Warcraft`). Change it to match your install.

## Releasing

Releasing needs write access to the repo, to push the tag and create the
GitHub Release.
Releases work the same way as in the ChattyLittleNpc and Tank Tools repos:

1. Bump `## Version:` in `NpcSonar/NpcSonar.toc` and get the change onto `main`.
2. From `main`, run `python release.py` for a dry run, then
   `python release.py --create`. Add `--type beta` or `--type alpha` for a
   pre-release. The script needs the GitHub CLI (`gh`), signed in.
3. The script tags the commit (`v<version>`, plus `-beta`/`-alpha`), pushes the
   tag and creates a GitHub Release.
4. `.github/workflows/release.yml` then zips `NpcSonar/` and attaches
   `NpcSonar-<tag>.zip` to that release.
5. Upload that zip to CurseForge by hand. Nothing packages it there
   automatically.
