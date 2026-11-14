--------------------------------------------------------------------------------
-- NPC Sonar -- scanning for a quest's NPCs
--
-- No API maps a quest to the NPCs it needs, but the client knows which units
-- belong to the quests in your log: that is how quest icons get onto
-- nameplates and quest lines into unit tooltips. C_TooltipInfo.GetUnit hands
-- those tooltip lines to addons. A QuestTitle line names a quest (its `id` is
-- the quest ID) and the QuestObjective lines after it are that unit's
-- objectives, each with a `completed` flag. So a unit is wanted for a tracked
-- quest when its tooltip has that quest's title line and at least one of the
-- objectives under it is still open, or none are listed (a talk-to NPC).
--
-- C_QuestLog.UnitIsRelatedToActiveQuest is a cheap first filter, where the
-- client has it, and tooltip answers are cached per GUID for a moment and
-- dropped whenever the quest log changes.
--
-- Picked quests are NpcSonarDB.quests, a list of quest IDs the player chose
-- with the quest log button. The automatic mode (NpcSonarDB.questMode: "off",
-- "zone" or "all") adds the other quests in the log, or those on the current
-- map, to `auto`. It is rebuilt from the quest log as quests come and go, and
-- keeps a scan running while it has quests (unless the player pressed Stop).
-- Automatic quests are quieter: a chat line instead of the full alert, and
-- their names give way to picked quests' names in the badge macro.
--
-- Both kinds are scanned for alongside the NPC rows; their entries in the scan
-- ("wanted entries") are "quest:<id>" strings, so they never collide with a
-- lowercase NPC name.
--
-- Raid markers: the badge's macro targets by name, and a quest row has no
-- names until the scan finds its NPCs. Names found for a quest are added to
-- the macro as they turn up (ns.QuestNames), so a click marks them too.
--------------------------------------------------------------------------------

local _, ns = ...

local LineType = Enum and Enum.TooltipDataLineType
local LINE_QUEST_OBJECTIVE = LineType and LineType.QuestObjective or 8
local LINE_QUEST_TITLE     = LineType and LineType.QuestTitle or 17

local CACHE_TTL = 2          -- seconds a unit's quest answer is reused
local MAX_NAMES_PER_QUEST = 6 -- learned names kept per quest for the badge macro
local MAX_NAMES = 8           -- and in all, so the macro stays short

local supported = C_TooltipInfo ~= nil and C_TooltipInfo.GetUnit ~= nil

local cache = {}            -- GUID -> { want = entry or false, t = GetTime() }
local learned = {}          -- wanted entry -> list of NPC names found for it
local learnedList = {}      -- all learned names in the order found, for the macro
local auto = {}             -- quest IDs the automatic mode covers, minus picked ones
local paused = false        -- the player pressed Stop: no automatic scan until one starts

-- The picked quests.
local function Quests()
    ns.db.quests = ns.db.quests or {}
    return ns.db.quests
end

local function IsPicked(id)
    return tContains(Quests(), id)
end
ns.IsPickedQuest = IsPicked

-- Every quest scanned for: the picked ones, then the automatic ones.
local function Tracked()
    local list = {}
    for _, id in ipairs(Quests()) do list[#list + 1] = id end
    for _, id in ipairs(auto) do list[#list + 1] = id end
    return list
end

function ns.QuestSupported()
    return supported
end

function ns.QuestWant(id)
    return "quest:" .. id
end

-- The quest ID of a wanted entry, or nil for an NPC name.
local function QuestIDOf(want)
    local id = type(want) == "string" and want:match("^quest:(%d+)$")
    return id and tonumber(id)
end

function ns.IsQuestWant(want)
    return QuestIDOf(want) ~= nil
end

function ns.HasQuests()
    return supported and (#Quests() > 0 or #auto > 0)
end

function ns.IsTrackingQuest(id)
    return IsPicked(id) or tContains(auto, id)
end

-- "quests in this zone", for the automatic mode's chat and tooltip lines.
local function AutoScope()
    return ns.db.questMode == "zone" and "in this zone" or "in your log"
end

local function CountText(n)
    return n == 1 and "1 quest" or (n .. " quests")
end

local function Title(id)
    local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    return title or ("quest " .. id)
end
ns.QuestTitle = Title

-- "Quest: Wanted: Hogger, Quest: The Fargodeep Mine, 5 quests in this zone",
-- for tooltips and chat. Automatic quests are counted, not listed.
function ns.QuestTitlesText()
    if not supported then return "" end
    local parts = {}
    for _, id in ipairs(Quests()) do
        parts[#parts + 1] = "Quest: " .. Title(id)
    end
    if #auto > 0 then
        parts[#parts + 1] = CountText(#auto) .. " " .. AutoScope()
    end
    return table.concat(parts, ", ")
end

-- Names found for tracked quests this scan, for the badge macro.
function ns.QuestNames()
    return learnedList
end

--------------------------------------------------------------------------------
-- Matching

-- The tracked quest a QuestTitle line names, or nil. The line's `id` is the
-- quest ID; its text is compared too, in case a client leaves `id` out.
local function TrackedFromTitleLine(line)
    local id = ns.Clean(line.id)
    if id and ns.IsTrackingQuest(id) then return id end
    local text = ns.Clean(line.leftText)
    if type(text) ~= "string" then return nil end
    for _, q in ipairs(Tracked()) do
        if Title(q) == text then return q end
    end
    return nil
end

-- Whether an objective line is still open. `completed` says so where the
-- client provides it; otherwise "3/8 Gnolls" style text is read.
local function ObjectiveOpen(line)
    local completed = ns.Clean(line.completed)
    if completed ~= nil then return not completed end
    local text = ns.Clean(line.leftText)
    if type(text) == "string" then
        local have, need = text:match("(%d+)%s*/%s*(%d+)")
        if have then return tonumber(have) < tonumber(need) end
    end
    return true
end

-- The wanted entry of the first tracked quest this unit is still needed for.
local function QuestOfUnit(unit)
    local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end

    local quest, open, objectives
    local function Finish()
        if quest and (open or objectives == 0) then return ns.QuestWant(quest) end
        return nil
    end
    for _, line in ipairs(data.lines) do
        local t = ns.Clean(line.type)
        if t == LINE_QUEST_TITLE then
            local found = Finish()
            if found then return found end
            quest, open, objectives = TrackedFromTitleLine(line), false, 0
        elseif t == LINE_QUEST_OBJECTIVE then
            if quest then
                objectives = objectives + 1
                if ObjectiveOpen(line) then open = true end
            end
        end
    end
    return Finish()
end

-- Learned names seen during one scan pass, split by whether any unit with
-- that name was still needed. Two NPCs can share a name with only one still
-- needed (one wounded soldier helped, the next not), so a name is dropped
-- only when every unit with it seen in the pass is no longer needed.
local seenNeeded, seenDone = {}, {}

local function NoteSeen(unit, needed)
    if #learnedList == 0 then return end
    local name = ns.Clean(UnitName(unit))
    if type(name) ~= "string" or not tContains(learnedList, name) then return end
    if needed then seenNeeded[name] = true else seenDone[name] = true end
end

-- Whether a learned name was found for a picked quest (not only automatic ones).
local function PickedName(name)
    for _, id in ipairs(Quests()) do
        if tContains(learned[ns.QuestWant(id)] or {}, name) then return true end
    end
    return false
end

-- Drops a learned name from the macro and from every quest it was found for.
local function DropName(name)
    tDeleteItem(learnedList, name)
    for _, names in pairs(learned) do tDeleteItem(names, name) end
end

-- Called by Core at the end of each scan pass. A learned name whose NPCs no
-- longer count for any tracked quest (their objective is done) leaves the
-- badge macro, so a click stops targeting it. Only names of picked quests are
-- mentioned in chat; the automatic mode stays quiet.
function ns.QuestPassDone()
    local changed = false
    for name in pairs(seenDone) do
        if not seenNeeded[name] and tContains(learnedList, name) then
            local picked = PickedName(name)
            DropName(name)
            if picked then
                ns.Print(("No longer tracking |cffffd100%s|r: no tracked quest needs it now."):format(name))
            end
            changed = true
        end
    end
    wipe(seenNeeded)
    wipe(seenDone)
    if changed then ns.UpdateMarkButton() end
end

local function Lookup(unit)
    if C_QuestLog.UnitIsRelatedToActiveQuest then
        local ok, related = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
        if ok and ns.Clean(related) == false then return nil end
    end
    local guid = ns.Clean(UnitGUID(unit))
    local now = GetTime()
    local hit = guid and cache[guid]
    if hit and now - hit.t < CACHE_TTL then return hit.want or nil end
    local want = QuestOfUnit(unit)
    if guid then cache[guid] = { want = want or false, t = now } end
    return want
end

-- The wanted entry for a living NPC unit that a tracked quest needs, or nil.
-- Core calls it for units no NPC name matched.
function ns.QuestMatch(unit)
    if not ns.HasQuests() then return nil end
    local want = Lookup(unit)
    NoteSeen(unit, want ~= nil)
    return want
end

-- Remembers an NPC name found for a quest, so the badge can target it.
-- Returns true when the name is new. When the macro is full, a picked quest's
-- name takes the place of the oldest name only automatic quests found.
function ns.LearnQuestName(name, want)
    local names = learned[want]
    if not names then names = {}; learned[want] = names end
    if tContains(names, name) or #names >= MAX_NAMES_PER_QUEST then return false end
    local picked = IsPicked(QuestIDOf(want))
    if #learnedList >= MAX_NAMES and not tContains(learnedList, name) then
        if not picked then return false end
        local evict
        for _, n in ipairs(learnedList) do
            if not PickedName(n) then evict = n; break end
        end
        if not evict then return false end
        DropName(evict)
    end
    names[#names + 1] = name
    if not tContains(learnedList, name) then learnedList[#learnedList + 1] = name end
    if picked then
        ns.Print(("Tracking |cffffd100%s|r for %s."):format(name, Title(QuestIDOf(want))))
    end
    return true
end

-- Adds what each tracked quest is scanning for to a tooltip: the quest, its
-- open objectives (which name the NPCs to expect) and the NPCs found for it
-- so far, which are the ones the badge targets. `onlyID` limits it to one
-- quest. Automatic quests are listed only once something was found for them;
-- the rest are counted on one line, so a full quest log stays readable.
function ns.AddQuestTrackingLines(tooltip, onlyID)
    if not supported then return end
    local function AddQuest(id)
        tooltip:AddLine(" ")
        tooltip:AddLine("Quest: " .. Title(id), 1, 0.82, 0)
        local objectives = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id)
        for _, o in ipairs(objectives or {}) do
            if not o.finished and o.text and o.text ~= "" then
                tooltip:AddLine("  " .. o.text, 0.75, 0.75, 0.75)
            end
        end
        local names = learned[ns.QuestWant(id)]
        if names and #names > 0 then
            tooltip:AddLine("  Tracking: " .. table.concat(names, ", "), 0.32, 0.85, 0.48, true)
        else
            tooltip:AddLine("  Tracking: none seen yet", 0.55, 0.57, 0.63)
        end
    end
    local quiet = 0
    for _, id in ipairs(Tracked()) do
        if onlyID then
            if id == onlyID then AddQuest(id) end
        elseif IsPicked(id) or #(learned[ns.QuestWant(id)] or {}) > 0 then
            AddQuest(id)
        else
            quiet = quiet + 1
        end
    end
    if quiet > 0 then
        tooltip:AddLine(" ")
        tooltip:AddLine(("%s %s, none seen yet"):format(
            quiet == #auto and CountText(quiet) or ("Plus " .. CountText(quiet)), AutoScope()),
            0.55, 0.57, 0.63)
    end
end

--------------------------------------------------------------------------------
-- The automatic mode

-- Quest IDs in the log that the automatic mode covers: no headers, hidden or
-- emissary entries, nothing already complete, and with `zoneOnly` only quests
-- the game places on the current map. Older clients without C_QuestLog.GetInfo
-- list quests under zone headers instead (quests under a collapsed header
-- aren't listed there).
local function QuestLogIDs(zoneOnly)
    local ids = {}
    local function Add(id)
        if id and id ~= 0 and not tContains(ids, id)
            and not (C_QuestLog.IsComplete and C_QuestLog.IsComplete(id)) then
            ids[#ids + 1] = id
        end
    end
    if C_QuestLog.GetInfo and C_QuestLog.GetNumQuestLogEntries then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and not info.isHidden and not info.isBounty
                and (not zoneOnly or info.isOnMap) then
                Add(info.questID)
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        local zone = GetRealZoneText and GetRealZoneText()
        local header
        for i = 1, GetNumQuestLogEntries() do
            local title, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
            if isHeader then
                header = title
            elseif not zoneOnly or header == zone then
                Add(id)
            end
        end
    end
    return ids
end

-- Forgets what was found for a quest: its names leave the macro unless
-- another quest found them too, and it may be announced again.
local function ForgetFound(id)
    local want = ns.QuestWant(id)
    local names = learned[want] or {}
    learned[want] = nil
    for _, name in ipairs(names) do
        local other = false
        for _, list in pairs(learned) do
            if tContains(list, name) then other = true; break end
        end
        if not other then tDeleteItem(learnedList, name) end
    end
    ns.ForgetQuestAlert(want)
end

-- Rebuilds `auto` from the quest log. Returns true when it changed.
local function UpdateAuto()
    local mode = supported and ns.db.questMode or "off"
    local ids = mode == "off" and {} or QuestLogIDs(mode == "zone")
    local new = {}
    for _, id in ipairs(ids) do
        if not IsPicked(id) then new[#new + 1] = id end
    end
    local changed = #new ~= #auto
    for _, id in ipairs(auto) do
        if not tContains(new, id) then
            changed = true
            if not IsPicked(id) then ForgetFound(id) end
        end
    end
    auto = new
    return changed
end

-- Called when a scan starts: forget what the last scan found, drop picked
-- quests that left the log while nothing was watching, and end a pause.
function ns.ResetQuests()
    wipe(cache)
    wipe(learned)
    wipe(learnedList)
    paused = false
    if not supported then return end
    local list = Quests()
    for i = #list, 1, -1 do
        if not C_QuestLog.IsOnQuest(list[i]) then table.remove(list, i) end
    end
    UpdateAuto()
end

-- Called by Core when the player stops the scan. The automatic mode waits
-- for them to start one again, instead of starting a new scan at once.
function ns.PauseAutoQuests()
    if paused or not supported or ns.db.questMode == "off" then return end
    paused = true
    ns.Print("Automatic quest scan paused. Start a scan to resume it.")
end

--------------------------------------------------------------------------------
-- Adding and removing quests

local RefreshQuestButtons -- defined below

-- Brings `auto` up to date with the quest log and the scan up to date with
-- it: a running scan rescans or, with nothing left, stops; an idle one starts
-- for the automatic quests, unless paused. Started that way it looks for
-- quests only, not the window's NPC rows.
local function Sync()
    if not (ns.db and supported) then return end
    local changed = UpdateAuto()
    if ns.scanning then
        if #ns.WantedNames() == 0 and not ns.HasQuests() then
            ns.Stop()
        elseif changed then
            wipe(cache)
            ns.Rescan()
            ns.Refresh()
        end
    elseif #auto > 0 and not paused then
        ns.Start(nil, true)
    end
    RefreshQuestButtons()
end

function ns.SetQuestMode(mode)
    if ns.db.questMode == mode then return end
    ns.db.questMode = mode
    paused = false
    if not supported then return end
    Sync()
    if mode == "off" then
        ns.Print("Automatic quest scan off.")
    else
        ns.Print(("Automatic quest scan: %s %s."):format(CountText(#auto), AutoScope()))
    end
    ns.Refresh()
end

local function AfterChange()
    if ns.scanning then
        if #ns.WantedNames() == 0 and not ns.HasQuests() then
            ns.Stop()
        else
            wipe(cache)
            ns.Rescan()
        end
    end
    ns.Refresh()
    RefreshQuestButtons()
end

function ns.TrackQuest(id)
    if not supported then
        ns.Print("Scanning for quest NPCs needs a newer client than this one.")
        return
    end
    if not id or id == 0 then return end
    if not C_QuestLog.IsOnQuest(id) then
        ns.Print("That quest isn't in your quest log, so the game won't say which NPCs it needs.")
        return
    end
    if C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) then
        ns.Print(("|cffffd100%s|r is already complete; no NPCs left to find."):format(Title(id)))
        return
    end
    -- Picking a quest the automatic mode already covers keeps what it found,
    -- but lets it be announced again, now with the full alert.
    if not IsPicked(id) then
        table.insert(Quests(), id)
        if tContains(auto, id) then
            tDeleteItem(auto, id)
            ns.ForgetQuestAlert(ns.QuestWant(id))
        end
        ns.Print(("Scanning for the NPCs of |cffffd100%s|r."):format(Title(id)))
    end
    if ns.scanning then AfterChange() else ns.Start() end
    RefreshQuestButtons()
end

-- A quest the automatic mode covers goes back to it rather than being dropped.
function ns.UntrackQuest(id, why)
    local list = Quests()
    for i, q in ipairs(list) do
        if q == id then
            table.remove(list, i)
            UpdateAuto()
            if tContains(auto, id) then
                ns.Print(("|cffffd100%s|r is back in the automatic quest scan."):format(Title(id)))
            else
                ForgetFound(id)
                ns.Print(("Stopped scanning for |cffffd100%s|r%s."):format(Title(id), why or ""))
            end
            ns.UpdateMarkButton()
            AfterChange()
            return
        end
    end
end

function ns.ToggleQuest(id)
    if IsPicked(id) then ns.UntrackQuest(id) else ns.TrackQuest(id) end
end

-- Drops the picked quests; the automatic mode keeps any it covers.
function ns.ClearQuests()
    if #Quests() == 0 then return end
    for _, id in ipairs(Quests()) do ForgetFound(id) end
    wipe(Quests())
    UpdateAuto()
    ns.UpdateMarkButton()
    ns.Print("Stopped scanning for picked quests.")
    AfterChange()
end

-- Quests that are finished or gone stop being scanned for.
local function CheckQuests(event, questID)
    if not supported then return end
    local list = Quests()
    for i = #list, 1, -1 do
        local id = list[i]
        if (event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN") and id == questID then
            ns.UntrackQuest(id, ", it left your quest log")
        elseif C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) then
            ns.UntrackQuest(id, ", its objectives are done")
        end
    end
end

--------------------------------------------------------------------------------
-- Quest log button

local buttons = {}  -- { button, getQuestID }

local ICON_SEARCH = "Interface\\AddOns\\NpcSonar\\Media\\sonar_search"
local ICON_FOUND  = "Interface\\AddOns\\NpcSonar\\Media\\sonar_found"

-- Idle it is a flat dark button like the window's; while the quest is picked
-- it fills with the sonar blue, so the state reads at a glance. A quest the
-- automatic mode covers shows the found icon on the dark button; a click
-- picks it.
function RefreshQuestButtons()
    for _, b in ipairs(buttons) do
        local id = b.getQuestID()
        local picked = id ~= nil and IsPicked(id)
        local covered = not picked and id ~= nil and ns.IsTrackingQuest(id)
        b:SetLabel(picked and "Stop NPC scan" or covered and "Auto-scanning" or "Scan for NPCs")
        b.icon:SetTexture((picked or covered) and ICON_FOUND or ICON_SEARCH)
        b.kind = picked and "primary" or "secondary"
        b:SetEnabled(id ~= nil and id ~= 0)
        b:Paint()
    end
end

local function MakeButton(parent, getQuestID)
    local b = ns.Style.Button(parent, "Scan for NPCs", 128, 24)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT", 6, 0)
    b.icon:SetTexture(ICON_SEARCH)
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
    b.label:SetPoint("RIGHT", -6, 0)
    b.getQuestID = getQuestID
    local function ShowTooltip(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("NPC Sonar")
        GameTooltip:AddLine("Marks the NPCs this quest still needs on their nameplates\n"
            .. "and alerts you when one is near.\n" .. ns.ClickHint()
            .. "\nto target one and put a raid marker on it.", 1, 1, 1, true)
        local id = getQuestID()
        if id and ns.IsTrackingQuest(id) and not IsPicked(id) then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("The automatic quest scan covers this quest quietly.\n"
                .. "Click to pick it: full alerts, and its NPCs go first on the badge.",
                0.7, 0.7, 0.7, true)
        end
        if id and ns.IsTrackingQuest(id) then ns.AddQuestTrackingLines(GameTooltip, id) end
        GameTooltip:Show()
    end
    b:SetScript("OnClick", function(self)
        local id = getQuestID()
        if id and id ~= 0 then ns.ToggleQuest(id) end
        -- Still under the mouse: redraw the tooltip for the new state.
        if GameTooltip:IsOwned(self) then ShowTooltip(self) end
    end)
    b:HookScript("OnEnter", ShowTooltip)
    b:HookScript("OnLeave", GameTooltip_Hide)
    parent:HookScript("OnShow", RefreshQuestButtons)
    buttons[#buttons + 1] = b
    return b
end

-- Retail: the quest details page in the map's quest log.
local function HookQuestMap()
    local details = QuestMapFrame and QuestMapFrame.DetailsFrame
    if not details or details.npcSonarButton then return details ~= nil end
    local b = MakeButton(details, function()
        return QuestMapFrame_GetDetailQuestID and QuestMapFrame_GetDetailQuestID()
    end)
    -- Top row, right of the Back button: the bottom of the page is taken by
    -- the Rewards panel and the Abandon/Share/Track bar. The gap leaves room
    -- for a small button other addons put beside Back (e.g. a voice-over
    -- speaker).
    local back = details.BackButton
    if back then
        b:SetPoint("LEFT", back, "RIGHT", 44, 0)
    else
        b:SetPoint("TOPRIGHT", details, "TOPRIGHT", -8, -4)
    end
    b:SetFrameLevel(details:GetFrameLevel() + 10)
    details.npcSonarButton = b
    if QuestMapFrame_ShowQuestDetails then
        hooksecurefunc("QuestMapFrame_ShowQuestDetails", RefreshQuestButtons)
    end
    return true
end

-- Classic: the quest log window. The selected quest's ID is the eighth return
-- of GetQuestLogTitle on these clients.
local function HookQuestLog()
    if not QuestLogFrame or QuestLogFrame.npcSonarButton then return QuestLogFrame ~= nil end
    local b = MakeButton(QuestLogFrame, function()
        if C_QuestLog.GetSelectedQuest then
            local id = C_QuestLog.GetSelectedQuest()
            if id and id ~= 0 then return id end
        end
        local index = GetQuestLogSelection and GetQuestLogSelection()
        if not index or index == 0 then return nil end
        return select(8, GetQuestLogTitle(index))
    end)
    b:SetPoint("TOPRIGHT", QuestLogFrame, "TOPRIGHT", -40, -40)
    QuestLogFrame.npcSonarButton = b
    if QuestLog_SetSelection then
        hooksecurefunc("QuestLog_SetSelection", RefreshQuestButtons)
    end
    return true
end

local hooked = false
local function TryHook()
    if hooked or not supported then return end
    -- Retail has both globals' worth of code paths in places; the map's quest
    -- log is the one players see there.
    if QuestMapFrame then
        hooked = HookQuestMap()
    elseif QuestLogFrame then
        hooked = HookQuestLog()
    end
end

--------------------------------------------------------------------------------
-- /npcsonar debug: what the tooltip data says about a unit's quests.

function ns.QuestDebug(unit)
    if not supported then
        ns.Print("quest scan: |cffff4040not supported on this client|r (no C_TooltipInfo)")
        return
    end
    local related = C_QuestLog.UnitIsRelatedToActiveQuest
        and select(2, pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit))
    local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
    local lines = ok and type(data) == "table" and data.lines or {}
    local shown = 0
    for _, line in ipairs(lines) do
        local t = ns.Clean(line.type)
        if t == LINE_QUEST_TITLE or t == LINE_QUEST_OBJECTIVE then
            shown = shown + 1
            ns.Print(("  %s id=%s completed=%s text=%s"):format(
                t == LINE_QUEST_TITLE and "QuestTitle" or "Objective",
                tostring(ns.Clean(line.id)), tostring(ns.Clean(line.completed)),
                tostring(ns.Clean(line.leftText))))
        end
    end
    ns.Print(("%s quest data: related=%s, %d quest lines, tracked match=%s"):format(
        unit, tostring(ns.Clean(related)), shown, tostring(QuestOfUnit(unit))))
end

--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_REMOVED")
events:RegisterEvent("QUEST_TURNED_IN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" or event == "ADDON_LOADED" then
        -- The quest log frames may come from a load-on-demand Blizzard addon.
        TryHook()
        return
    end
    if not ns.db then return end
    -- Objective progress changes which units still count.
    wipe(cache)
    CheckQuests(event, arg1)
    -- New, finished and abandoned quests, and a new zone for the zone mode.
    Sync()
end)
