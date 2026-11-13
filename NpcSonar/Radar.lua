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
-- Positions are unavailable inside instances, and vignette names can be
-- secret there (Midnight); either way the radar simply finds nothing.
--------------------------------------------------------------------------------

local _, ns = ...
local S = ns.Style
local C = S.C

local ARROW = "Interface\\AddOns\\NpcSonar\\Media\\radar_arrow"
local UPDATE_INTERVAL = 0.05   -- arrow refresh while shown

local announced = {}   -- vignette GUIDs announced this scan
local tracked          -- { guid, name, want } for the vignette the arrow follows

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
local function Offset(guid)
    local mapID = PlayerMap()
    for _ = 1, 4 do
        if not mapID or mapID == 0 then return nil end
        local east, south = OffsetOn(guid, mapID)
        if east then return east, south end
        local info = C_Map.GetMapInfo(mapID)
        mapID = info and info.parentMapID
    end
    return nil
end

--------------------------------------------------------------------------------
-- The arrow. A plain frame of our own on UIParent: never protected, so it can
-- show, hide and move in combat. Left-drag moves it.

local arrow = CreateFrame("Frame", "NpcSonarRadarArrow", UIParent)
arrow:SetSize(56, 76)
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

local label = S.Font(arrow, 11, C.text, "OUTLINE")
label:SetPoint("TOP", head, "BOTTOM", 0, -2)

local dist = S.Font(arrow, 10, C.muted, "OUTLINE")
dist:SetPoint("TOP", label, "BOTTOM", 0, -1)

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
arrow:SetScript("OnUpdate", function(self, dt)
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
            end
            local d = east and (east * east + south * south)
            if d and (not best or d < bestDist) then
                best, bestDist = { guid = guid, name = name, want = want }, d
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
