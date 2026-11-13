--------------------------------------------------------------------------------
-- NPC Sonar -- the window
--
-- Built lazily on first open from the flat widgets in Style.lua. Draws state
-- and forwards input to Core; it owns no scanning logic.
--
-- The NPCs to look for are rows (NpcSonarDB.npcs): a name box, a marker
-- button, a sound button and a remove button each. A row's marker and sound
-- start as "Default", which follows the default marker tiles and default
-- sound further down. Rows can be added up to MAX_ROWS; everything below
-- them sits in one frame that moves down as rows are added, and the window's
-- height follows.
--------------------------------------------------------------------------------

local ADDON, ns = ...
local S = ns.Style
local C = S.C

local WIDTH, PAD = 320, 12
local ROW_H, ROW_GAP = 26, 4
local MAX_ROWS = ns.MAX_NPCS
local SPEAKER = "Interface\\AddOns\\NpcSonar\\Media\\speaker"  -- from assets/make_speaker.py

local frame, rowsArea, addBtn, startBtn, stopBtn, statusText, stateText, stateDot
local partialToggle, friendlyToggle, pinToggle, deathToggle, radarToggle, waypointToggle, soundLabel, listLabel
local tiles = {}
local rows = {}         -- row widgets, reused; rows[i] shows ns.db.npcs[i]
local topHeight, lowerHeight

local function Tooltip(widget, text)
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(text)
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", GameTooltip_Hide)
end

-- The window always shows at least one row to type into.
local function Npcs()
    ns.db.npcs = ns.db.npcs or {}
    if #ns.db.npcs == 0 then ns.db.npcs[1] = { name = "" } end
    return ns.db.npcs
end

local function SoundLabel(key)
    for _, s in ipairs(ns.SoundChoices()) do
        if s.key == key then return s.label end
    end
    return "None"
end

local function UpdateListLabel()
    if not listLabel then return end
    local shown = ns.ShownList()
    if shown then
        listLabel:SetText(shown)
        listLabel:SetTextColor(unpack(C.text))
    else
        listLabel:SetText(#ns.ListNames() > 0 and "(unsaved)" or "(none saved)")
        listLabel:SetTextColor(unpack(C.muted))
    end
end

local function PaintTile(t)
    local selected = t.index == ns.db.icon
    t:SetBackdropColor(unpack(t.hovered and C.hover or C.panel))
    t:SetBackdropBorderColor(unpack(selected and C.accent or C.border))
    t.icon:SetAlpha((selected or t.hovered) and 1 or 0.55)
end

--------------------------------------------------------------------------------
-- Picker: a small menu under a button, shared by every row's marker and sound
-- buttons. Entries are { label, icon?, checked?, onClick }. A click outside
-- it or clicking its button again closes it. It closes with the window, so
-- Escape (which closes the window) closes it too.

local picker
local PICK_W, PICK_H = 170, 20

local function BuildPicker()
    picker = CreateFrame("Frame", "NpcSonarPicker", UIParent, "BackdropTemplate")
    picker:SetFrameStrata("FULLSCREEN_DIALOG")
    picker:SetClampedToScreen(true)
    picker:SetWidth(PICK_W)
    S.Backdrop(picker, C.bg, C.accent)
    picker:Hide()
    picker.buttons = {}
    picker:SetScript("OnUpdate", function(self)
        if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
            and not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then
            self:Hide()
        end
    end)
end

local function PickerButton(i)
    local b = picker.buttons[i]
    if b then return b end
    b = CreateFrame("Button", nil, picker, "BackdropTemplate")
    b:SetSize(PICK_W - 8, PICK_H)
    b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * PICK_H)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    b:SetBackdropColor(0, 0, 0, 0)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT", 4, 0)
    b.label = S.Font(b, 12, C.text)
    b.label:SetPoint("LEFT", 26, 0)
    b:SetScript("OnEnter", function(self) self:SetBackdropColor(unpack(C.hover)) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropColor(0, 0, 0, 0) end)
    picker.buttons[i] = b
    return b
end

local function OpenPicker(owner, entries)
    if not picker then BuildPicker() end
    if picker:IsShown() and picker.owner == owner then
        picker:Hide()
        return
    end
    picker.owner = owner
    for i, e in ipairs(entries) do
        local b = PickerButton(i)
        b.icon:SetShown(e.icon ~= nil)
        if e.icon then b.icon:SetTexture(e.icon) end
        b.label:SetText(e.label)
        b.label:SetTextColor(unpack(e.checked and C.accent or C.text))
        b:SetScript("OnClick", function()
            picker:Hide()
            e.onClick()
        end)
        b:Show()
    end
    for i = #entries + 1, #picker.buttons do picker.buttons[i]:Hide() end
    picker:SetHeight(#entries * PICK_H + 8)
    picker:ClearAllPoints()
    picker:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -2)
    picker:Show()
end

--------------------------------------------------------------------------------
-- NPC rows

-- Refresh never overwrites a focused box, so anything that changes rows
-- under the user (removing one, loading a list, Target) lets go of focus
-- first; otherwise a box would keep showing, and then write back, the text
-- of a row that has moved.
local function ClearRowFocus()
    for _, w in ipairs(rows) do w.box:ClearFocus() end
end

local function RowChanged()
    ns.Refresh()
    ns.RowsChanged()
end

local function MarkerEntries(i)
    local row = Npcs()[i]
    local list = {
        {
            label = ("Default (%s)"):format(ns.ICON_NAMES[ns.db.icon]),
            icon = ns.IconPath(ns.db.icon),
            checked = row.icon == nil,
            onClick = function() row.icon = nil; RowChanged() end,
        },
    }
    for icon = 8, 1, -1 do  -- skull first, as in the tiles
        list[#list + 1] = {
            label = ns.ICON_NAMES[icon],
            icon = ns.IconPath(icon),
            checked = row.icon == icon,
            onClick = function() row.icon = icon; RowChanged() end,
        }
    end
    return list
end

-- Picking a sound plays it, so you hear what you chose.
local function SoundEntries(i)
    local row = Npcs()[i]
    local list = {
        {
            label = ("Default (%s)"):format(SoundLabel(ns.db.sound)),
            checked = row.sound == nil,
            onClick = function()
                row.sound = nil
                ns.PlayAlertSound()
                RowChanged()
            end,
        },
    }
    for _, s in ipairs(ns.SoundChoices()) do
        list[#list + 1] = {
            label = s.label,
            checked = row.sound == s.key,
            onClick = function()
                row.sound = s.key
                ns.PlayAlertSound(s.key)
                RowChanged()
            end,
        }
    end
    return list
end

local function PaintRow(w, row)
    local own = row.icon ~= nil
    w.marker.icon:SetTexture(ns.IconPath(row.icon or ns.db.icon))
    w.marker.icon:SetAlpha(own and 1 or 0.4)
    w.marker:SetBackdropBorderColor(unpack(own and C.accent or C.border))
    local ownSound = row.sound ~= nil
    w.sound.icon:SetVertexColor(unpack(ownSound and C.accent or C.muted))
    w.sound:SetBackdropBorderColor(unpack(ownSound and C.accent or C.border))
end

local function SmallButton(parent, size)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(size, size)
    S.Backdrop(b, C.panel)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 4, -4)
    b.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    b:HookScript("OnEnter", function(self) self:SetBackdropColor(unpack(C.hover)) end)
    b:HookScript("OnLeave", function(self) self:SetBackdropColor(unpack(C.panel)) end)
    return b
end

local function BuildRow(i)
    local w = CreateFrame("Frame", nil, rowsArea)
    w:SetHeight(ROW_H)
    w:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_H + ROW_GAP))
    w:SetPoint("RIGHT", rowsArea, "RIGHT")

    w.remove = S.Button(w, "x", 22, ROW_H)
    w.remove:SetPoint("RIGHT")
    w.sound = SmallButton(w, ROW_H)
    w.sound:SetPoint("RIGHT", w.remove, "LEFT", -4, 0)
    w.sound.icon:SetTexture(SPEAKER)
    w.marker = SmallButton(w, ROW_H)
    w.marker:SetPoint("RIGHT", w.sound, "LEFT", -4, 0)

    w.box = S.Input(w, 1, ROW_H, i == 1 and "NPC name, e.g. Grimtooth" or "Another NPC")
    w.box:SetPoint("LEFT")
    w.box:SetPoint("RIGHT", w.marker, "LEFT", -6, 0)
    w.box:HookScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        Npcs()[i].name = self:GetText()
        UpdateListLabel()
    end)
    w.box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        ns.Start()
    end)
    w.box:SetScript("OnTabPressed", function()
        local nextRow = rows[i + 1]
        if nextRow and nextRow:IsShown() then nextRow.box:SetFocus() else rows[1].box:SetFocus() end
    end)

    w.marker:SetScript("OnClick", function(self) OpenPicker(self, MarkerEntries(i)) end)
    w.marker:HookScript("OnEnter", function(self)
        local row = Npcs()[i]
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(row.icon and ("Marker: " .. ns.ICON_NAMES[row.icon])
            or ("Marker: default (" .. ns.ICON_NAMES[ns.db.icon] .. ")"))
        GameTooltip:AddLine("Click to choose this NPC's marker", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    w.marker:HookScript("OnLeave", GameTooltip_Hide)

    w.sound:SetScript("OnClick", function(self) OpenPicker(self, SoundEntries(i)) end)
    w.sound:HookScript("OnEnter", function(self)
        local row = Npcs()[i]
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(row.sound and ("Alert sound: " .. SoundLabel(row.sound))
            or ("Alert sound: default (" .. SoundLabel(ns.db.sound) .. ")"))
        GameTooltip:AddLine("Click to choose this NPC's alert sound", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    w.sound:HookScript("OnLeave", GameTooltip_Hide)

    w.remove:SetScript("OnClick", function()
        if picker then picker:Hide() end
        ClearRowFocus()
        local npcs = Npcs()
        table.remove(npcs, i)
        Npcs()  -- keeps one empty row when the last is removed
        ns.Refresh()
    end)
    Tooltip(w.remove, "Remove this NPC")

    rows[i] = w
    return w
end

-- Shows one row per NPC and sizes the window to fit.
local function LayoutRows()
    local n = math.min(#Npcs(), MAX_ROWS)
    for i = 1, math.max(n, #rows) do
        local w = rows[i] or (i <= n and BuildRow(i))
        if w then w:SetShown(i <= n) end
    end
    local rowsHeight = n * ROW_H + (n - 1) * ROW_GAP
    rowsArea:SetHeight(rowsHeight)
    frame:SetHeight(topHeight + rowsHeight + lowerHeight + 30 + PAD)
end

--------------------------------------------------------------------------------

local function Build()
    frame = CreateFrame("Frame", "NpcSonarFrame", UIParent, "BackdropTemplate")
    frame:SetWidth(WIDTH)  -- height follows the rows; see LayoutRows
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
    frame:SetScript("OnHide", function() if picker then picker:Hide() end end)
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

    -- The version from the .toc, small and muted after the title.
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = getMeta and getMeta(ADDON, "Version")
    local versionText = S.Font(header, 10, C.muted)
    versionText:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 5, 1)
    versionText:SetText(version and ("v" .. version) or "")

    stateDot = header:CreateTexture(nil, "ARTWORK")
    stateDot:SetSize(6, 6)
    stateDot:SetPoint("LEFT", title, "RIGHT", 10 + versionText:GetStringWidth() + 5, 0)
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

    -- Rows are stacked from the top with a running offset: Row(height, gapAfter)
    -- returns the row's top and moves the cursor below it. The part above the
    -- NPC rows is laid out on the window, the part below on `lower`, which
    -- hangs under the rows and moves with them.
    local y = -46
    local function Row(height, gapAfter)
        local top = y
        y = y - height - (gapAfter or 0)
        return top
    end

    -- Saved lists: < name > stepper that loads, plus Save and Del ---------------
    local listCap = S.Caption(frame, "Saved lists")
    listCap:SetPoint("TOPLEFT", PAD, Row(14))

    local listY = Row(26, 14)
    local listPrev = S.Button(frame, "<", 28, 26)
    listPrev:SetPoint("TOPLEFT", PAD, listY)
    local listDel = S.Button(frame, "Del", 40, 26)
    listDel:SetPoint("TOPRIGHT", -PAD, listY)
    local listSave = S.Button(frame, "Save", 48, 26)
    listSave:SetPoint("RIGHT", listDel, "LEFT", -4, 0)
    local listNext = S.Button(frame, ">", 28, 26)
    listNext:SetPoint("RIGHT", listSave, "LEFT", -6, 0)

    local listBox = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    listBox:SetPoint("TOPLEFT", listPrev, "TOPRIGHT", 4, 0)
    listBox:SetPoint("BOTTOMRIGHT", listNext, "BOTTOMLEFT", -4, 0)
    S.Backdrop(listBox, C.panel)
    listLabel = S.Font(listBox, 12, C.text)
    listLabel:SetPoint("LEFT", 8, 0)
    listLabel:SetPoint("RIGHT", -8, 0)
    listLabel:SetWordWrap(false)

    listPrev:SetScript("OnClick", function() ClearRowFocus(); ns.StepList(-1) end)
    listNext:SetScript("OnClick", function() ClearRowFocus(); ns.StepList(1) end)
    listSave:SetScript("OnClick", function()
        ClearRowFocus()
        ns.PromptSaveList()
    end)
    listDel:SetScript("OnClick", function()
        local shown = ns.ShownList()
        if shown then ns.ConfirmDeleteList(shown) end
    end)
    Tooltip(listPrev, "Load the previous saved list (replaces the NPCs below)")
    Tooltip(listNext, "Load the next saved list (replaces the NPCs below)")
    Tooltip(listSave, "Save the NPCs below, with their markers and sounds, as a list")
    Tooltip(listDel, "Delete the list shown")

    -- NPC rows -----------------------------------------------------------------
    local npcCap = S.Caption(frame, "NPCs")
    npcCap:SetPoint("TOPLEFT", PAD, Row(14))

    rowsArea = CreateFrame("Frame", nil, frame)
    rowsArea:SetPoint("TOPLEFT", PAD, y)
    rowsArea:SetPoint("TOPRIGHT", -PAD, y)
    topHeight = -y

    -- Everything below the rows -------------------------------------------------
    local lower = CreateFrame("Frame", nil, frame)
    lower:SetPoint("TOPLEFT", rowsArea, "BOTTOMLEFT", 0, -ROW_GAP)
    lower:SetPoint("TOPRIGHT", rowsArea, "BOTTOMRIGHT", 0, -ROW_GAP)
    y = 0

    local addY = Row(26, 14)
    addBtn = S.Button(lower, "+ Add NPC", 96, 26)
    addBtn:SetPoint("TOPLEFT", 0, addY)
    addBtn:SetScript("OnClick", function()
        local npcs = Npcs()
        if #npcs >= MAX_ROWS then return end
        npcs[#npcs + 1] = { name = "" }
        ns.Refresh()
        rows[#npcs].box:SetFocus()
    end)
    Tooltip(addBtn, ("Look for another NPC (up to %d)"):format(MAX_ROWS))

    local targetBtn = S.Button(lower, "Target", 64, 26)
    targetBtn:SetPoint("TOPRIGHT", 0, addY)
    Tooltip(targetBtn, "Add your current target's name\n(fills the first empty row)")
    targetBtn:SetScript("OnClick", function()
        local name = ns.Clean(UnitName("target"))
        if type(name) ~= "string" then
            ns.Print("Target an NPC first.")
            return
        end
        local npcs = Npcs()
        for _, r in ipairs(npcs) do
            if strtrim(r.name or ""):lower() == name:lower() then
                ns.Print(name .. " is already in the list.")
                return
            end
        end
        local slot
        for i, r in ipairs(npcs) do
            if strtrim(r.name or "") == "" then slot = i; break end
        end
        if not slot then
            if #npcs >= MAX_ROWS then
                ns.Print(("Up to %d NPCs; remove one first."):format(MAX_ROWS))
                return
            end
            slot = #npcs + 1
            npcs[slot] = {}
        end
        npcs[slot].name = name
        ClearRowFocus()
        ns.Refresh()
    end)

    -- Marker tiles -------------------------------------------------------------
    local markCap = S.Caption(lower, "Default marker")
    markCap:SetPoint("TOPLEFT", 0, Row(14))

    local tileSize, gap = 32, 5
    local tilesY = Row(tileSize, 14)
    for slot = 1, 8 do
        local i = 9 - slot -- skull first
        local t = CreateFrame("Button", nil, lower, "BackdropTemplate")
        t:SetSize(tileSize, tileSize)
        t:SetPoint("TOPLEFT", (slot - 1) * (tileSize + gap), tilesY)
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
            GameTooltip:AddLine("For NPCs whose marker is Default", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        t:SetScript("OnLeave", function(self)
            self.hovered = false; PaintTile(self)
            GameTooltip:Hide()
        end)
        tiles[i] = t
    end

    -- Options ------------------------------------------------------------------
    partialToggle = S.Toggle(lower, "Partial name match", function(on)
        ns.db.partial = on
        ns.UpdateMarkButton()
    end)
    partialToggle:SetPoint("TOPLEFT", 0, Row(18, 6))
    Tooltip(partialToggle, "Match any NPC whose name contains the text")

    friendlyToggle = S.Toggle(lower, "Show friendly NPC nameplates while scanning", function(on)
        ns.db.friendlyPlates = on
        ns.UpdatePinning()
    end)
    friendlyToggle:SetPoint("TOPLEFT", 0, Row(18, 6))
    Tooltip(friendlyToggle, "Friendly NPCs (quest givers, vendors) only get a nameplate when\n"
        .. "friendly NPC nameplates are on, and without one they are only found\n"
        .. "under the mouse or as your target. Turns them on during the scan\n"
        .. "and puts your setting back when it stops.")

    pinToggle = S.Toggle(lower, "Keep target's nameplate on screen", function(on)
        ns.db.pinTarget = on
        ns.UpdatePinning()
    end)
    pinToggle:SetPoint("TOPLEFT", 0, Row(18, 6))
    Tooltip(pinToggle, "While scanning, your target's nameplate stays at the screen edge\n"
        .. "when it is behind you or off to the side. Changes game settings\n"
        .. "during the scan and puts yours back when it stops.")

    deathToggle = S.Toggle(lower, "Stop looking for an NPC once it dies", function(on)
        ns.db.doneOnDeath = on
    end)
    deathToggle:SetPoint("TOPLEFT", 0, Row(18, 6))
    Tooltip(deathToggle, "When a found NPC dies, drop its name from this scan.\n"
        .. "The scan stops once every name is done.")

    radarToggle = S.Toggle(lower, "Track rares on the minimap with an arrow", function(on)
        ns.db.radar = on
        ns.RadarScan()
    end)
    radarToggle:SetPoint("TOPLEFT", 0, Row(18, 6))
    Tooltip(radarToggle, "Rares and other special NPCs show on the minimap long before\n"
        .. "they get a nameplate. When one matches, you are alerted and an\n"
        .. "arrow points at it with the distance. Drag the arrow to move it.\n"
        .. "Inside instances it can only alert, without the arrow.")

    waypointToggle = S.Toggle(lower, "Set a map waypoint on rares it finds", function(on)
        ns.db.waypoint = on
    end)
    waypointToggle:SetPoint("TOPLEFT", 0, Row(18, 12))
    Tooltip(waypointToggle, "When the radar detects a match, put a map waypoint on it.\n"
        .. "A waypoint you placed yourself is left alone.")

    -- Default sound: < name > stepper. Every step plays the sound so you hear
    -- what you picked; clicking the name plays it again.
    local soundCap = S.Caption(lower, "Default sound")
    soundCap:SetPoint("TOPLEFT", 0, Row(14))

    local soundY = Row(26, 12)
    local prevBtn = S.Button(lower, "<", 28, 26)
    prevBtn:SetPoint("TOPLEFT", 0, soundY)
    local nextBtn = S.Button(lower, ">", 28, 26)
    nextBtn:SetPoint("TOPRIGHT", 0, soundY)

    local soundBox = CreateFrame("Button", nil, lower, "BackdropTemplate")
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
        GameTooltip:AddLine("For NPCs whose sound is Default", 0.7, 0.7, 0.7)
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
    -- Three lines at 11pt: the "Found" line plus a hint that wraps once.
    local statusY = Row(60, 12)
    local statusPanel = CreateFrame("Frame", nil, lower, "BackdropTemplate")
    statusPanel:SetPoint("TOPLEFT", 0, statusY)
    statusPanel:SetPoint("TOPRIGHT", 0, statusY)
    statusPanel:SetHeight(60)
    S.Backdrop(statusPanel, C.panel)

    statusText = S.Font(statusPanel, 11, C.text)
    statusText:SetPoint("TOPLEFT", 10, -8)
    statusText:SetPoint("BOTTOMRIGHT", -10, 6)
    statusText:SetJustifyH("LEFT")
    statusText:SetJustifyV("TOP")
    statusText:SetWordWrap(true)

    -- Last sighting: Waypoint / Share / Log ------------------------------------
    local third = (WIDTH - PAD * 2 - 8) / 3
    local sightY = Row(26, 12)
    local wpBtn = S.Button(lower, "Waypoint", third, 26)
    wpBtn:SetPoint("TOPLEFT", 0, sightY)
    wpBtn:SetScript("OnClick", function() ns.WaypointLatest() end)
    Tooltip(wpBtn, "Put a map waypoint on the latest sighting")
    local shareBtn = S.Button(lower, "Share", third, 26)
    shareBtn:SetPoint("LEFT", wpBtn, "RIGHT", 4, 0)
    shareBtn:SetScript("OnClick", function() ns.ShareLatest() end)
    Tooltip(shareBtn, "Post the latest sighting to your group, or your guild if solo")
    local logBtn = S.Button(lower, "Log", third, 26)
    logBtn:SetPoint("LEFT", shareBtn, "RIGHT", 4, 0)
    logBtn:SetScript("OnClick", function() ns.PrintSightings() end)
    Tooltip(logBtn, "Print where each name was last seen (/npcsonar log)")

    lowerHeight = ROW_GAP - y
    lower:SetHeight(lowerHeight)

    -- Actions ------------------------------------------------------------------
    local half = (WIDTH - PAD * 2 - 8) / 2
    startBtn = S.Button(frame, "Start scan", half, 30, "primary")
    startBtn:SetPoint("BOTTOMLEFT", PAD, PAD)
    startBtn:SetScript("OnClick", function()
        ClearRowFocus()
        ns.Start()
    end)

    stopBtn = S.Button(frame, "Stop", half, 30, "secondary")
    stopBtn:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    stopBtn:SetScript("OnClick", function() ns.Stop() end)

    LayoutRows()
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

    LayoutRows()
    local npcs = Npcs()
    for i, w in ipairs(rows) do
        local row = npcs[i]
        if row and w:IsShown() then
            if not w.box:HasFocus() then w.box:SetText(row.name or "") end
            PaintRow(w, row)
        end
    end
    addBtn:SetEnabled(#npcs < MAX_ROWS)

    for _, t in pairs(tiles) do PaintTile(t) end
    partialToggle:SetChecked(ns.db.partial)
    friendlyToggle:SetChecked(ns.db.friendlyPlates)
    pinToggle:SetChecked(ns.db.pinTarget)
    deathToggle:SetChecked(ns.db.doneOnDeath)
    radarToggle:SetChecked(ns.db.radar)
    waypointToggle:SetChecked(ns.db.waypoint)
    UpdateListLabel()
    soundLabel:SetText(SoundLabel(ns.db.sound))
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
