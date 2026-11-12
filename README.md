# NPC Sonar

Type an NPC's name and press **Start scan**. When that NPC comes close enough
to show up, the addon puts an icon over its nameplate (skull by default) and
alerts you. It's meant for quests where the mob you need patrols.

## Usage

- `/npcsonar` (or the shortcut `/npcd`) opens or closes the window.
- **Minimap button:** left-click opens the window, and right-click starts or stops the scan. If no name is set yet, right-click opens the window instead. Hover to see what it's scanning for. Drag it around the minimap edge to move it. Minimap button collectors, such as Enhance QoL's button sink, pick it up too.
- **Addons button by the minimap:** where the game has Blizzard's addon compartment, NPC Sonar is also listed there, with the same clicks.
- `/npcsonar <name>` starts scanning for that name. Separate several names with commas.
- `/npcsonar stop` and `/npcsonar start` stop and resume.
- `/npcsonar minimap` hides or shows the minimap button.
- **Target** copies your current target's name into the box.
- **Partial name match** matches any NPC whose name contains the text, so `ashar` finds "Shade of Ashar".
- When a match is found, you get a chat line, an on-screen raid-warning message and a sound.
- **Alert sound** picks that sound. Use the arrows to step through the game's alert sounds (each one plays as you pick it), click the name to hear it again, or choose **None**. Only sounds your client has are listed.

## Marking

Addons aren't allowed to place raid markers on their own. Calling
`SetRaidTarget` from addon code triggers the "blocked from an action only
available to the Blizzard UI" popup. So marking works in two parts:

1. **Nameplate icon (automatic, only you see it).** Every living match gets
   the chosen icon drawn above its nameplate.
2. **The sonar badge (one click, everyone sees the marker).** While
   scanning, a small sonar badge is on screen. Its sweep turns while
   searching; when a match is in range the sweep stops, an orange contact
   appears and the border turns green. The corner shows the
   marker a click will place.
   - **Left-click** targets the NPC and puts a real raid marker on it. On
     clients that have the ping system (retail), it also sends an **attack**
     ping on it. You can also bind this to a key under
     *Key Bindings → AddOns → NPC Sonar*.
   - **Right-click** opens or closes the window.
   - **Right-drag** moves the badge.

   The click runs this macro: `/cleartarget`, `/targetexact <name>` for each
   name (`/target` with partial matching), then `/tm [exists,nodead] <icon>`,
   and `/ping [@target,exists,nodead] attack` where pings exist.

The badge is a secure button, so the game won't let it change during combat.
If you start or stop a scan, or edit the name or marker mid-fight, it shows,
hides or updates its macro when combat ends. Its colours still change in combat.

## How it finds NPCs

Addons can't look up a unit by name, so the scan checks every unit token that
can point at an NPC: target, mouseover, focus and `nameplate1`–`nameplate40`.
It checks every 0.3 s and also whenever a nameplate appears. This means:

- An NPC is found only once it's within nameplate range (about 40–60 yd) or you
  mouse over it. It doesn't search the whole zone.
- **Enemy nameplates must be on** (press V). For friendly quest NPCs,
  friendly NPC nameplates must be on too.
- Dead NPCs are skipped.
- Inside instances, Midnight hides NPC names from addons (they come back as
  secret values). There's no way for an addon to compare them, so the
  automatic icon and alert can't work there. The window says so when it sees
  hidden names. **Clicking the sonar badge still works**, because its macro runs in the
  game's own secure code, which can still read names.
- `/npcsonar debug` prints what the addon can see: client version, whether you're in
  an instance, whether pings exist, and the name, nameplate and match result
  for your target, mouseover and any matching nameplates.

## Install

`python deploy.py` copies `NpcSonar/` into your WoW AddOns folder
(`WOW_ROOT` is set at the top of the script).

## Releasing

Releases work the same way as in the ChattyLittleNpc and Tank Tools repos:

1. Bump `## Version:` in `NpcSonar/NpcSonar.toc` and get the change onto `main`.
2. From `main`, run `python release.py` for a dry run, then
   `python release.py --create`. Add `--type beta` or `--type alpha` for a
   pre-release.
3. The script tags the commit (`v<version>`, plus `-beta`/`-alpha`), pushes the
   tag and creates a GitHub Release.
4. `.github/workflows/release.yml` then zips `NpcSonar/` and attaches
   `NpcSonar-<tag>.zip` to that release.
5. CurseForge packages the tagged commit through the repo's webhook, using
   `pkgmeta.yaml`: the folder is named `NpcSonar`, and dev files, docs and
   `assets/` are left out. Tags without a suffix are Releases; `-beta` and
   `-alpha` tags become Beta and Alpha files. The one-time webhook setup is
   described in `../curseforge-packaging-setup.md`.
