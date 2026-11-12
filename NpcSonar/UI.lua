--------------------------------------------------------------------------------
-- NPC Sonar -- the window
--
-- Built lazily on first open from the flat widgets in Style.lua. Draws state
-- and forwards input to Core; it owns no scanning logic.
--------------------------------------------------------------------------------

local _, ns = ...
local S = ns.Style
local C = S.C

local WIDTH, PAD = 320, 12

local frame, nameBox, startBtn, stopBtn, statusText, stateText, stateDot
local partialToggle, soundLabel
local tiles = {}

local function Tooltip(widget, text)
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(text)
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", GameTooltip_Hide)
end

local function PaintTile(t)
    local selected = t.index == ns.db.icon
    t:SetBackdropColor(unpack(t.hovered and C.hover or C.panel))
    t:SetBackdropBorderColor(unpack(selected and C.accent or C.border))
    t.icon:SetAlpha((selected or t.hovered) and 1 or 0.55)
end

local function Build()
    frame = CreateFrame("Frame", "NpcSonarFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, 356)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    S.Backdrop(frame, C.bg)
    local pt = ns.db.point
    if pt then
        frame:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
    else
        frame:SetPoint("CENTER")
    end
    frame:Hide()
    tinsert(UISpecialFrames, "NpcSonarFrame") -- Escape closes it

    -- Header: the drag handle --------------------------------------------------
    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(32)
    header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    header:SetBackdropColor(unpack(C.header))
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local p, _, rp, x, y = frame:GetPoint()
        ns.db.point = { p, rp, x, y }
    end)

    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetSize(16, 16)
    logo:SetPoint("LEFT", PAD, 0)
    logo:SetTexture(ns.IconPath(8))

    local title = S.Font(header, 13, C.text)
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("NPC Sonar")

    stateDot = header:CreateTexture(nil, "ARTWORK")
    stateDot:SetSize(6, 6)
    stateDot:SetPoint("LEFT", title, "RIGHT", 10, 0)
    stateDot:SetColorTexture(1, 1, 1, 1)

    stateText = S.Font(header, 10, C.muted)
    stateText:SetPoint("LEFT", stateDot, "RIGHT", 5, 0)

    local close = CreateFrame("Button", nil, header)
    close:SetSize(32, 32)
    close:SetPoint("RIGHT")
    local x = S.Font(close, 14, C.muted)
    x:SetPoint("CENTER")
    x:SetText("x")
    close:SetScript("OnEnter", function() x:SetTextColor(1, 1, 1, 1) end)
    close:SetScript("OnLeave", function() x:SetTextColor(unpack(C.muted)) end)
    close:SetScript("OnClick", function() frame:Hide() end)

    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    line:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(unpack(C.border))

    -- Name input ---------------------------------------------------------------
    local nameCap = S.Caption(frame, "NPC name")
    nameCap:SetPoint("TOPLEFT", PAD, -46)

    local targetBtn = S.Button(frame, "Target", 64, 26)
    targetBtn:SetPoint("TOPRIGHT", -PAD, -60)
    Tooltip(targetBtn, "Use your current target's name")

    nameBox = S.Input(frame, 1, 26, "e.g. Shade of Ashar, Grimtooth")
    nameBox:SetPoint("TOPLEFT", PAD, -60)
    nameBox:SetPoint("RIGHT", targetBtn, "LEFT", -6, 0)
    nameBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        ns.Start(self:GetText())
    end)
    nameBox:HookScript("OnTextChanged", function(self, userInput)
        if userInput then ns.db.names = self:GetText() end
    end)

    targetBtn:SetScript("OnClick", function()
        local name = ns.Clean(UnitName("target"))
        if type(name) == "string" then
            nameBox:SetText(name)
            ns.db.names = name
        else
            ns.Print("Target an NPC first.")
        end
    end)

    -- Marker tiles -------------------------------------------------------------
    local markCap = S.Caption(frame, "Marker")
    markCap:SetPoint("TOPLEFT", PAD, -100)

    local tileSize, gap = 32, 5
    for slot = 1, 8 do
        local i = 9 - slot -- skull first
        local t = CreateFrame("Button", nil, frame, "BackdropTemplate")
        t:SetSize(tileSize, tileSize)
        t:SetPoint("TOPLEFT", PAD + (slot - 1) * (tileSize + gap), -114)
        t.index = i
        S.Backdrop(t, C.panel)
        t.icon = t:CreateTexture(nil, "ARTWORK")
        t.icon:SetPoint("TOPLEFT", 5, -5)
        t.icon:SetPoint("BOTTOMRIGHT", -5, 5)
        t.icon:SetTexture(ns.IconPath(i))
        t:SetScript("OnClick", function()
            ns.db.icon = i
            ns.Refresh()
            ns.Rescan()
        end)
        t:SetScript("OnEnter", function(self)
            self.hovered = true; PaintTile(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(ns.ICON_NAMES[i])
            GameTooltip:Show()
        end)
        t:SetScript("OnLeave", function(self)
            self.hovered = false; PaintTile(self)
            GameTooltip:Hide()
        end)
        tiles[i] = t
    end

    -- Options ------------------------------------------------------------------
    partialToggle = S.Toggle(frame, "Partial name match", function(on)
        ns.db.partial = on
        ns.UpdateMarkButton()
    end)
    partialToggle:SetPoint("TOPLEFT", PAD, -160)
    Tooltip(partialToggle, "Match any NPC whose name contains the text")

    -- Alert sound: < name > stepper. Every step plays the sound so you hear
    -- what you picked; clicking the name plays it again.
    local soundCap = S.Caption(frame, "Alert sound")
    soundCap:SetPoint("TOPLEFT", PAD, -190)

    local prevBtn = S.Button(frame, "<", 28, 26)
    prevBtn:SetPoint("TOPLEFT", PAD, -204)
    local nextBtn = S.Button(frame, ">", 28, 26)
    nextBtn:SetPoint("TOPRIGHT", -PAD, -204)

    local soundBox = CreateFrame("Button", nil, frame, "BackdropTemplate")
    soundBox:SetPoint("TOPLEFT", prevBtn, "TOPRIGHT", 4, 0)
    soundBox:SetPoint("BOTTOMRIGHT", nextBtn, "BOTTOMLEFT", -4, 0)
    S.Backdrop(soundBox, C.panel)
    soundLabel = S.Font(soundBox, 12, C.text)
    soundLabel:SetPoint("CENTER")
    soundBox:SetScript("OnClick", function() ns.PlayAlertSound() end)
    soundBox:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(C.accent))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Click to preview")
        GameTooltip:Show()
    end)
    soundBox:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(C.border))
        GameTooltip:Hide()
    end)

    local function Step(delta)
        local list = ns.SoundChoices()
        local at = 1
        for i, s in ipairs(list) do
            if s.key == ns.db.sound then at = i end
        end
        local pick = list[(at - 1 + delta) % #list + 1]
        ns.db.sound = pick.key
        ns.PlayAlertSound()
        ns.Refresh()
    end
    prevBtn:SetScript("OnClick", function() Step(-1) end)
    nextBtn:SetScript("OnClick", function() Step(1) end)

    -- Status -------------------------------------------------------------------
    local statusPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    statusPanel:SetPoint("TOPLEFT", PAD, -242)
    statusPanel:SetPoint("TOPRIGHT", -PAD, -242)
    -- Three lines at 11pt: the "Found" line plus a hint that wraps once.
    statusPanel:SetHeight(60)
    S.Backdrop(statusPanel, C.panel)

    statusText = S.Font(statusPanel, 11, C.text)
    statusText:SetPoint("TOPLEFT", 10, -8)
    statusText:SetPoint("BOTTOMRIGHT", -10, 6)
    statusText:SetJustifyH("LEFT")
    statusText:SetJustifyV("TOP")
    statusText:SetWordWrap(true)

    -- Actions ------------------------------------------------------------------
    local half = (WIDTH - PAD * 2 - 8) / 2
    startBtn = S.Button(frame, "Start scan", half, 30, "primary")
    startBtn:SetPoint("BOTTOMLEFT", PAD, PAD)
    startBtn:SetScript("OnClick", function()
        nameBox:ClearFocus()
        ns.Start(nameBox:GetText())
    end)

    stopBtn = S.Button(frame, "Stop", half, 30, "secondary")
    stopBtn:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    stopBtn:SetScript("OnClick", function() ns.Stop() end)
end

--------------------------------------------------------------------------------

local lastStatus = "Enter a name and start a scan."

function ns.SetStatus(text)
    if text == lastStatus then return end
    lastStatus = text
    if statusText then statusText:SetText(text) end
end

function ns.Refresh()
    if not frame then return end
    local on = ns.scanning
    stateDot:SetColorTexture(unpack(on and C.good or C.muted))
    stateText:SetText(on and "SCANNING" or "IDLE")
    stateText:SetTextColor(unpack(on and C.good or C.muted))
    if not nameBox:HasFocus() then nameBox:SetText(ns.db.names or "") end
    for _, t in pairs(tiles) do PaintTile(t) end
    partialToggle:SetChecked(ns.db.partial)
    local soundName = "None"
    for _, s in ipairs(ns.SoundChoices()) do
        if s.key == ns.db.sound then soundName = s.label end
    end
    soundLabel:SetText(soundName)
    soundLabel:SetTextColor(unpack(ns.db.sound == "NONE" and C.muted or C.text))
    startBtn:SetLabel(on and "Restart scan" or "Start scan")
    stopBtn:SetEnabled(on)
    statusText:SetText(lastStatus)
end

function ns.ToggleWindow()
    if not frame then Build() end
    frame:SetShown(not frame:IsShown())
    ns.Refresh()
end
