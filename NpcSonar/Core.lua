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
    names   = "",
    icon    = 8,      -- skull
    partial = false,  -- substring match instead of whole-name match
    pinTarget = true, -- while scanning, hold the target's plate at the screen edge (Pin.lua)
    doneOnDeath = true, -- stop looking for a name once an NPC found under it dies
    radar   = true,   -- detect matching rares on the minimap and point at them (Radar.lua)
    sound   = "RAID_WARNING",  -- a SOUNDKIT key, or "NONE"
}

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
function ns.ResetRadar() end
function ns.RadarStatus() return nil end
function ns.ToggleMinimapButton() end

ns.found = false  -- a match is in range right now; drives the badge colour

-- Returns the wanted names (lowercase, tags removed, no duplicates) and a
-- table of name -> marker for the names that carry a {tag}. An unknown tag
-- is left in the name, which then simply never matches.
local function ParseNames(text)
    local list, icons = {}, {}
    for part in (text or ""):gmatch("[^,;]+") do
        local icon
        part = part:gsub("{(%w+)}", function(tag)
            local i = ICON_TAGS[tag:lower()]
            if not i then return nil end  -- keep the text as typed
            icon = i
            return ""
        end)
        part = strtrim(part):lower()
        if part ~= "" then
            if not tContains(list, part) then list[#list + 1] = part end
            -- A repeat may carry the tag the first copy lacked.
            icons[part] = icons[part] or icon
        end
    end
    return list, icons
end

function ns.WantedNames()
    return wanted
end

-- The marker for a wanted entry: its own tag, else the chosen default.
function ns.IconFor(want)
    return wantedIcon[want] or ns.db.icon
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

    local want = WantedFor(name)
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

local PING_TEXTURE  = "Interface\\AddOns\\NpcSonar\\Media\\ping_ring"
local PING_COLOR    = { 0.25, 0.70, 0.95 }  -- the badge's sonar blue
local PING_RINGS    = 2
local PING_DURATION = 1.2                   -- one ring's expand-and-fade
local PING_PERIOD   = 1.6                   -- time between pings of one ring
local PING_SCALE    = { 0.6, 2.4 }          -- relative to OVERLAY_SIZE

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
        o:SetPoint("BOTTOM", plate, "TOP", 0, 2)
        o.tex = o:CreateTexture(nil, "OVERLAY")
        o.tex:SetAllPoints()
        o.pings = {}
        for i = 1, PING_RINGS do
            o.pings[i] = AddPingRing(o)
        end
        overlays[plate] = o
    end
    o.tex:SetTexture(ns.IconPath(ns.IconFor(want)))
    local color = ns.ColorFor(want)
    for _, ag in ipairs(o.pings) do
        ag:GetParent():SetVertexColor(color[1], color[2], color[3])
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

-- Prints msg, shows it as a raid warning, plays the alert sound and flashes
-- the taskbar. Returns false without doing anything inside the cooldown, so
-- a pack of matches is one alert. Shared with the radar.
function ns.Announce(msg)
    local now = GetTime()
    if now - lastAlertAt < ALERT_COOLDOWN then return false end
    lastAlertAt = now

    ns.Print(msg)
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
    end
    ns.PlayAlertSound()
    -- Flashes the taskbar entry; the client does nothing when the game
    -- window already has focus.
    if FlashClientIcon then FlashClientIcon() end
    return true
end

local function Alert(unit, name, want)
    local guid = Clean(UnitGUID(unit))
    if guid and alerted[guid] then return end
    if not ns.Announce(("Found %s %s"):format(ns.IconString(ns.IconFor(want)), name)) then return end
    if guid then alerted[guid] = want end
end

-- An NPC we announced is now dead (you usually still have it targeted, or
-- its corpse is under the mouse). Its name is done: drop it from this scan,
-- and stop when nothing is left. ns.db.names is untouched, so the next Start
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
    local name = Clean(UnitName(unit))
    name = type(name) == "string" and name or want
    if #wanted == 0 then
        ns.Print(("%s is dead. Nothing left to look for, scan stopped."):format(name))
        ns.Stop()
        return true
    end
    ns.Print(("%s is dead. Still looking for: %s"):format(name, table.concat(wanted, ", ")))
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
            Alert(unit, name, want)
        elseif want then
            sawHidden = true
        end
    end
    HideOverlays(true)
    ns.RadarTick()

    local found = firstName ~= nil
    if found ~= ns.found then
        ns.found = found
        ns.UpdateIndicator()
    end

    if firstName then
        ns.SetStatus(("|cff00ff00Found:|r %s %s\nClick the |cffffd100sonar badge|r (or your keybind) to target it and set a raid marker.")
            :format(ns.IconString(ns.IconFor(firstWant)), firstName))
    elseif sawHidden then
        -- The secure macro runs in Blizzard code, which can still read names,
        -- so the button keeps working where the scan has gone blind.
        ns.SetStatus("|cffff8000NPC names are hidden from addons here,|r so no auto-detect. "
            .. "Clicking the |cffffd100sonar badge|r still finds and marks the NPC.")
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
end

local function WarnIfPlatesOff()
    if C_CVar and C_CVar.GetCVarBool and not C_CVar.GetCVarBool("nameplateShowEnemies") then
        ns.Print("Enemy nameplates are off (toggle with V), so only your target and mouseover can be scanned.")
    end
end

--------------------------------------------------------------------------------

function ns.Start(text)
    if text then ns.db.names = text end
    wanted, wantedIcon = ParseNames(ns.db.names)
    if #wanted == 0 then
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
        for k, v in pairs(DEFAULTS) do
            if NpcSonarDB[k] == nil then NpcSonarDB[k] = v end
        end
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
    if cmd == "" then
        ns.ToggleWindow()
    elseif cmd == "stop" then
        ns.Stop()
    elseif cmd == "start" then
        ns.Start()
    elseif cmd == "minimap" then
        ns.ToggleMinimapButton()
    elseif cmd == "debug" then
        ns.Debug()
    else
        ns.Start(msg)
    end
end
