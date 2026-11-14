--------------------------------------------------------------------------------
-- NPC Sonar -- saved search lists
--
-- A list is a name and a copy of the window's NPC rows, each with its own
-- marker and sound ("Daily rares" -> Grimtooth/skull, Shade of Ashar). They
-- live in NpcSonarDB.lists, keyed by name; NpcSonarDB.currentList is the one
-- last saved or loaded, which the window shows and Save offers as the
-- default name.
--
--   /npcsonar save <name>     save the current rows under <name>
--   /npcsonar load <name>     put a list's rows in the window (restarts a scan)
--   /npcsonar delete <name>   forget a list
--   /npcsonar lists           print them
--------------------------------------------------------------------------------

local _, ns = ...

local function Lists()
    ns.db.lists = ns.db.lists or {}
    return ns.db.lists
end

-- List names, sorted case-insensitively.
function ns.ListNames()
    local names = {}
    for name in pairs(Lists()) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

-- Finds a list by name, ignoring case. Returns its stored name.
local function Find(name)
    name = strtrim(name or ""):lower()
    for stored in pairs(Lists()) do
        if stored:lower() == name then return stored end
    end
    return nil
end

function ns.SaveList(name)
    name = strtrim(name or "")
    if name == "" then
        ns.Print("Give the list a name.")
        return
    end
    if ns.NamesText(ns.db.npcs) == "" then
        ns.Print("Enter some NPC names first.")
        return
    end
    -- Saving under an existing name (in any case) replaces that list.
    local old = Find(name)
    if old then Lists()[old] = nil end
    Lists()[name] = ns.CopyRows(ns.db.npcs)
    ns.db.currentList = name
    ns.Print(("Saved list %q."):format(name))
    ns.Refresh()
end

function ns.LoadList(name)
    local stored = Find(name)
    if not stored then
        ns.Print(("No list called %q. Type /npcsonar lists to see them."):format(name or ""))
        return
    end
    -- Names typed but never saved would be lost; print them so they can be
    -- copied back from chat.
    local typed = ns.NamesText(ns.db.npcs)
    if typed ~= "" and not ns.ShownList() then
        ns.Print("Replaced unsaved names: " .. typed)
    end
    ns.db.npcs = ns.CopyRows(Lists()[stored])
    ns.db.currentList = stored
    if ns.scanning then
        ns.Start()  -- pick up the new names at once
    else
        ns.Refresh()
    end
end

-- The list the window holds unchanged, or nil. Once a row is edited the
-- window no longer holds "that list".
function ns.ShownList()
    local current = ns.db.currentList
    local list = current and Lists()[current]
    if list and ns.RowsKey(list) == ns.RowsKey(ns.db.npcs) then return current end
    return nil
end

function ns.DeleteList(name)
    local stored = Find(name)
    if not stored then
        ns.Print(("No list called %q."):format(name or ""))
        return
    end
    Lists()[stored] = nil
    if ns.db.currentList == stored then ns.db.currentList = nil end
    ns.Print(("Deleted list %q."):format(stored))
    ns.Refresh()
end

function ns.PrintLists()
    local names = ns.ListNames()
    if #names == 0 then
        ns.Print("No saved lists. Save one with /npcsonar save <name>.")
        return
    end
    for _, name in ipairs(names) do
        ns.Print(("|cffffd100%s|r: %s"):format(name, ns.NamesText(Lists()[name])))
    end
end

-- Loads the list `delta` steps from the current one, wrapping around.
function ns.StepList(delta)
    local names = ns.ListNames()
    if #names == 0 then
        ns.Print("No saved lists yet. Click Save to keep the current names.")
        return
    end
    local at = 0
    for i, name in ipairs(names) do
        if name == ns.db.currentList then at = i end
    end
    if at == 0 and delta < 0 then at = 1 end  -- so < from nothing lands on the last
    ns.LoadList(names[(at - 1 + delta) % #names + 1])
end

--------------------------------------------------------------------------------
-- Dialogs. The edit box is reached through GetEditBox where the client has
-- it (newer StaticPopup code) and the editBox field elsewhere. The dialog
-- itself is remembered from OnShow rather than taken from the edit box's
-- parent, which isn't the dialog in every client's popup layout.

local function EditBoxOf(popup)
    return popup.GetEditBox and popup:GetEditBox() or popup.editBox
end

local saveDialog

StaticPopupDialogs["NPCSONAR_SAVE_LIST"] = {
    text = "Save these NPC names as a list called:",
    button1 = SAVE,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 48,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnShow = function(self)
        saveDialog = self
        local box = EditBoxOf(self)
        box:SetText(ns.db.currentList or "")
        box:HighlightText()
    end,
    OnAccept = function(self)
        ns.SaveList(EditBoxOf(self):GetText())
    end,
    EditBoxOnEnterPressed = function(box)
        -- With no name, keep the dialog open to type one.
        if strtrim(box:GetText()) == "" then return end
        ns.SaveList(box:GetText())
        if saveDialog then saveDialog:Hide() end
    end,
    EditBoxOnEscapePressed = function()
        if saveDialog then saveDialog:Hide() end
    end,
}

StaticPopupDialogs["NPCSONAR_DELETE_LIST"] = {
    text = "Delete the saved list \"%s\"?",
    button1 = DELETE,
    button2 = CANCEL,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnAccept = function(_, name)
        ns.DeleteList(name)
    end,
}

function ns.ConfirmDeleteList(name)
    -- The third argument comes back to OnAccept as `data`.
    StaticPopup_Show("NPCSONAR_DELETE_LIST", name, nil, name)
end

function ns.PromptSaveList()
    if ns.NamesText(ns.db.npcs) == "" then
        ns.Print("Enter some NPC names first.")
        return
    end
    StaticPopup_Show("NPCSONAR_SAVE_LIST")
end
