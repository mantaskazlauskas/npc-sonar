--------------------------------------------------------------------------------
-- NPC Sonar -- scanning and highlighting
--
-- The client gives addons no way to look up a unit by name, so the scan walks
-- every unit token that can point at an NPC -- target, mouseover, focus and
-- nameplate1..40 -- and compares names. In practice that means an NPC is found
-- once it is close enough to get a nameplate (~40-60 yd) or you mouse over it.
--
-- Marking: SetRaidTarget is protected (Classic) or restricted (Midnight), and
-- calling it from addon code raises the "blocked from an action" popup. So the
-- scan never marks anything itself. It draws the chosen icon over each match's
-- nameplate -- only you see it -- and the real raid marker is placed by the
-- secure button in MarkButton.lua, which runs on your click or keybind.
--
-- Since Midnight, names can come back as secret values (mostly inside
-- instances). Comparing a secret throws, so every read goes through Clean(),
-- and a unit whose name is unreadable simply never matches.
--------------------------------------------------------------------------------

local ADDON, ns = ...

local DEFAULTS = {
    icon    = 8,      -- skull
    partial = false,  -- substring match instead of whole-name match
    pinTarget = true, -- while scanning, hold the target's plate at the screen edge (Pin.lua)
    friendlyPlates = true, -- while scanning, show friendly NPC nameplates so they can be found (Pin.lua)
    doneOnDeath = true, -- stop looking for a name once an NPC found under it dies
    badge   = true,   -- show the sonar badge; its keybind works either way (MarkButton.lua)
    radar   = true,   -- detect matching rares on the minimap and point at them (Radar.lua)
    waypoint = true,  -- drop a map waypoint on rares the radar finds (Sightings.lua)
    sound   = "RAID_WARNING",  -- a SOUNDKIT key, or "NONE"
    pingSize = 1,     -- ripple ring size, a multiple of the default (ns.PING_SIZES)
    markerOffset = 0, -- nameplate marker's height above its default spot, in px (ns.MARKER_OFFSETS)
}

-- Steps offered in the window for the ripple size and the marker height. A
-- saved value outside its list is reset to the default at load.
ns.PING_SIZES = { 0.5, 0.75, 1, 1.25, 1.5, 2, 2.5 }
ns.MARKER_OFFSETS = { -20, -15, -10, -5, 0, 5, 10, 15, 20, 25, 30, 40, 50, 60 }

ns.ICON_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }

-- Name tags that pick a marker per name, as in chat: "Grimtooth {skull}".
local ICON_TAGS = {
    star = 1, circle = 2, coin = 2, diamond = 3, triangle = 4,
    moon = 5, square = 6, cross = 7, x = 7, skull = 8,
}
for i = 1, 8 do
    ICON_TAGS["rt" .. i] = i
    ICON_TAGS[tostring(i)] = i
end

-- Ping ring colour for each marker, used for names that carry a tag.
local ICON_COLORS = {
    { 1.00, 0.92, 0.30 },  -- star
    { 1.00, 0.55, 0.15 },  -- circle
    { 0.80, 0.35, 1.00 },  -- diamond
    { 0.35, 0.95, 0.35 },  -- triangle
    { 0.75, 0.85, 1.00 },  -- moon
    { 0.20, 0.35, 1.00 },  -- square (deeper than the default sonar blue)
    { 1.00, 0.25, 0.20 },  -- cross
    { 0.95, 0.95, 0.95 },  -- skull
}

-- Alert sounds, as SOUNDKIT keys. Which keys exist differs between retail and
-- the Classic clients, so the list the window offers is filtered at runtime
-- and a saved key the client lacks falls back to the default.
local SOUND_CHOICES = {
    { key = "NONE",                         label = "None" },
    { key = "RAID_WARNING",                 label = "Raid warning" },
    { key = "READY_CHECK",                  label = "Ready check" },
    { key = "ALARM_CLOCK_WARNING_3",        label = "Alarm clock" },
    { key = "UI_RAID_BOSS_WHISPER_WARNING", label = "Boss whisper" },
    { key = "IG_PLAYER_INVITE",             label = "Party invite" },
    { key = "TELL_MESSAGE",                 label = "Whisper" },
    { key = "UI_BNET_TOAST",                label = "Toast" },
    { key = "IG_QUEST_LIST_COMPLETE",       label = "Quest complete" },
    { key = "LEVELUPSOUND",                 label = "Level up" },
}

function ns.SoundChoices()
    local list = {}
    for _, s in ipairs(SOUND_CHOICES) do
        if s.key == "NONE" or (SOUNDKIT and SOUNDKIT[s.key]) then
            list[#list + 1] = s
        end
    end
    return list
end

function ns.PlayAlertSound(key)
    key = key or ns.db.sound
    local id = key ~= "NONE" and SOUNDKIT and SOUNDKIT[key]
    if id then PlaySound(id, "Master") end
end

local SCAN_INTERVAL  = 0.3
local ALERT_COOLDOWN = 3    -- seconds between alerts, so a pack of matches is one alert
local OVERLAY_SIZE   = 32

local issecretvalue = issecretvalue

local function Clean(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

ns.Clean = Clean

-- Target first so the status names the unit you are looking at.
local UNITS = { "target", "mouseover", "focus" }
local PLATE_UNITS = {}
for i = 1, 40 do
    UNITS[#UNITS + 1] = "nameplate" .. i
    PLATE_UNITS["nameplate" .. i] = true
end

ns.scanning = false
local wanted = {}
local wantedIcon = {}    -- wanted entry -> marker from its {tag}; absent = the default marker
local ticker
local alerted = {}       -- GUID -> wanted entry it matched, for NPCs announced this scan
local lastAlertAt = -math.huge

--------------------------------------------------------------------------------

function ns.IconPath(i)
    return "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i
end

function ns.IconString(i, size)
    return ("|T%s:%d|t"):format(ns.IconPath(i), size or 0)
end

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffNPC Sonar:|r " .. msg)
end

-- Other files replace these; the stubs keep Core usable if one fails to load.
function ns.SetStatus(_) end
function ns.Refresh() end
function ns.UpdateMarkButton() end
function ns.UpdateIndicator() end
function ns.SetupLaunchers() end
function ns.RadarScan() end
function ns.RadarTick() end
function ns.NoteUnit(_unit) end
function ns.ResetRadar() end
function ns.RadarStatus() return nil end
function ns.RecordSighting(_name, _want, _guid) end
function ns.ToggleMinimapButton() end
function ns.ToggleBadge() end
function ns.ClickHint() return "Click the |cffffd100sonar badge|r (or your keybind)" end
function ns.QuestMatch(_unit) return nil end
function ns.HasQuests() return false end
function ns.IsQuestWant(_want) return false end
function ns.QuestNames() return {} end
function ns.QuestTitlesText() return "" end
function ns.LearnQuestName(_name, _want) return false end
function ns.ResetQuests() end
function ns.QuestDebug(_unit) end
function ns.ClearQuests() end
function ns.ToggleQuest(_id) ns.Print("Quest scanning isn't available.") end
function ns.QuestTitle(id) return "quest " .. tostring(id) end
function ns.AddQuestTrackingLines(_tooltip, _onlyID) end
function ns.QuestPassDone() end

ns.found = false  -- a match is in range right now; drives the badge colour

--------------------------------------------------------------------------------
-- What to look for. NpcSonarDB.npcs is a list of rows, one per NPC, as the
-- window shows them: { name = "Grimtooth", icon = 8, sound = "READY_CHECK" }.
-- icon and sound are optional; without them the row uses the default marker
-- and sound. A {tag} typed in a name ("Grimtooth {skull}", as in chat) also
-- picks the marker, so typed lists and /npcsonar keep working.
--
-- Rows are read into `wanted` when a scan starts: lowercase names, tags
-- removed, no duplicates, with each name's marker and sound alongside.

-- A typed name without its {tag}, and the marker the tag picked. An unknown
-- tag is left in the name, which then simply never matches.
local function ParsePart(text)
    local icon
    text = (text or ""):gsub("{(%w+)}", function(tag)
        local i = ICON_TAGS[tag:lower()]
        if not i then return nil end  -- keep the text as typed
        icon = i
        return ""
    end)
    return strtrim(text), icon
end

-- The window has room for this many rows, so text is cut to it too.
ns.MAX_NPCS = 8

-- Rows from comma-separated text ("Grimtooth {skull}, Shade of Ashar"), at
-- most MAX_NPCS of them. Names past that are printed rather than kept in rows
-- the window couldn't show.
function ns.ParseRows(text)
    local rows, dropped = {}, {}
    for part in (text or ""):gmatch("[^,;]+") do
        local name, icon = ParsePart(part)
        if name ~= "" then
            if #rows < ns.MAX_NPCS then
                rows[#rows + 1] = { name = name, icon = icon }
            else
                dropped[#dropped + 1] = name
            end
        end
    end
    if #dropped > 0 then
        ns.Print(("Up to %d NPCs at a time; left out: %s"):format(ns.MAX_NPCS, table.concat(dropped, ", ")))
    end
    return rows
end

function ns.CopyRows(rows)
    local copy = {}
    for i, r in ipairs(rows or {}) do
        copy[i] = { name = r.name, icon = r.icon, sound = r.sound }
    end
    return copy
end

-- The rows that name something.
local function FilledRows(rows)
    local out = {}
    for _, r in ipairs(rows or {}) do
        if strtrim(r.name or "") ~= "" then out[#out + 1] = r end
    end
    return out
end

-- "Grimtooth, Shade of Ashar", for tooltips and chat. Without `rows` it is
-- what a scan looks for: the window's rows plus tracked quests (Quests.lua).
function ns.NamesText(rows)
    local names = {}
    for _, r in ipairs(FilledRows(rows or ns.db.npcs)) do
        names[#names + 1] = (ParsePart(r.name))
    end
    if not rows then
        local quests = ns.QuestTitlesText()
        if quests ~= "" then names[#names + 1] = quests end
    end
    return table.concat(names, ", ")
end

-- A string that is equal for two row lists exactly when they look for the
-- same names with the same markers and sounds; used to tell whether the
-- window still holds a saved list unchanged.
function ns.RowsKey(rows)
    local parts = {}
    for _, r in ipairs(FilledRows(rows)) do
        parts[#parts + 1] = ("%s|%s|%s"):format(strtrim(r.name):lower(), r.icon or "", r.sound or "")
    end
    return table.concat(parts, ";")
end

-- Fills wanted, wantedIcon and wantedSound from the rows. A repeat of a name
-- may carry the marker or sound the first copy lacked.
local wantedSound = {}
local function ReadRows(rows)
    local list, icons, sounds = {}, {}, {}
    for _, r in ipairs(rows or {}) do
        local name, tagIcon = ParsePart(r.name)
        name = name:lower()
        if name ~= "" then
            if not tContains(list, name) then list[#list + 1] = name end
            icons[name] = icons[name] or r.icon or tagIcon
            sounds[name] = sounds[name] or r.sound
        end
    end
    return list, icons, sounds
end

function ns.WantedNames()
    return wanted
end

-- The names the badge macro targets: the wanted names, then names found for
-- tracked quests (Quests.lua).
function ns.MacroNames()
    local names = {}
    for _, n in ipairs(wanted) do names[#names + 1] = n end
    for _, n in ipairs(ns.QuestNames()) do
        if not tContains(names, n:lower()) then names[#names + 1] = n end
    end
    return names
end

-- The marker for a wanted entry: its own, else the chosen default.
function ns.IconFor(want)
    return wantedIcon[want] or ns.db.icon
end

-- The alert sound for a wanted entry: its own, else the chosen default.
function ns.SoundFor(want)
    return wantedSound[want] or ns.db.sound
end

-- True when any name carries its own marker.
function ns.HasNameIcons()
    return next(wantedIcon) ~= nil
end

-- The wanted entry a display name matches, or nil.
local function WantedFor(name)
    local lower = name:lower()
    for _, want in ipairs(wanted) do
        if lower == want or (ns.db.partial and lower:find(want, 1, true)) then
            return want
        end
    end
    return nil
end
ns.WantedFor = WantedFor

-- Returns the unit's display name when it is a living NPC we are looking for,
-- and the wanted entry it matched. The second return is true instead when the
-- unit's name is secret: it might be a match, but the client won't let us
-- look (Midnight, inside instances).
local function Match(unit)
    if not Clean(UnitExists(unit)) then return nil end
    -- Unreadable answers fall through: better to consider a unit than to go
    -- blind wherever the client restricts these.
    if Clean(UnitIsPlayer(unit)) then return nil end
    if Clean(UnitIsDead(unit)) then return nil end

    local raw = UnitName(unit)
    if IsSecret(raw) then return nil, true end
    local name = raw
    if type(name) ~= "string" then return nil end

    local want = WantedFor(name) or ns.QuestMatch(unit)
    if want then return name, want end
    return nil
end

--------------------------------------------------------------------------------
-- Nameplate overlays. One per plate frame, reused as plates are recycled; the
-- overlay is a child of the plate so it moves, scales and hides with it.
--
-- Behind the icon, sonar rings expand and fade on a loop. Each ring has its
-- own looping group with the same period (duration + end delay), and ring i
-- is started (i-1)/PING_RINGS of a period after the first, so the pings are
-- evenly spaced and may overlap. The stagger is a timer rather than a start
-- delay: a start delay counts on every loop, and pushing a late ring's delay
-- past the period would need a negative end delay. The ring's base alpha is
-- 0, so it is invisible while stopped or waiting out its end delay.

local MARKER_GAP    = 2                     -- px between plate top and marker at height 0
local PING_TEXTURE  = "Interface\\AddOns\\NpcSonar\\Media\\ping_ring"
local PING_COLOR    = { 0.25, 0.70, 0.95 }  -- the badge's sonar blue
local PING_RINGS    = 2
local PING_DURATION = 1.2                   -- one ring's expand-and-fade
local PING_PERIOD   = 1.6                   -- time between pings of one ring
local PING_SCALE    = { 0.6, 2.4 }          -- relative to the ring's size: OVERLAY_SIZE * db.pingSize

assert(PING_PERIOD >= PING_DURATION, "PING_PERIOD must cover PING_DURATION")

-- Colour for a wanted entry's rings and radar arrow: its marker's colour when
-- the name has a {tag}, else the sonar blue.
function ns.ColorFor(want)
    return ICON_COLORS[wantedIcon[want]] or PING_COLOR
end

local overlays = {}

local function AddPingRing(o)
    local ring = o:CreateTexture(nil, "BACKGROUND")
    ring:SetTexture(PING_TEXTURE)
    ring:SetBlendMode("ADD")
    ring:SetVertexColor(PING_COLOR[1], PING_COLOR[2], PING_COLOR[3])
    ring:SetPoint("CENTER")
    ring:SetSize(OVERLAY_SIZE, OVERLAY_SIZE)
    ring:SetAlpha(0)

    local ag = ring:CreateAnimationGroup()
    ag:SetLooping("REPEAT")

    local scale = ag:CreateAnimation("Scale")
    scale:SetScaleFrom(PING_SCALE[1], PING_SCALE[1])
    scale:SetScaleTo(PING_SCALE[2], PING_SCALE[2])
    scale:SetSmoothing("OUT")

    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.9)
    fade:SetToAlpha(0)

    for _, anim in ipairs({ scale, fade }) do
        anim:SetDuration(PING_DURATION)
        anim:SetEndDelay(PING_PERIOD - PING_DURATION)
    end
    return ag
end

-- Stops every ring and starts them again in phase. The token makes timers
-- left over from an earlier start do nothing if they fire after a restart.
local function StartPings(o)
    o.pingToken = (o.pingToken or 0) + 1
    local token = o.pingToken
    for i, ag in ipairs(o.pings) do
        ag:Stop()
        local delay = (i - 1) * PING_PERIOD / PING_RINGS
        if delay == 0 then
            ag:Play()
        else
            C_Timer.After(delay, function()
                if o.pingToken == token then ag:Play() end
            end)
        end
    end
end

-- `want` is the wanted entry the unit matched: it picks the marker, and a
-- name with its own {tag} gets rings in that marker's colour so several
-- matches stay apart. Untagged names keep the sonar blue.
local function ShowOverlay(unit, want)
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or not plate then return end

    local o = overlays[plate]
    if not o then
        -- A forbidden plate (friendly plates inside Midnight instances) refuses
        -- children; skip it rather than error.
        local created
        created, o = pcall(CreateFrame, "Frame", nil, plate)
        if not created then return end
        o:SetSize(OVERLAY_SIZE, OVERLAY_SIZE)
        o.tex = o:CreateTexture(nil, "OVERLAY")
        o.tex:SetAllPoints()
        o.pings = {}
        for i = 1, PING_RINGS do
            o.pings[i] = AddPingRing(o)
        end
        overlays[plate] = o
    end
    -- Re-anchored only when the marker height setting changed. The offset is
    -- in the plate's own scale, so it shrinks and grows with the plate.
    local offset = ns.db.markerOffset or 0
    if o.offset ~= offset then
        o:ClearAllPoints()
        o:SetPoint("BOTTOM", plate, "TOP", 0, MARKER_GAP + offset)
        o.offset = offset
    end
    o.tex:SetTexture(ns.IconPath(ns.IconFor(want)))
    local color = ns.ColorFor(want)
    -- The Scale animation is relative to the texture's size, so resizing the
    -- ring scales the whole ripple, start and end alike, without rebuilding
    -- the animation. Done on every show so a change in the window is picked
    -- up on the next scan tick.
    local ringSize = OVERLAY_SIZE * (ns.db.pingSize or 1)
    for _, ag in ipairs(o.pings) do
        local ring = ag:GetParent()
        ring:SetVertexColor(color[1], color[2], color[3])
        ring:SetSize(ringSize, ringSize)
    end
    o:Show()
    -- The first ring is played at once on every start, so if it isn't
    -- playing the set was never started or has been stopped.
    if not o.pings[1]:IsPlaying() then StartPings(o) end
    o.used = true
end

local function HideOverlays(onlyUnused)
    for _, o in pairs(overlays) do
        if not (onlyUnused and o.used) then o:Hide() end
        o.used = false
    end
end

--------------------------------------------------------------------------------

-- Prints msg, shows it as a raid warning, plays `sound` (a SOUNDKIT key, or
-- the default) and flashes the taskbar. Returns false without doing anything
-- inside the cooldown, so a pack of matches is one alert. Shared with the
-- radar.
function ns.Announce(msg, sound)
    local now = GetTime()
    if now - lastAlertAt < ALERT_COOLDOWN then return false end
    lastAlertAt = now

    ns.Print(msg)
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
    end
    ns.PlayAlertSound(sound)
    -- Flashes the taskbar entry; the client does nothing when the game
    -- window already has focus.
    if FlashClientIcon then FlashClientIcon() end
    return true
end

-- A quest usually needs a pack of NPCs, so it is announced once per scan, for
-- the first one found; the rest are only marked. Each name found for it is
-- added to the badge macro.
local alertedQuest = {}
local function AlertQuest(name, want)
    if ns.LearnQuestName(name, want) then ns.UpdateMarkButton() end
    if alertedQuest[want] then return end
    local id = tonumber(want:match("%d+"))
    if ns.Announce(("Found %s %s for |cffffd100%s|r"):format(
            ns.IconString(ns.IconFor(want)), name, ns.QuestTitle(id)), ns.SoundFor(want)) then
        alertedQuest[want] = true
    end
end

-- Lets a quest tracked again during the same scan be announced again.
function ns.ForgetQuestAlert(want)
    if want then alertedQuest[want] = nil else wipe(alertedQuest) end
end

local function Alert(unit, name, want)
    if ns.IsQuestWant(want) then return AlertQuest(name, want) end
    local guid = Clean(UnitGUID(unit))
    if guid and alerted[guid] then return end
    if not ns.Announce(("Found %s %s"):format(ns.IconString(ns.IconFor(want)), name),
            ns.SoundFor(want)) then
        return
    end
    if guid then alerted[guid] = want end
    ns.RecordSighting(name, want, nil)
end

-- An NPC we announced is now dead (you usually still have it targeted, or
-- its corpse is under the mouse). Its name is done: drop it from this scan,
-- and stop when nothing is left. ns.db.npcs is untouched, so the next Start
-- looks for everything again.
local function CheckDeath(unit)
    local guid = Clean(UnitGUID(unit))
    local want = guid and alerted[guid]
    if not want or not Clean(UnitIsDead(unit)) then return false end
    -- Forget every NPC found under this name, so a second corpse of the same
    -- name can't announce it again.
    for g, w in pairs(alerted) do
        if w == want then alerted[g] = nil end
    end
    local removed = false
    for i, w in ipairs(wanted) do
        if w == want then table.remove(wanted, i); removed = true; break end
    end
    if not removed then return false end
    wantedIcon[want] = nil
    wantedSound[want] = nil
    local name = Clean(UnitName(unit))
    name = type(name) == "string" and name or want
    if #wanted == 0 and not ns.HasQuests() then
        ns.Print(("%s is dead. Nothing left to look for, scan stopped."):format(name))
        ns.Stop()
        return true
    end
    if #wanted == 0 then
        ns.Print(("%s is dead. Still looking for quest NPCs."):format(name))
    else
        ns.Print(("%s is dead. Still looking for: %s"):format(name, table.concat(wanted, ", ")))
    end
    ns.UpdateMarkButton()
    ns.RadarScan()
    return false
end

local function Scan()
    if not ns.scanning then return end
    local firstName, firstWant, sawHidden

    for _, unit in ipairs(UNITS) do
        if ns.db.doneOnDeath and next(alerted) and CheckDeath(unit) then return end
        local name, want = Match(unit)
        if name then
            if not firstName then firstName, firstWant = name, want end
            if PLATE_UNITS[unit] then ShowOverlay(unit, want) end
            -- Level and model info is kept for named rares; quest packs would
            -- only fill the saved variables.
            if not ns.IsQuestWant(want) then ns.NoteUnit(unit) end
            Alert(unit, name, want)
        elseif want then
            sawHidden = true
        end
    end
    HideOverlays(true)
    ns.QuestPassDone()
    ns.RadarTick()

    local found = firstName ~= nil
    if found ~= ns.found then
        ns.found = found
        ns.UpdateIndicator()
    end

    if firstName then
        ns.SetStatus(("|cff00ff00Found:|r %s %s\n%s to target it and set a raid marker.")
            :format(ns.IconString(ns.IconFor(firstWant)), firstName, ns.ClickHint()))
    elseif sawHidden then
        -- The secure macro runs in Blizzard code, which can still read names,
        -- so the button keeps working where the scan has gone blind.
        ns.SetStatus("|cffff8000NPC names are hidden from addons here,|r so no auto-detect. "
            .. ns.ClickHint() .. " to find and mark the NPC anyway.")
    else
        ns.SetStatus(ns.RadarStatus() or "Searching...")
    end
end

--------------------------------------------------------------------------------
-- /npcsonar debug: what the client is showing us, for reports from places we
-- can't test (instances, other client flavours).

local function Show(v)
    if v == nil then return "|cff888888nil|r" end
    if IsSecret(v) then return "|cffff8000SECRET|r" end
    return "|cff00ff00" .. tostring(v) .. "|r"
end

function ns.Debug()
    local _, build, _, toc = GetBuildInfo()
    local inInstance, instanceType = IsInInstance()
    ns.Print(("client %s (toc %s), instance=%s %s, secret values=%s"):format(
        tostring(build), tostring(toc), tostring(inInstance), tostring(instanceType or ""),
        tostring(issecretvalue ~= nil)))
    ns.Print(("ping system: %s"):format(
        (C_Ping and C_Ping.IsPingSystemEnabled) and Show(C_Ping.IsPingSystemEnabled()) or "|cffff4040not in this client|r"))

    local any = false
    for _, unit in ipairs(UNITS) do
        if Clean(UnitExists(unit)) then
            local isPlate = PLATE_UNITS[unit]
            -- Plates are summarised only when they matter; target/mouseover always.
            local name, hidden = Match(unit)
            if not isPlate or name or hidden then
                any = true
                local plate = "-"
                if isPlate then
                    local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, unit)
                    plate = not ok and "|cffff4040error|r" or p and "yes" or "|cffff4040no|r"
                end
                ns.Print(("%s: name=%s player=%s dead=%s match=%s%s"):format(
                    unit, Show(UnitName(unit)), Show(UnitIsPlayer(unit)), Show(UnitIsDead(unit)),
                    name and "|cff00ff00yes|r" or hidden and "|cffff8000unknown|r" or "no",
                    isPlate and (" plate=" .. plate) or ""))
            end
        end
    end
    if not any then ns.Print("No target, mouseover or relevant nameplates. Target the NPC and run it again.") end
    if Clean(UnitExists("target")) and not Clean(UnitIsPlayer("target")) then ns.QuestDebug("target") end
end

-- Enemy plates are the player's call (V toggles them), so they only get a
-- warning. Friendly NPC plates are switched on for the scan when that option
-- is on (Pin.lua); with it off, the player is told what they miss.
local function WarnIfPlatesOff()
    if not (C_CVar and C_CVar.GetCVarBool) then return end
    if not C_CVar.GetCVarBool("nameplateShowEnemies") then
        ns.Print("Enemy nameplates are off (toggle with V), so enemies are only found as your target or under the mouse.")
    end
    if not ns.db.friendlyPlates and C_CVar.GetCVar("nameplateShowFriendlyNPCs") == "0" then
        ns.Print("Friendly NPC nameplates are off, so friendly NPCs are only found as your target or under the mouse. "
            .. "Turn on \"Show friendly NPC nameplates while scanning\" to fix that.")
    end
end

--------------------------------------------------------------------------------

-- `text` (from /npcsonar <names>) replaces the rows; without it the rows in
-- the window are used.
function ns.Start(text)
    if text then ns.db.npcs = ns.ParseRows(text) end
    wanted, wantedIcon, wantedSound = ReadRows(ns.db.npcs)
    ns.ResetQuests()
    wipe(alertedQuest)
    if #wanted == 0 and not ns.HasQuests() then
        ns.Print("Enter an NPC name first.")
        ns.SetStatus("Enter an NPC name first.")
        return false
    end

    ns.scanning = true
    wipe(alerted)
    lastAlertAt = -math.huge
    HideOverlays(false)
    if not ticker then ticker = C_Timer.NewTicker(SCAN_INTERVAL, Scan) end
    ns.UpdatePinning()
    ns.ResetRadar()
    WarnIfPlatesOff()
    ns.SetStatus("Searching...")
    ns.Refresh()
    ns.UpdateMarkButton()
    ns.found = false
    ns.UpdateIndicator()
    Scan()
    return true
end

function ns.Stop()
    ns.scanning = false
    if ticker then ticker:Cancel(); ticker = nil end
    ns.UpdatePinning()
    ns.RadarScan()  -- hides the arrow now that nothing is scanning
    HideOverlays(false)
    ns.SetStatus("Stopped.")
    ns.Refresh()
    ns.UpdateMarkButton()
    ns.found = false
    ns.UpdateIndicator()
end

-- Called when the marker choice changes so visible overlays follow at once.
function ns.Rescan()
    Scan()
    ns.UpdateMarkButton()
end

-- Called when a row's marker or sound changes in the window. A running scan
-- takes the new choice at once; the names it looks for stay as they were
-- until the next Start (so names already found dead stay dropped).
function ns.RowsChanged()
    if not ns.scanning then return end
    local _, icons, sounds = ReadRows(ns.db.npcs)
    wipe(wantedIcon)
    wipe(wantedSound)
    for _, want in ipairs(wanted) do
        wantedIcon[want] = icons[want]
        wantedSound[want] = sounds[want]
    end
    ns.Rescan()
end

-- A sound key saved on a client that has it, loaded on one that doesn't.
local function KnownSound(key)
    return key == nil or key == "NONE" or (SOUNDKIT and SOUNDKIT[key]) ~= nil
end

-- 0.2.0 kept the names as one comma-separated text (NpcSonarDB.names), and
-- saved lists as such texts. Both become rows; sounds the client lacks fall
-- back to the default.
local function MigrateRows(db)
    if db.npcs == nil then db.npcs = ns.ParseRows(db.names) end
    db.names = nil
    for name, list in pairs(db.lists or {}) do
        if type(list) == "string" then db.lists[name] = ns.ParseRows(list) end
    end
    local function Check(rows)
        for _, r in ipairs(rows) do
            if not KnownSound(r.sound) then r.sound = nil end
        end
    end
    Check(db.npcs)
    for _, list in pairs(db.lists or {}) do Check(list) end
end

--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        NpcSonarDB = NpcSonarDB or {}
        -- `sound` used to be an on/off flag.
        if NpcSonarDB.sound == true then NpcSonarDB.sound = nil end
        if NpcSonarDB.sound == false then NpcSonarDB.sound = "NONE" end
        if NpcSonarDB.sound ~= nil and NpcSonarDB.sound ~= "NONE"
            and not (SOUNDKIT and SOUNDKIT[NpcSonarDB.sound]) then
            NpcSonarDB.sound = nil -- saved on a client that had this sound; this one doesn't
        end
        if NpcSonarDB.pingSize ~= nil and not tContains(ns.PING_SIZES, NpcSonarDB.pingSize) then
            NpcSonarDB.pingSize = nil
        end
        if NpcSonarDB.markerOffset ~= nil and not tContains(ns.MARKER_OFFSETS, NpcSonarDB.markerOffset) then
            NpcSonarDB.markerOffset = nil
        end
        for k, v in pairs(DEFAULTS) do
            if NpcSonarDB[k] == nil then NpcSonarDB[k] = v end
        end
        MigrateRows(NpcSonarDB)
        ns.db = NpcSonarDB
        self:UnregisterEvent("ADDON_LOADED")
        -- React the moment a candidate appears instead of waiting for a tick.
        self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        self:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
        self:RegisterEvent("PLAYER_TARGET_CHANGED")
        ns.SetupLaunchers()
        return
    end
    Scan()
end)

SLASH_NPCSONAR1 = "/npcsonar"
SLASH_NPCSONAR2 = "/npcd"
SlashCmdList.NPCSONAR = function(msg)
    msg = strtrim(msg or "")
    local cmd = msg:lower()
    -- "save", "load" and "delete" take the rest of the line as a list name;
    -- without one they print the usage instead of starting a scan for an
    -- NPC called "save".
    local verb, rest = msg:match("^(%S+)%s*(.-)$")
    verb = verb and verb:lower()
    if (verb == "save" or verb == "load" or verb == "delete") and rest == "" then
        ns.Print(("Usage: /npcsonar %s <list name>"):format(verb))
        return
    end
    if verb == "save" then
        ns.SaveList(rest)
    elseif verb == "load" then
        ns.LoadList(rest)
    elseif verb == "delete" then
        ns.DeleteList(rest)
    elseif cmd == "lists" then
        ns.PrintLists()
    elseif cmd == "log" then
        ns.PrintSightings()
    elseif cmd == "share" then
        ns.ShareLatest()
    elseif cmd == "waypoint" then
        ns.WaypointLatest()
    elseif cmd == "" then
        ns.ToggleWindow()
    elseif cmd == "stop" then
        ns.Stop()
    elseif cmd == "start" then
        ns.Start()
    elseif cmd == "minimap" then
        ns.ToggleMinimapButton()
    elseif cmd == "badge" then
        ns.ToggleBadge()
    elseif cmd == "debug" then
        ns.Debug()
    elseif cmd == "quest clear" then
        ns.ClearQuests()
    elseif verb == "quest" then
        if tonumber(rest) then
            ns.ToggleQuest(tonumber(rest))
        else
            ns.Print("Usage: /npcsonar quest <questID>, or /npcsonar quest clear")
        end
    else
        ns.Start(msg)
    end
end
