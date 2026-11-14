--------------------------------------------------------------------------------
-- NPC Sonar -- the sonar badge
--
-- One small badge that is always on screen, so new players find it. While
-- idle it sits still and slightly dimmed; while a scan runs its sonar scope
-- sweeps round; when a match is in range the sweep stops, an orange contact
-- appears and the border turns green. It is also the button that places the
-- raid marker:
--
--   left-click / keybind   idle: start the scan (or open the window if no
--                          name is set); scanning: target the NPC and mark it
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
_G["BINDING_NAME_CLICK NpcSonarMarkButton:LeftButton"] = "Start scan / target & mark the NPC"

local IDLE_ALPHA = 0.75

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
-- The attribute is only set while scanning (see Apply); while idle the left
-- click does nothing secure, and the hook below starts the scan instead.
-- Both edges registered with an explicit useOnKeyDown is how a secure button
-- fires exactly once on current clients, whatever ActionButtonUseKeyDown says.
btn:RegisterForClicks("LeftButtonUp", "LeftButtonDown", "RightButtonUp")
btn:SetAttribute("useOnKeyDown", false)
-- A hook runs after the secure handler and only touches our own code and
-- unprotected window, so it is safe in combat. Starting a scan in combat
-- works; the badge just takes on its macro once combat ends.
-- Left clicks fire on both edges; only the up edge counts, as for the secure
-- handler (useOnKeyDown false). Starting on the down edge would set the
-- macro in time for the up edge to run it, clearing your target.
-- If a scan stopped in combat, the badge still holds its macro until combat
-- ends (see Apply), so that click marks and must not also restart a scan.
local function HoldsMacro()
    return btn:GetAttribute("*type1") ~= nil
end

btn:HookScript("OnClick", function(_, button, down)
    if button == "RightButton" then
        ns.ToggleWindow()
    elseif down or ns.scanning or HoldsMacro() then
        return
    elseif not ns.Start() then
        -- No name yet: open the window so there is somewhere to type one.
        if not (NpcSonarFrame and NpcSonarFrame:IsShown()) then ns.ToggleWindow() end
    end
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
    self:SetAlpha(1)  -- full strength under the mouse, even while idle
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if not ns.scanning then
        GameTooltip:SetText("NPC Sonar: idle")
        local names = ns.NamesText()
        if names ~= "" then GameTooltip:AddLine(names, 1, 1, 1, true) end
        GameTooltip:AddLine("Left-click: start scanning", 0.7, 0.7, 0.7)
    else
        GameTooltip:SetText(ns.found and "NPC Sonar: found" or "NPC Sonar: scanning")
        -- Names from the rows here; quests get their own block below.
        local names = ns.NamesText(ns.db.npcs)
        if names ~= "" then GameTooltip:AddLine(names, 1, 1, 1, true) end
        GameTooltip:AddLine("Left-click: target & mark it", 0.7, 0.7, 0.7)
        if ns.HasQuests() then
            ns.AddQuestTrackingLines(GameTooltip)
            GameTooltip:AddLine(" ")
        end
    end
    GameTooltip:AddLine("Right-click: open window. Right-drag: move.", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Bind a key under Key Bindings > AddOns.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", function(self)
    self:SetBackdropColor(unpack(C.bg))
    self:SetAlpha((ns.scanning or HoldsMacro()) and 1 or IDLE_ALPHA)
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
    local names = ns.MacroNames()
    local lines
    if #names == 0 then
        -- Only quests are tracked and none of their NPCs has been seen yet:
        -- nothing to target by name, so mark whatever you have targeted
        -- rather than clearing it.
        lines = { "/tm [@target,exists,nodead] " .. ns.db.icon }
    elseif ns.HasNameIcons() then
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
        -- The last /target line that matches wins, so names found for quests
        -- (after the wanted names in `names`) go first: a named rare nearby
        -- beats a quest mob.
        lines = { "/cleartarget" }
        local rows = #ns.WantedNames()
        for i = rows + 1, #names do
            lines[#lines + 1] = cmd .. names[i]
        end
        for i = 1, rows do
            lines[#lines + 1] = cmd .. names[i]
        end
        lines[#lines + 1] = "/tm [exists,nodead] " .. ns.db.icon
    end
    -- Pings are retail-only. Leave the line out where the system doesn't
    -- exist, or every click would print an unknown-command error.
    -- The ping type follows the target: an attack ping is refused on a
    -- friendly unit, so friendly NPCs get "assist", and anything neither
    -- attackable nor friendly (some neutral NPCs) gets "warning".
    if C_Ping then
        lines[#lines + 1] = "/ping [@target,harm,nodead] attack; "
            .. "[@target,help,nodead] assist; [@target,exists,nodead] warning"
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
    -- While idle there is nothing to mark: no macro, and the click hook
    -- starts the scan instead.
    btn:SetAttribute("*type1", ns.scanning and "macro" or nil)
    btn:SetAttribute("macrotext", ns.scanning and BuildMacro() or nil)
    btn:Show()
    ns.UpdateIndicator()  -- the dimming follows whether it still holds the macro
end

function ns.UpdateMarkButton()
    -- The corner shows what a click marks: with per-name markers, the
    -- first-listed name's, since that is the target a click leaves you on.
    local first = ns.MacroNames()[1]
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
    -- Alpha is cosmetic, so it may change in combat. A badge still holding
    -- its macro (scan stopped mid-combat) stays at full strength, since a
    -- click would still mark.
    btn:SetAlpha((ns.scanning or HoldsMacro()) and 1 or IDLE_ALPHA)
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
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- Saved settings exist by now; put the idle badge on screen.
        ns.UpdateMarkButton()
        ns.UpdateIndicator()
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Last chance before lockdown to finish a drag on the secure frame.
        EndDrag()
    elseif pending then
        ns.UpdateMarkButton()
    end
end)
