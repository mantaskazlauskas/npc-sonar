--------------------------------------------------------------------------------
-- NPC Sonar -- launchers: the minimap button and the addon compartment entry
--
-- Both do the same thing:
--   left-click    open or close the window
--   right-click   start or stop the scan (opens the window if no name is set)
--   hover         tooltip with the scan state
--
-- Minimap button: a plain named Button parented to Minimap, in the usual round
-- style. Button collectors (Enhance QoL's button sink and others) gather named
-- buttons parented to Minimap, so this also shows up in their grids. Once a
-- collector has re-parented it, the button stops positioning itself.
--
-- Addon compartment: registered from code rather than with the .toc's
-- AddonCompartmentFunc line, because only Retail reads that line while the
-- Classic clients that have the compartment still accept RegisterAddon. Doing
-- both would list us twice on Retail.
--------------------------------------------------------------------------------

local _, ns = ...

local ICON = "Interface\\AddOns\\NpcSonar\\Media\\sonar_search"
local DEFAULT_ANGLE = 225   -- degrees, bottom-left of the minimap

--------------------------------------------------------------------------------
-- Shared behaviour

local function OnLauncherClick(mouseButton)
    if mouseButton == "RightButton" then
        if ns.scanning then
            ns.Stop()
        elseif not ns.Start() then
            -- No name saved yet: open the window so there's somewhere to type
            -- one, instead of leaving only a chat message.
            if not (NpcSonarFrame and NpcSonarFrame:IsShown()) then ns.ToggleWindow() end
        end
    else
        ns.ToggleWindow()
    end
end

local function ShowTooltip(owner, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_LEFT")
    GameTooltip:SetText("NPC Sonar")
    if ns.scanning then
        GameTooltip:AddLine("Scanning for: " .. (ns.db.names or ""), 0.32, 0.85, 0.48, true)
    else
        GameTooltip:AddLine("Idle", 0.55, 0.57, 0.63)
    end
    GameTooltip:AddLine("Left-click: open window", 0.7, 0.7, 0.7)
    GameTooltip:AddLine(ns.scanning and "Right-click: stop scan" or "Right-click: start scan", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Minimap button

local mini = CreateFrame("Button", "NpcSonarMinimapButton", Minimap)
mini:SetSize(31, 31)
mini:SetFrameStrata("MEDIUM")
mini:SetFrameLevel(8)
mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mini:RegisterForDrag("LeftButton")
mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
mini:Hide()

local background = mini:CreateTexture(nil, "BACKGROUND")
background:SetSize(20, 20)
background:SetPoint("TOPLEFT", 7, -5)
background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

local icon = mini:CreateTexture(nil, "ARTWORK")
icon:SetSize(19, 19)
icon:SetPoint("TOPLEFT", 6, -6)
icon:SetTexture(ICON)

local border = mini:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53)
border:SetPoint("TOPLEFT")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

local function OwnedByMinimap()
    return mini:GetParent() == Minimap
end

local function PlaceOnRim()
    if not OwnedByMinimap() then return end
    local angle = math.rad(ns.db.minimapAngle or DEFAULT_ANGLE)
    local radius = Minimap:GetWidth() / 2 + 5
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function FollowCursor()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    ns.db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
    PlaceOnRim()
end

mini:SetScript("OnDragStart", function(self)
    if not OwnedByMinimap() then return end  -- a collector is managing it
    self:SetScript("OnUpdate", FollowCursor)
    GameTooltip:Hide()
end)
mini:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
end)
mini:SetScript("OnClick", function(_, mouseButton) OnLauncherClick(mouseButton) end)
mini:SetScript("OnEnter", function(self) ShowTooltip(self) end)
mini:SetScript("OnLeave", function() GameTooltip:Hide() end)

function ns.UpdateMinimapButton()
    if ns.db.minimapHidden then
        mini:Hide()
    else
        PlaceOnRim()
        mini:Show()
    end
end

function ns.ToggleMinimapButton()
    ns.db.minimapHidden = not ns.db.minimapHidden
    ns.UpdateMinimapButton()
    ns.Print(ns.db.minimapHidden
        and "Minimap button hidden. Type /npcsonar minimap to show it again."
        or "Minimap button shown.")
end

--------------------------------------------------------------------------------
-- Addon compartment

local function RegisterCompartment()
    if not (AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon) then return end
    AddonCompartmentFrame:RegisterAddon({
        text = "NPC Sonar",
        icon = ICON,
        notCheckable = true,
        registerForAnyClick = true,
        func = function(_, menuInputData)
            OnLauncherClick(menuInputData and menuInputData.buttonName)
        end,
        funcOnEnter = function(button) ShowTooltip(button) end,
        funcOnLeave = function() GameTooltip:Hide() end,
    })
end

--------------------------------------------------------------------------------

-- Called by Core once the saved settings exist.
function ns.SetupLaunchers()
    ns.UpdateMinimapButton()
    RegisterCompartment()
end
