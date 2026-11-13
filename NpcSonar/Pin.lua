--------------------------------------------------------------------------------
-- NPC Sonar -- game settings changed while a scan runs
--
-- Two options change console variables (CVars) for the length of a scan:
--
-- Keep target's nameplate on screen (pinTarget). Addons can't place a
-- nameplate themselves (no world-to-screen API, and NPC positions are
-- hidden), but the client can hold off-screen plates at the screen edge.
-- Which CVar does that differs by client:
--
--   Retail (Midnight)  nameplateTargetRadialPosition  1 = target only
--   Classic clients    nameplate{Other,Large}{Top,Bottom}Inset  >= 0 clamps
--                      plates that far inside the edge, -1 lets them leave
--
-- Show friendly NPC nameplates (friendlyPlates). The scan sees NPCs through
-- their nameplates, and friendly NPC plates are a separate, per-character
-- setting that is off by default (nameplateShowFriendlyNPCs). Without it a
-- friendly quest NPC is only found under the mouse or as your target.
--
-- Within each option the client is told apart by which CVar exists, not by
-- version checks (see the rule sets). A rule is skipped when the player's own
-- setting already does the job, so we never downgrade it.
--
-- The player's values are saved in NpcSonarDB.pinBackup first and put back
-- when the scan stops or an option is turned off, at logout, and again at
-- login in case the game closed mid-scan. NpcSonarDB.pinKey records which
-- rules are in effect. A value the player changed themselves while scanning
-- is left alone. CVars can't be changed in combat, so a change requested
-- then waits for PLAYER_REGEN_ENABLED.
--------------------------------------------------------------------------------

local _, ns = ...

local function ReadCVar(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
    return GetCVar(name)
end

-- True only when the write went through: C_CVar.SetCVar can refuse by
-- returning false without raising. The old global returns nothing, which
-- counts as success.
local function WriteCVar(name, value)
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    local ok, res = pcall(set, name, value)
    return ok and res ~= false
end

local function AtLeast(min)
    return function(v) local n = tonumber(v); return n ~= nil and n >= min end
end

-- Each option lists sets of rules, best first. Only the first set whose lead
-- CVar exists is used: for pinTarget, the insets move every plate, so they
-- are never applied on a client that has the target-only radial setting,
-- even if it still knows the insets.
local INSET = "0.1"
local OPTIONS = {
    {
        option = "pinTarget",
        sets = {
            {
                { cvar = "nameplateTargetRadialPosition", value = "1", ok = AtLeast(1) },
            },
            {
                { cvar = "nameplateOtherTopInset",    value = INSET, ok = AtLeast(0) },
                { cvar = "nameplateOtherBottomInset", value = INSET, ok = AtLeast(0) },
                { cvar = "nameplateLargeTopInset",    value = INSET, ok = AtLeast(0) },
                { cvar = "nameplateLargeBottomInset", value = INSET, ok = AtLeast(0) },
            },
        },
    },
    {
        option = "friendlyPlates",
        sets = {
            {
                { cvar = "nameplateShowFriendlyNPCs", value = "1", ok = AtLeast(1) },
            },
        },
    },
}

-- The rules wanted right now: those of every option that is on, while a scan
-- runs; none otherwise. Also returns a key naming them, to compare with what
-- is in effect.
local function WantedRules()
    local rules, names = {}, {}
    if not ns.scanning then return rules, "" end
    for _, o in ipairs(OPTIONS) do
        if ns.db[o.option] then
            for _, set in ipairs(o.sets) do
                if ReadCVar(set[1].cvar) ~= nil then
                    for _, r in ipairs(set) do
                        rules[#rules + 1] = r
                        names[#names + 1] = r.cvar
                    end
                    break
                end
            end
        end
    end
    table.sort(names)
    return rules, table.concat(names, ",")
end

local waiter = CreateFrame("Frame")

-- A CVar still in the backup (its restore failed earlier) is ours already:
-- its saved original is kept rather than replaced by our own value.
local function Apply(rules, key)
    local backup = ns.db.pinBackup or {}
    for _, r in ipairs(rules) do
        if not backup[r.cvar] then
            local cur = ReadCVar(r.cvar)
            if cur ~= nil and not r.ok(cur) and WriteCVar(r.cvar, r.value) then
                backup[r.cvar] = { old = cur, set = r.value }
            end
        end
    end
    ns.db.pinBackup = backup
    ns.db.pinKey = key
end

-- An entry is dropped once it is restored or no longer ours to restore. One
-- whose write fails stays in the backup, and so does the backup, so the next
-- UpdatePinning or login tries again. CVars named in `keep` are left as they
-- are, still backed up: the new set of rules wants them too, so turning one
-- option off mid-scan doesn't flip the other option's settings off and on.
local function Restore(keep)
    local backup = ns.db.pinBackup or {}
    for cvar, b in pairs(backup) do
        -- Kept entries carry over; Apply skips them because they are still
        -- backed up.
        if not (keep and keep[cvar]) then
            -- Only undo our own change; a value the player set meanwhile stays.
            local ours = tonumber(ReadCVar(cvar)) == tonumber(b.set)
            if not ours or WriteCVar(cvar, b.old) then backup[cvar] = nil end
        end
    end
    ns.db.pinBackup = next(backup) and backup or nil
    ns.db.pinKey = nil
end

-- Brings the CVars in line with the scan state and the options. Called on
-- Start, Stop, option toggles, login and after combat. When what is wanted
-- changes, CVars the new rules no longer want are put back and the rest are
-- applied, which keeps the bookkeeping to one backup.
function ns.UpdatePinning()
    local rules, key = WantedRules()
    -- A backup without a key comes from 1.0.0, before keys; treat it as stale.
    local current = ns.db.pinKey or (ns.db.pinBackup and "?") or ""
    if key == current then return end
    if InCombatLockdown() then
        waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local keep = {}
    for _, r in ipairs(rules) do keep[r.cvar] = true end
    Restore(keep)
    if key ~= "" then Apply(rules, key) end
end

-- PLAYER_LOGOUT (also fired by /reload) puts the player's values back before
-- the game saves its settings, so quitting mid-scan and then disabling the
-- addon can't leave them changed. The login pass is the fallback for a crash.
waiter:RegisterEvent("PLAYER_LOGIN")
waiter:RegisterEvent("PLAYER_LOGOUT")
waiter:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGOUT" then
        if ns.db.pinBackup or ns.db.pinKey then Restore() end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
    ns.UpdatePinning()
end)
