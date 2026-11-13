--------------------------------------------------------------------------------
-- NPC Sonar -- long-range radar for rares
--
-- Nameplates only exist within ~40-60 yd. Rares, treasures and other special
-- NPCs also show up as "vignettes" (the minimap skull/star icons), which the
-- client reports from much further away and with a map position. While a
-- scan runs, vignettes whose name matches a wanted name are announced, and an
-- arrow points at the nearest one with its distance.
--
-- Direction: map positions are fractions of the current map (x east, y
-- south). C_Map.GetMapWorldSize turns them into yards, so the bearing and
-- distance are true even though maps aren't square. GetPlayerFacing is
-- radians counter-clockwise from north, and Texture:SetRotation turns
-- counter-clockwise too, so the arrow (drawn pointing up) is rotated by
-- bearing - facing.
--
-- Positions are unavailable inside instances: a match there is still
-- announced, but gets no arrow. Vignette names can also be secret there
-- (Midnight), and a secret name never matches.
--------------------------------------------------------------------------------

local _, ns = ...
local S = ns.Style
local C = S.C

local ARROW = "Interface\\AddOns\\NpcSonar\\Media\\radar_arrow"
local UPDATE_INTERVAL = 0.05   -- arrow refresh while shown
local MODEL_SIZE = 72
local MODEL_SPIN = 0.6         -- radians per second, a slow turntable

local announced = {}   -- vignette GUIDs announced this scan
local tracked          -- { guid, name, want, npcID } for the vignette the arrow follows

--------------------------------------------------------------------------------
-- NPC details. A vignette carries the NPC's GUID, and with it the creature
-- ID the model is drawn from, but not its level. The level is only readable
-- from a unit (nameplate, target, mouseover), so it is remembered per
-- creature in NpcSonarDB.npcInfo whenever a matching NPC is seen as one, and
-- shown from then on, even from radar range on a later hunt. Until then the
-- level reads "??".

-- Creature ID from a GUID like "Creature-0-1234-0-56-12345-0000ABCDEF".
local function NpcID(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
    return nil
end

local CLASSIFICATION = {
    rare = "Rare", rareelite = "Rare Elite", elite = "Elite",
    worldboss = "Boss",
}

-- Most open-world rares on Retail scale to whoever looks at them, so a level
-- equal to the viewer's is stored as "scaled" and shown as your current
-- level; another character then sees its own level, not the one who saw it.
local SCALES = WOW_PROJECT_ID == nil or WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

local function DetailText(npcID)
    local info = npcID and ns.db.npcInfo and ns.db.npcInfo[npcID]
    local level = info and (info.scaled and UnitLevel("player") or info.level)
    local text = "Level " .. ((level and level > 0) and level or "??")
    local class = info and CLASSIFICATION[info.class]
    if class then text = text .. "  " .. class end
    return text
end

--------------------------------------------------------------------------------
-- Positions

local function PlayerMap()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
end

-- Yards east and south from the player to the vignette on one map, or nil.
local function OffsetOn(guid, mapID)
    local w, h = C_Map.GetMapWorldSize(mapID)
    local me = C_Map.GetPlayerMapPosition(mapID, "player")
    local ok, it = pcall(C_VignetteInfo.GetVignettePosition, guid, mapID)
    if not (w and w > 0 and me and ok and it) then return nil end
    return (it.x - me.x) * w, (it.y - me.y) * h
end

-- The player's best map can be a small sub-map (a cave, a building) that
-- doesn't hold the vignette; walk up to the parent maps until one does.
-- Returns the first non-nil result of fn(mapID).
local function OnPlayerMaps(fn)
    local mapID = PlayerMap()
    for _ = 1, 4 do
        if not mapID or mapID == 0 then return nil end
        local a, b, c = fn(mapID)
        if a then return a, b, c end
        local info = C_Map.GetMapInfo(mapID)
        mapID = info and info.parentMapID
    end
    return nil
end

local function Offset(guid)
    return OnPlayerMaps(function(mapID) return OffsetOn(guid, mapID) end)
end

-- Map ID and position of a vignette, for waypoints and the sighting log.
function ns.VignettePosition(guid)
    return OnPlayerMaps(function(mapID)
        -- A vignette outside a small sub-map can come back with coordinates
        -- beyond its edges; keep walking up to a map that contains it.
        local ok, pos = pcall(C_VignetteInfo.GetVignettePosition, guid, mapID)
        if ok and pos and pos.x >= 0 and pos.x <= 1 and pos.y >= 0 and pos.y <= 1 then
            return mapID, pos.x, pos.y
        end
    end)
end

--------------------------------------------------------------------------------
-- The arrow. A plain frame of our own on UIParent: never protected, so it can
-- show, hide and move in combat. Left-drag moves it.

-- Height of the arrow head and of the text block under it; the model's
-- height is added only while it shows (see ShowModel).
local HEAD_HEIGHT, TEXT_HEIGHT = 40, 40

local arrow = CreateFrame("Frame", "NpcSonarRadarArrow", UIParent)
arrow:SetSize(MODEL_SIZE, HEAD_HEIGHT + TEXT_HEIGHT)
arrow:SetFrameStrata("MEDIUM")
arrow:SetClampedToScreen(true)
arrow:SetMovable(true)
arrow:EnableMouse(true)
arrow:RegisterForDrag("LeftButton")
arrow:Hide()

local head = arrow:CreateTexture(nil, "ARTWORK")
head:SetSize(40, 40)
head:SetPoint("TOP")
head:SetTexture(ARROW)

-- The NPC itself, small and slowly turning. Hidden for vignettes that
-- aren't creatures (treasures, objects), and the text moves up into its place.
local model = CreateFrame("PlayerModel", nil, arrow)
model:SetSize(MODEL_SIZE, MODEL_SIZE)
model:SetPoint("TOP", head, "BOTTOM", 0, 0)
model:SetPortraitZoom(0)
model:Hide()

local label = S.Font(arrow, 11, C.text, "OUTLINE")

local detail = S.Font(arrow, 10, C.accent, "OUTLINE")
detail:SetPoint("TOP", label, "BOTTOM", 0, -1)

local dist = S.Font(arrow, 10, C.muted, "OUTLINE")

local MAX_MODEL_TRIES = 5
local modelID     -- creature currently in the model
local modelTries = 0
local layout      -- "creature" or "object", the layout last applied
local spin = 0

-- Lays out the frame for a creature (model, name, level, distance) or for
-- anything else (name, distance), only when that changes. The frame's height
-- follows, so it never leaves an empty area to drag or clamp by.
local function Layout(kind)
    if kind == layout then return end
    layout = kind
    label:ClearAllPoints()
    dist:ClearAllPoints()
    if kind == "creature" then
        model:Show()
        detail:Show()
        label:SetPoint("TOP", model, "BOTTOM", 0, -2)
        dist:SetPoint("TOP", detail, "BOTTOM", 0, -1)
        arrow:SetHeight(HEAD_HEIGHT + MODEL_SIZE + TEXT_HEIGHT)
    else
        model:Hide()
        detail:Hide()
        label:SetPoint("TOP", head, "BOTTOM", 0, -2)
        dist:SetPoint("TOP", label, "BOTTOM", 0, -1)
        arrow:SetHeight(HEAD_HEIGHT + TEXT_HEIGHT)
    end
end

-- Puts the tracked NPC in the model. Creature data the client hasn't cached
-- yet loads in the background, so a model that came up empty is asked for
-- again on later scans, a few times at most (some creatures have no model).
local function ShowModel(npcID)
    if not npcID then
        if modelID then model:ClearModel() end
        modelID = nil
        Layout("object")
        return
    end
    if npcID ~= modelID then
        modelID, modelTries = npcID, 1
        model:SetCreature(npcID)
    elseif (model:GetModelFileID() or 0) == 0 and modelTries < MAX_MODEL_TRIES then
        modelTries = modelTries + 1
        model:SetCreature(npcID)
    end
    Layout("creature")
end

arrow:SetScript("OnDragStart", arrow.StartMoving)
arrow:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    ns.db.radarPoint = { p, rp, x, y }
end)

local function PlaceArrow()
    local pt = ns.db.radarPoint
    arrow:ClearAllPoints()
    if pt then
        arrow:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
    else
        arrow:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
    end
end

local elapsed = 0
arrow:SetScript("OnUpdate", function(_, dt)
    if model:IsShown() then
        spin = (spin + dt * MODEL_SPIN) % (2 * math.pi)
        model:SetFacing(spin)
    end
    elapsed = elapsed + dt
    if elapsed < UPDATE_INTERVAL then return end
    elapsed = 0

    local east, south
    if tracked then east, south = Offset(tracked.guid) end
    local facing = GetPlayerFacing()
    if not (east and facing) then
        head:Hide()
        dist:SetText("")
        return
    end
    local bearing = math.atan2(-east, -south)  -- counter-clockwise from north
    head:SetRotation(bearing - facing)
    head:Show()
    dist:SetText(("%d yd"):format(math.sqrt(east * east + south * south) + 0.5))
end)

--------------------------------------------------------------------------------
-- Vignette scan

local function Track(best)
    tracked = best
    if not best then
        arrow:Hide()
        return
    end
    local color = ns.ColorFor(best.want)
    head:SetVertexColor(color[1], color[2], color[3])
    label:SetText(ns.IconString(ns.IconFor(best.want)) .. " " .. best.name)
    detail:SetText(DetailText(best.npcID))
    ShowModel(best.npcID)
    if not arrow:IsShown() then
        PlaceArrow()
        arrow:Show()
    end
end

function ns.RadarScan()
    if not (ns.scanning and ns.db.radar and C_VignetteInfo) then
        Track(nil)
        return
    end
    local best, bestDist
    for _, guid in ipairs(C_VignetteInfo.GetVignettes() or {}) do
        local ok, info = pcall(C_VignetteInfo.GetVignetteInfo, guid)
        local name = ok and info and ns.Clean(info.name)
        local want = type(name) == "string" and not ns.Clean(info.isDead) and ns.WantedFor(name)
        if want then
            -- Only a vignette we can place gets the arrow; elsewhere (inside
            -- instances) it is still announced, without promising a direction.
            local east, south = Offset(guid)
            -- Announce shares the alert cooldown; a vignette that lands inside
            -- it is tried again on the next RadarTick.
            if not announced[guid] and ns.Announce(("Detected %s %s on the minimap. %s")
                    :format(ns.IconString(ns.IconFor(want)), name,
                        east and "Follow the arrow." or "No direction available here.")) then
                announced[guid] = true
                ns.RecordSighting(name, want, guid)
            end
            local d = east and (east * east + south * south)
            if d and (not best or d < bestDist) then
                best, bestDist = {
                    guid = guid, name = name, want = want,
                    npcID = NpcID(ns.Clean(info.objectGUID)),
                }, d
            end
        end
    end
    Track(best)
end

-- Vignette events say when the list changes, but not when the player moves
-- closer to a different match or an announcement was held back by the alert
-- cooldown. Core's scan ticker calls this; it rescans once a second.
local lastTick = 0
function ns.RadarTick()
    local now = GetTime()
    if now - lastTick < 1 then return end
    lastTick = now
    ns.RadarScan()
end

-- Status line while nothing is in nameplate range, or nil.
function ns.RadarStatus()
    if not tracked then return nil end
    local text = dist:GetText()
    return ("|cff40b3f2Detected:|r %s %s%s\nFollow the arrow until it is in nameplate range.")
        :format(ns.IconString(ns.IconFor(tracked.want)), tracked.name,
            (text and text ~= "") and (" (" .. text .. ")") or "")
end

-- Called by Core for every unit that matches a wanted name: remembers the
-- creature's level and classification for the radar's detail line.
function ns.NoteUnit(unit)
    local id = NpcID(ns.Clean(UnitGUID(unit)))
    local level = ns.Clean(UnitLevel(unit))
    if not id or type(level) ~= "number" then return end
    local class = ns.Clean(UnitClassification(unit))
    class = type(class) == "string" and class or nil
    ns.db.npcInfo = ns.db.npcInfo or {}
    local old = ns.db.npcInfo[id]
    local scaled = SCALES and level == UnitLevel("player") or nil
    -- The scan sees a matching unit every 0.3 s; only write on a change.
    if old and old.level == level and old.class == class and old.scaled == scaled then return end
    ns.db.npcInfo[id] = { level = level, class = class, scaled = scaled }
    if tracked and tracked.npcID == id then detail:SetText(DetailText(id)) end
end

function ns.ResetRadar()
    wipe(announced)
    ns.RadarScan()
end

local events = CreateFrame("Frame")
if C_VignetteInfo then
    events:RegisterEvent("VIGNETTES_UPDATED")
    events:RegisterEvent("VIGNETTE_MINIMAP_UPDATED")
end
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", function()
    if ns.db then ns.RadarScan() end
end)
