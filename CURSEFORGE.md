# NPC Sonar

**Stop hunting for that one patrolling quest mob.** Type its name and start a scan. NPC Sonar keeps sweeping the area around you and alerts you the moment your target comes into view. It also marks it, so you can spot it in a crowd.

## What it does

- **Finds NPCs by name.** Enter a name, and click **+ Add NPC** for each extra one (up to 8). Turn on partial matching and `ashar` will find "Shade of Ashar". Or target the NPC once and click **Target** to add its name.
- **Marks them on your screen.** Every matching NPC gets your chosen raid icon (skull, cross, moon and so on) floating over its nameplate, with sonar rings pinging out behind it. Only you see it, and it updates live as mobs come and go.
- **A marker and sound per NPC.** Every NPC row has its own marker and alert sound button, so the skull rare and the star rare look and sound different, with matching ring colours and raid markers. Leave them on Default to use the shared choice.
- **Spots rares from far away.** Rares and other special NPCs show on your minimap long before they get a nameplate. When one matches, you're alerted, an arrow on screen points at it with the distance and a small model of the NPC with its name and level, and a map waypoint is dropped on it. Made for Retail; on Classic it works only where the game shows such icons on the minimap.
- **Alerts you.** When a match appears, you get a chat message, an on-screen raid-warning message, a sound and a flashing taskbar icon if the game is in the background, once per NPC per scan. Pick the sound from the game's own alert sounds, or turn it off.
- **Targets and marks in one click.** While scanning, a small sonar badge sits on your screen. Its sweep turns while it searches. When your NPC is in range, the sweep stops, an orange contact lights up and the border turns green. Click it to target the NPC and place a real raid marker that your group can see. On clients with the ping system (Retail), it also pings it. You can bind it to a key.
- **Keeps your target in view.** While scanning, your target's nameplate stays at the edge of the screen when it's behind you or off to the side (on Classic clients, all nameplates do). Your own nameplate settings are put back when the scan stops.
- **Knows when you're done.** Once a found NPC dies, its name is dropped from the scan, and the scan stops when every name is done. Turn this off to keep finding more mobs with the same name. Corpses never trigger alerts.

The screen-edge, radar, waypoint and stop-when-dead behaviours are all options in the window, on by default.
- **Saved lists.** Save a set of NPCs with their markers and sounds ("Daily rares", "Profession trainers") and load it again with one click.
- **Remembers sightings.** NPC Sonar keeps where and when each name was last seen. Put a waypoint on the latest one, share it with your group or guild, or print the log.

## How to use

1. Type `/npcsonar` to open the window.
2. Enter the NPC's name (and **+ Add NPC** for more), pick markers and sounds if you like, and press **Start scan**. If you change the names later, press **Restart scan** to search for the new ones.
3. Keep moving. When the badge turns green, click it, or press your keybind.

## Commands

| Command | What it does |
|---|---|
| `/npcsonar` (or `/npcd`) | Open or close the window |
| `/npcsonar <name>` | Start scanning for a name right away |
| `/npcsonar stop` / `/npcsonar start` | Stop or resume the scan |
| `/npcsonar minimap` | Hide or show the minimap button |
| `/npcsonar save <list>` / `load <list>` / `delete <list>` | Save, load or delete a list of names |
| `/npcsonar lists` | Print your saved lists |
| `/npcsonar log` | Print where each name was last seen |
| `/npcsonar waypoint` | Put a map waypoint on the latest sighting |
| `/npcsonar share` | Post the latest sighting to your group, or guild if solo |
| `/npcsonar debug` | Print what the addon can see, for bug reports |

**Badge controls:** left-click targets and marks. Right-click opens the window. Right-drag moves the badge.
**Minimap button:** left-click opens the window, and right-click starts or stops the scan. Drag it around the minimap edge to move it. It works with minimap button collectors, and it's also listed in Blizzard's addons button where the game has one.
**Keybinding:** *Key Bindings → AddOns → NPC Sonar*.

## Good to know

- **Range:** NPC Sonar finds NPCs once they're within nameplate range (roughly 40–60 yards) or under your mouse. Rares and other NPCs with a minimap icon are found from much further away. It doesn't search the whole zone.
- **Waypoints:** a waypoint you placed yourself is never replaced automatically.
- **Nameplates:** turn on **enemy nameplates** (press V). For friendly quest NPCs, turn on friendly NPC nameplates too.
- **Raid groups:** placing a raid marker needs raid leader or assist. In a party or solo, anyone can mark.
- **Instances (Midnight):** Blizzard hides NPC names from addons inside instances, so automatic detection can't work there. Clicking the badge still finds and marks the NPC.
- **No automatic raid markers:** Blizzard only allows raid markers and pings from a click or keypress, so NPC Sonar marks automatically on your screen and leaves the real marker to your click.
- **The click clears your target first:** if the NPC isn't nearby, clicking the badge just leaves you with no target.
- **Combat:** Blizzard locks the badge during combat. If you start a scan or change the name or marker mid-fight, the badge appears or updates when combat ends.

## Supported versions

Retail and the Classic clients, from Classic Era through Mists of Pandaria Classic.

## Feedback

Bug reports and ideas are welcome. If something isn't being found, please include the output of `/npcsonar debug`, typed while the NPC is targeted.
