--------------------------------------------------------------------------------
-- NPC Sonar -- the sonar badge
--
-- One small badge that is on screen only while a scan runs. Its sonar scope
-- sweeps round while searching; when a match is in range the sweep stops, an
-- orange contact appears and the border turns green. It is also the button
-- that places the raid marker:
--
--   left-click / keybind   target the NPC and mark it
--   right-click            open or close the window
--   right-drag             move it
--
-- Placing a raid marker is a protected action: an addon may not call
-- SetRaidTarget, but a secure button may run /tm when the player clicks it or
-- presses its keybind. So the badge is a secure button holding a macro:
--
--   /cleartarget                 so a miss can't mark whatever you had targeted
--   /targetexact <name>          one line per wanted name (/target if partial)
--   /tm [exists,nodead] <icon>
--
-- When names carry their own {tag} markers, that block is repeated per name
-- instead; see BuildMacro.
--
-- Secure frames can't be shown, hidden, moved or have attributes changed in
-- combat, so those changes wait for combat to end. Colours, textures and the
-- sweep are cosmetic and update at any time. The badge is parented to UIParent
-- and not anchored to the window, because a protected frame would make
-- anything it is attached to protected too, and closing the window in combat
-- would then trigger the blocked-action popup this file exists to avoid.
--------------------------------------------------------------------------------

local _, ns = ...
local S = ns.Style
local C = S.C

-- Rendered from assets/make_icon.py: the scope alone, and with the contact.
local SCOPE_SEARCH = "Interface\\AddOns\\NpcSonar\\Media\\sonar_search"
local SCOPE_FOUND  = "Interface\\AddOns\\NpcSonar\\Media\\sonar_found"
local SWEEP_SECONDS = 2.5   -- one full turn

BINDING_HEADER_NPCSONAR = "NPC Sonar"
_G["BINDING_NAME_CLICK NpcSonarMarkButton:LeftButton"] = "Target & mark the NPC"

local btn = CreateFrame("Button", "NpcSonarMarkButton", UIParent,
    "SecureActionButtonTemplate, BackdropTemplate")
btn:SetSize(36, 36)
btn:SetFrameStrata("MEDIUM")
btn:SetClampedToScreen(true)
btn:SetMovable(true)
S.Backdrop(btn, C.bg)
btn:Hide()

local scope = btn:CreateTexture(nil, "ARTWORK")
scope:SetPoint("CENTER")
scope:SetSize(32, 32)
scope:SetTexture(SCOPE_SEARCH)

-- The chosen raid marker, small in the corner, so you can see what a click
-- will place.
local marker = btn:CreateTexture(nil, "OVERLAY")
marker:SetSize(14, 14)
marker:SetPoint("BOTTOMRIGHT", 4, -4)

-- The whole scope turns, which reads as the sweep going round: the rings and
-- crosshair are symmetric, so only the sweep visibly moves. Negative degrees
-- is clockwise.
local sweep = scope:CreateAnimationGroup()
sweep:SetLooping("REPEAT")
local turn = sweep:CreateAnimation("Rotation")
turn:SetDegrees(-360)
turn:SetDuration(SWEEP_SECONDS)

-- *type1, not type: the macro belongs to the left button only, so right-clicks
-- stay free for opening the window. The * matches any modifier; a bare "type1"
-- is skipped when one is held, which would break modified keybinds like SHIFT-Q.
btn:SetAttribute("*type1", "macro")
-- Both edges registered with an explicit useOnKeyDown is how a secure button
-- fires exactly once on current clients, whatever ActionButtonUseKeyDown says.
btn:RegisterForClicks("LeftButtonUp", "LeftButtonDown", "RightButtonUp")
btn:SetAttribute("useOnKeyDown", false)
-- A hook runs after the secure handler and only touches our own unprotected
-- window, so it is safe in combat.
btn:HookScript("OnClick", function(_, button)
    if button == "RightButton" then ns.ToggleWindow() end
end)

local dragging = false
btn:RegisterForDrag("RightButton")
btn:SetScript("OnDragStart", function(self)
    if InCombatLockdown() then return end
    dragging = true
    self:StartMoving()
end)
local function EndDrag()
    if not dragging then return end
    dragging = false
    btn:StopMovingOrSizing()
    local p, _, rp, x, y = btn:GetPoint()
    ns.db.indicatorPoint = { p, rp, x, y }
end
btn:SetScript("OnDragStop", function()
    -- Moving a secure frame is blocked in combat; if a pull interrupted the
    -- drag, PLAYER_REGEN_DISABLED below already ended it.
    if not InCombatLockdown() then EndDrag() end
end)

btn:SetScript("OnEnter", function(self)
    self:SetBackdropColor(unpack(C.hover))
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(ns.found and "NPC Sonar: found" or "NPC Sonar: scanning")
    GameTooltip:AddLine(ns.db.names or "", 1, 1, 1, true)
    GameTooltip:AddLine("Left-click: target & mark it", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click: open window. Right-drag: move.", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Bind a key under Key Bindings > AddOns.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", function(self)
    self:SetBackdropColor(unpack(C.bg))
    GameTooltip:Hide()
end)

--------------------------------------------------------------------------------
-- Protected state: position, macro, visibility. Deferred in combat.

local placed = false
local pending = false

-- With one marker for every name, target whichever is around and mark it.
-- When names carry their own {tag} markers, each name is targeted and marked
-- in turn, with /cleartarget before each so a miss can't put that name's
-- marker on the previous NPC. Names go last-to-first so the first listed is
-- marked last; a final pass of /targetexact (or /target) lines without
-- /cleartarget, which keep the current target when nothing matches, leaves
-- you targeting the first-listed name that is around.
local function BuildMacro()
    local cmd = ns.db.partial and "/target " or "/targetexact "
    local names = ns.WantedNames()
    local lines
    if ns.HasNameIcons() then
        lines = {}
        for i = #names, 1, -1 do
            lines[#lines + 1] = "/cleartarget"
            lines[#lines + 1] = cmd .. names[i]
            lines[#lines + 1] = "/tm [exists,nodead] " .. ns.IconFor(names[i])
        end
        for i = #names, 1, -1 do
            lines[#lines + 1] = cmd .. names[i]
        end
    else
        lines = { "/cleartarget" }
        for _, name in ipairs(names) do
            lines[#lines + 1] = cmd .. name
        end
        lines[#lines + 1] = "/tm [exists,nodead] " .. ns.db.icon
    end
    -- Pings are retail-only. Leave the line out where the system doesn't
    -- exist, or every click would print an unknown-command error.
    if C_Ping then
        lines[#lines + 1] = "/ping [@target,exists,nodead] attack"
    end
    return table.concat(lines, "\n")
end

local function Apply()
    if not placed then
        placed = true
        local pt = ns.db.indicatorPoint
        btn:ClearAllPoints()
        if pt then
            btn:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
        else
            btn:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
        end
    end
    btn:SetAttribute("macrotext", BuildMacro())
    btn:SetShown(ns.scanning)
end

function ns.UpdateMarkButton()
    -- The corner shows what a click marks: with per-name markers, the
    -- first-listed name's, since that is the target a click leaves you on.
    local first = ns.WantedNames()[1]
    marker:SetTexture(ns.IconPath(first and ns.IconFor(first) or ns.db.icon))
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    Apply()
end

--------------------------------------------------------------------------------
-- Cosmetic state: searching vs found. Safe in combat.

function ns.UpdateIndicator()
    if ns.scanning and ns.found then
        -- Stop() returns the scope to its unrotated pose, where the contact
        -- sits just behind the sweep line.
        sweep:Stop()
        scope:SetTexture(SCOPE_FOUND)
        btn:SetBackdropBorderColor(unpack(C.good))
    else
        scope:SetTexture(SCOPE_SEARCH)
        btn:SetBackdropBorderColor(unpack(C.border))
        if ns.scanning then
            if not sweep:IsPlaying() then sweep:Play() end
        else
            sweep:Stop()
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Last chance before lockdown to finish a drag on the secure frame.
        EndDrag()
    elseif pending then
        ns.UpdateMarkButton()
    end
end)
