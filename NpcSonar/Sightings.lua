--------------------------------------------------------------------------------
-- NPC Sonar -- sightings: where each name was last seen, waypoints, sharing
--
-- Every announced find is logged per wanted name in NpcSonarDB.sightings:
-- the NPC's display name, when, and where. A radar (vignette) find stores
-- the NPC's own map position; a nameplate find is within ~60 yd, so it
-- stores the player's position. Inside instances there is no position, and
-- only the zone name is kept.
--
-- A radar find also drops a map waypoint on the NPC (when the option is on
-- and the map allows one), since it may be far away. The window's Waypoint
-- button does the same for the latest sighting, Share posts it to group or
-- guild chat, and Log prints them all (/npcsonar log).
--------------------------------------------------------------------------------

local _, ns = ...

local function Sightings()
    ns.db.sightings = ns.db.sightings or {}
    return ns.db.sightings
end

local function PlayerPosition()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if pos then return mapID, pos.x, pos.y end
    return nil
end

local function MapName(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    return info and info.name
end

local function Where(s)
    local zone = MapName(s.mapID) or s.zone or "unknown place"
    if s.x then
        return ("%s (%.1f, %.1f)"):format(zone, s.x * 100, s.y * 100)
    end
    return zone
end

local function Ago(t)
    local d = time() - t
    if d < 60 then return "just now" end
    if d < 3600 then return ("%d min ago"):format(d / 60) end
    if d < 86400 then return ("%d h ago"):format(d / 3600) end
    return ("%d days ago"):format(d / 86400)
end

local ourWaypoint      -- the last point we placed, to tell it from the player's own
local waypointed = {}  -- vignette GUIDs that already got an automatic waypoint

local function IsOurs(point)
    return ourWaypoint and point and point.uiMapID == ourWaypoint.mapID
        and math.abs(point.position.x - ourWaypoint.x) < 1e-4
        and math.abs(point.position.y - ourWaypoint.y) < 1e-4
end

-- `auto` is for radar finds: it never replaces a waypoint the player set
-- themselves, and it doesn't take super-tracking (the in-world arrow) away
-- from a quest. The Waypoint button does both, since the player asked.
local function SetWaypoint(s, auto)
    local function Fail(msg)
        if not auto then ns.Print(msg) end
        return false
    end
    if not (s and s.x and C_Map.SetUserWaypoint) then
        return Fail("No map position for that sighting.")
    end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(s.mapID) then
        return Fail("Waypoints can't be placed on this map.")
    end
    if auto and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()
        and not IsOurs(C_Map.GetUserWaypoint()) then
        return false
    end
    local point = UiMapPoint and UiMapPoint.CreateFromCoordinates(s.mapID, s.x, s.y)
        or { uiMapID = s.mapID, position = CreateVector2D(s.x, s.y) }
    local ok, wasSet = pcall(C_Map.SetUserWaypoint, point)
    if not (ok and wasSet ~= false) then
        return Fail("Couldn't place a waypoint there.")
    end
    ourWaypoint = { mapID = s.mapID, x = s.x, y = s.y }
    -- Retail also shows the pin in the world and on the edge of the screen.
    if not auto and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    return true
end

-- Called by Core and Radar after a find is announced. `guid` is the
-- vignette's for radar finds, nil for nameplate finds.
function ns.RecordSighting(name, want, guid)
    local now = time()
    local s = { name = name, time = now, zone = GetRealZoneText() }
    if guid then
        s.mapID, s.x, s.y = ns.VignettePosition(guid)
    else
        -- A radar sighting of the same NPC moments ago has its exact
        -- position; the player's position (up to ~60 yd off) is worse.
        local prev = Sightings()[want]
        if prev and prev.precise and prev.name == name and now - prev.time < 60 then
            prev.time = now
            return
        end
        s.mapID, s.x, s.y = PlayerPosition()
    end
    s.precise = guid ~= nil and s.x ~= nil
    Sightings()[want] = s
    if guid and ns.db.waypoint and not waypointed[guid] and SetWaypoint(s, true) then
        waypointed[guid] = true
        ns.Print(("Waypoint set on %s."):format(name))
    end
end

-- The most recent sighting of anything.
local function Latest()
    local best
    for _, s in pairs(Sightings()) do
        if not best or s.time > best.time then best = s end
    end
    return best
end

function ns.WaypointLatest()
    local s = Latest()
    if not s then
        ns.Print("Nothing sighted yet.")
        return
    end
    if SetWaypoint(s) then ns.Print(("Waypoint set on %s, %s."):format(s.name, Where(s))) end
end

function ns.ShareLatest()
    local s = Latest()
    if not s then
        ns.Print("Nothing sighted yet.")
        return
    end
    local channel
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        channel = "INSTANCE_CHAT"
    elseif IsInRaid() then
        channel = "RAID"
    elseif IsInGroup() then
        channel = "PARTY"
    elseif IsInGuild() then
        channel = "GUILD"
    else
        ns.Print("Not in a group or guild, so there's no one to share with.")
        return
    end
    -- During encounters, Mythic+ and PvP matches (Midnight) addon chat is
    -- dropped silently, so check first rather than trusting the send.
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        ns.Print("Chat is locked right now (encounter or match), so it can't be shared.")
        return
    end
    local msg = ("NPC Sonar: %s seen at %s, %s."):format(s.name, Where(s), Ago(s.time))
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not pcall(send, msg, channel) then
        ns.Print("The game didn't allow that message here.")
    end
end

function ns.PrintSightings()
    local list = {}
    for _, s in pairs(Sightings()) do list[#list + 1] = s end
    if #list == 0 then
        ns.Print("Nothing sighted yet.")
        return
    end
    table.sort(list, function(a, b) return a.time > b.time end)
    for _, s in ipairs(list) do
        ns.Print(("|cffffd100%s|r: %s, %s"):format(s.name, Ago(s.time), Where(s)))
    end
end
