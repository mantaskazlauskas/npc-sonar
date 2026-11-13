--------------------------------------------------------------------------------
-- NPC Sonar -- keep the target's nameplate on screen
--
-- Addons can't place a nameplate themselves (no world-to-screen API, and NPC
-- positions are hidden), but the client can hold off-screen plates at the
-- screen edge. Which console variable does that differs by client:
--
--   Retail (Midnight)  nameplateTargetRadialPosition  1 = target only
--   Classic clients    nameplate{Other,Large}{Top,Bottom}Inset  >= 0 clamps
--                      plates that far inside the edge, -1 lets them leave
--
-- The client is told apart by which CVar exists, not by version checks (see
-- RULE_SETS). A rule is skipped when the player's own setting already does
-- the job, so we never downgrade it.
--
-- The settings are only changed while a scan runs. The player's values are
-- saved in NpcSonarDB.pinBackup first and put back when the scan stops, and
-- again at login in case the game closed mid-scan. A value the player changed
-- themselves while scanning is left alone. CVars can't be changed in combat,
-- so a change requested then waits for PLAYER_REGEN_ENABLED.
--------------------------------------------------------------------------------

local _, ns = ...

local function ReadCVar(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
    return GetCVar(name)
end

local function WriteCVar(name, value)
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    return pcall(set, name, value)
end

local function AtLeast(min)
    return function(v) local n = tonumber(v); return n ~= nil and n >= min end
end

-- Sets of rules, best first. Only the first set whose lead CVar exists is
-- used: the insets move every plate, so they are never applied on a client
-- that has the target-only radial setting, even if it still knows the insets.
local INSET = "0.1"
local RULE_SETS = {
    {
        { cvar = "nameplateTargetRadialPosition", value = "1", ok = AtLeast(1) },
    },
    {
        { cvar = "nameplateOtherTopInset",    value = INSET, ok = AtLeast(0) },
        { cvar = "nameplateOtherBottomInset", value = INSET, ok = AtLeast(0) },
        { cvar = "nameplateLargeTopInset",    value = INSET, ok = AtLeast(0) },
        { cvar = "nameplateLargeBottomInset", value = INSET, ok = AtLeast(0) },
    },
}

local function Rules()
    for _, set in ipairs(RULE_SETS) do
        if ReadCVar(set[1].cvar) ~= nil then return set end
    end
    return {}
end

local waiter = CreateFrame("Frame")

local function Apply()
    local backup = {}
    for _, r in ipairs(Rules()) do
        local cur = ReadCVar(r.cvar)
        if cur ~= nil and not r.ok(cur) and WriteCVar(r.cvar, r.value) then
            backup[r.cvar] = { old = cur, set = r.value }
        end
    end
    ns.db.pinBackup = backup
end

-- An entry is dropped once it is restored or no longer ours to restore. One
-- whose write fails stays in the backup, and so does the backup, so the next
-- UpdatePinning or login tries again.
local function Restore()
    local backup = ns.db.pinBackup
    for cvar, b in pairs(backup) do
        -- Only undo our own change; a value the player set meanwhile stays.
        local ours = tonumber(ReadCVar(cvar)) == tonumber(b.set)
        if not ours or WriteCVar(cvar, b.old) then backup[cvar] = nil end
    end
    if next(backup) == nil then ns.db.pinBackup = nil end
end

-- Brings the CVars in line with "scanning and the option is on".
function ns.UpdatePinning()
    local want = ns.scanning and ns.db.pinTarget
    local applied = ns.db.pinBackup ~= nil
    if want == applied then return end
    if InCombatLockdown() then
        waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if want then Apply() else Restore() end
end

-- PLAYER_LOGOUT (also fired by /reload) puts the player's values back before
-- the game saves its settings, so quitting mid-scan and then disabling the
-- addon can't leave them changed. The login pass is the fallback for a crash.
waiter:RegisterEvent("PLAYER_LOGIN")
waiter:RegisterEvent("PLAYER_LOGOUT")
waiter:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGOUT" then
        if ns.db.pinBackup then Restore() end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
    ns.UpdatePinning()
end)
