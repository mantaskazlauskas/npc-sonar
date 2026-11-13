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
- **NPC rows:** each NPC has its own row. **+ Add NPC** adds one (up to 8) and
  **x** removes it. **Target** puts your current target's name in the first
  empty row.
- **Marker and sound per NPC:** each row has a marker button and a sound
  button that open a small menu. **Default** follows the **Default marker**
  tiles and **Default sound** below. NPCs with their own marker get ping rings
  and a radar arrow in that marker's colour. A marker can also be typed after a
  name, as in chat: `Grimtooth {skull}` (also `{rt1}`–`{rt8}`), which is how
  `/npcsonar Grimtooth {skull}, Shade of Ashar` sets them. Changing a marker or
  sound applies to a running scan at once; changed names need **Restart scan**.
- **Saved lists:** the `< name >` row at the top loads saved lists, NPC rows
  with their markers and sounds. **Save** keeps the current rows under a name
  and **Del** deletes the list shown (after asking). Also
  `/npcsonar save|load|delete <list>` and `/npcsonar lists`. Loading over
  unsaved names prints them to chat first.
- **Partial name match** matches any NPC whose name contains the text, so `ashar` finds "Shade of Ashar".
- **Keep target's nameplate on screen:** while scanning, holds your target's
  plate at the screen edge when it's off screen (Retail:
  `nameplateTargetRadialPosition`; Classic: the `nameplate*Inset` CVars, which
  hold every plate, not just the target's). Your
  values are restored when the scan stops, at logout, and at next login.
- **Stop looking for an NPC once it dies:** a found NPC seen dead drops its name
  from the running scan; the scan stops when no names are left.
- When a match is found, you get a chat line, an on-screen raid-warning
  message, a sound, and a taskbar flash if the game isn't focused.
- **Radar (Track rares on the minimap with an arrow):** matching minimap
  vignettes (rares, special NPCs) are announced from far away, and a draggable
  arrow points at the nearest one with its distance, a small turning model of
  the NPC and its level (known once you've seen that NPC up close; `??` until
  then, and on Retail scaled rares show your level). With **Set a map waypoint
  on rares it finds**, a waypoint is dropped on it too, unless you have placed
  your own. Inside instances there are no positions, so it can only alert,
  with no arrow or waypoint. Classic clients without minimap vignettes get
  nothing from it.
- **Sightings:** where and when each name was last seen is kept between
  sessions. **Waypoint**, **Share** (group chat, or guild when solo) and
  **Log** act on them; also `/npcsonar waypoint|share|log`.
- **Default sound** picks the sound for NPCs whose sound is Default. Use the arrows to step through the game's alert sounds (each one plays as you pick it), click the name to hear it again, or choose **None**. Only sounds your client has are listed.

## Marking

Addons aren't allowed to place raid markers on their own. Calling
`SetRaidTarget` from addon code triggers the "blocked from an action only
available to the Blizzard UI" popup. So marking works in two parts:

1. **Nameplate icon (automatic, only you see it).** Every living match gets
   the chosen icon drawn above its nameplate.
2. **The sonar badge (one click, everyone sees the marker).** A small sonar
   badge is always on screen. While idle it sits still and slightly dimmed;
   while scanning its sweep turns; when a match is in range the sweep stops,
   an orange contact appears and the border turns green. The corner shows
   the marker a click will place.
   - **Left-click** while idle starts the scan (or opens the window if no
     name is set). While scanning it targets the NPC and puts a real raid
     marker on it. On clients that have the ping system (retail), it also
     sends an **attack** ping on it. You can bind this to a key or controller
     button under *Key Bindings → AddOns → NPC Sonar*.
   - **Right-click** opens or closes the window.
   - **Right-drag** moves the badge.

   The click runs this macro: `/cleartarget`, `/targetexact <name>` for each
   name (`/target` with partial matching), then `/tm [exists,nodead] <icon>`,
   and `/ping [@target,exists,nodead] attack` where pings exist. When names
   carry their own markers, each name is cleared, targeted and marked in turn,
   and a last pass leaves you targeting the first-listed name that's around.

The badge is a secure button, so the game won't let it change during combat.
If you start or stop a scan, or edit the name or marker mid-fight, it updates
its macro when combat ends. Its colours and sweep still change in combat.

## How it finds NPCs

Addons can't look up a unit by name, so the scan checks every unit token that
can point at an NPC: target, mouseover, focus and `nameplate1`–`nameplate40`.
It checks every 0.3 s and also whenever a nameplate appears. This means:

- An NPC is found only once it's within nameplate range (about 40–60 yd) or you
  mouse over it. It doesn't search the whole zone. The exception is NPCs with
  a minimap vignette (rares and the like), which the radar sees much further out.
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
