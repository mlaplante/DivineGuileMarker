-------------------------------------------------------------------------------
-- DivineGuileMarker
-- Automatically identifies and skull-marks the real Lothraxion during
-- Divine Guile in Nexus-Point Xenas (Mythic+).
--
-- Detection strategy (polling-based — no Frame:RegisterEvent needed):
--   C_Timer.NewTicker drives all detection. Divine Guile is identified by
--   counting nameplates named "Lothraxion": 2+ means the mechanic is active.
--   The real boss is the one whose GUID matches the pre-captured boss GUID
--   (== comparison works on WoW Midnight secret strings).
-------------------------------------------------------------------------------

local ADDON_NAME = "DivineGuileMarker"

-- SavedVariables: WoW loads saved values after the main chunk runs but before
-- the first timer callback fires, so this or-default is only hit on first run.
DivineGuileMarkerDB = DivineGuileMarkerDB or {
    enabled        = true,
    announceToParty = false,
    markerIndex    = 8,   -- 8 = Skull
    soundAlert     = true,
}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

local SKULL_MARKER  = 8
local BOSS_NAME     = "Lothraxion"
local POLL_INTERVAL = 0.5   -- seconds between polls

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local state = {
    bossGUID         = nil,
    bossUnitToken    = nil,
    divineGuileActive = false,
    markerSet        = false,
    inEncounter      = false,
    debugMode        = false,
    npcIDsFound      = {},
}

-------------------------------------------------------------------------------
-- Utility functions
-------------------------------------------------------------------------------

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DGM]|r " .. tostring(msg))
end

local function DebugPrint(msg)
    if state.debugMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[DGM-Debug]|r " .. tostring(msg))
    end
end

--- Safely convert a GUID to a printable string.
-- UnitGUID() may return a secret string in WoW Midnight that cannot be
-- passed to string operations. pcall(tostring) handles this gracefully.
local function SafeGUID(guid)
    if not guid then return "nil" end
    local ok, str = pcall(tostring, guid)
    return ok and str or "[secret]"
end

--- Extract NPC ID from a GUID string (returns nil for secret GUIDs).
-- GUID format: "Creature-0-XXXX-XXXX-XXXX-NPCID-SPAWNID"
local function GetNPCIDFromGUID(guid)
    if not guid then return nil end
    local ok, _, _, _, _, _, npcID = pcall(strsplit, "-", guid)
    if not ok then return nil end
    return npcID and tonumber(npcID) or nil
end

--- Find a unit token for a stored GUID by scanning boss frames and nameplates.
local function FindUnitByGUID(targetGUID)
    if not targetGUID then return nil end
    for i = 1, 5 do
        local unit = "boss" .. i
        if UnitExists(unit) and UnitGUID(unit) == targetGUID then return unit end
    end
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) and UnitGUID(unit) == targetGUID then return unit end
    end
    if UnitExists("target") and UnitGUID("target") == targetGUID then return "target" end
    if UnitExists("focus")  and UnitGUID("focus")  == targetGUID then return "focus"  end
    return nil
end

--- Return true when the player is in Nexus-Point Xenas.
local function IsInNexusPoint()
    local _, instanceType = GetInstanceInfo()
    if instanceType ~= "party" then return false end
    local zoneName = GetInstanceInfo()
    return zoneName ~= nil and zoneName:find("Nexus") ~= nil
end

-------------------------------------------------------------------------------
-- Alert overlay (lazy — created only when needed, avoiding load-time taint)
-------------------------------------------------------------------------------

local alertFrame, alertText

local function ShowScreenAlert()
    if not alertFrame then
        alertFrame = CreateFrame("Frame", nil, UIParent)
        alertFrame:SetSize(700, 80)
        alertFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        alertFrame:SetFrameStrata("HIGH")
        alertText = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        alertText:SetAllPoints()
        alertText:SetTextColor(1, 1, 0)
    end
    alertText:SetText("REAL LOTHRAXION FOUND! — Target WITHOUT horns!")
    alertFrame:Show()
    C_Timer.After(4, function() alertFrame:Hide() end)
    if DivineGuileMarkerDB.soundAlert then
        PlaySound(8959)
    end
end

-------------------------------------------------------------------------------
-- Encounter management
-------------------------------------------------------------------------------

local function ResetEncounter()
    if state.markerSet and state.bossUnitToken and UnitExists(state.bossUnitToken) then
        SetRaidTarget(state.bossUnitToken, 0)
    end
    state.bossGUID          = nil
    state.bossUnitToken     = nil
    state.divineGuileActive = false
    state.markerSet         = false
    state.inEncounter       = false
    state.npcIDsFound       = {}
    DebugPrint("Encounter reset.")
end

local function MarkRealBoss()
    if not state.bossGUID then return false end

    local unit = FindUnitByGUID(state.bossGUID)
    if not unit then
        DebugPrint("Boss GUID known but no visible unit token yet.")
        return false
    end

    state.bossUnitToken = unit
    local marker        = DivineGuileMarkerDB.markerIndex or SKULL_MARKER
    local current       = GetRaidTargetIndex(unit)

    if current == marker then
        state.markerSet = true
        return true
    end

    SetRaidTarget(unit, marker)

    C_Timer.After(0.05, function()
        if not UnitExists(unit) then return end
        if GetRaidTargetIndex(unit) == marker then
            state.markerSet = true
            Print("Real Lothraxion marked with {skull}!")
            if DivineGuileMarkerDB.soundAlert then
                PlaySound(8959)
            end
            if DivineGuileMarkerDB.announceToParty then
                SendChatMessage("{skull} REAL LOTHRAXION FOUND — Interrupt this one! {skull}", "PARTY")
            end
        else
            DebugPrint("Could not set marker — need lead or assist.")
            ShowScreenAlert()
        end
    end)

    return true
end

-------------------------------------------------------------------------------
-- Main poll function (driven by C_Timer.NewTicker — no RegisterEvent needed)
-------------------------------------------------------------------------------

local function Poll()
    if not DivineGuileMarkerDB.enabled then return end

    -- Fast exit when not in the right dungeon
    if not IsInNexusPoint() then
        if state.inEncounter then ResetEncounter() end
        return
    end

    -- ── Encounter start detection ────────────────────────────────────────────
    if not state.inEncounter then
        for i = 1, 5 do
            local unit = "boss" .. i
            if UnitExists(unit) and UnitName(unit) == BOSS_NAME then
                state.bossGUID    = UnitGUID(unit)   -- may be secret; used for == only
                state.inEncounter = true
                state.bossUnitToken = unit
                Print("Lothraxion detected — watching for Divine Guile.")
                DebugPrint("Boss GUID captured from " .. unit .. ": " .. SafeGUID(state.bossGUID))
            end
            -- Debug: log all boss-frame NPC IDs
            if state.debugMode and UnitExists(unit) then
                local guid  = UnitGUID(unit)
                local npcID = GetNPCIDFromGUID(guid)
                local name  = UnitName(unit)
                if npcID and not state.npcIDsFound[npcID] then
                    state.npcIDsFound[npcID] = name or "Unknown"
                    DebugPrint(string.format("Boss frame: %s (NPC ID: %d) on %s",
                        name or "?", npcID, unit))
                end
            end
        end
        return
    end

    -- ── Encounter end detection ───────────────────────────────────────────────
    local bossAlive = false
    for i = 1, 5 do
        if UnitExists("boss" .. i) then bossAlive = true; break end
    end
    if not bossAlive then
        DebugPrint("Encounter ended (no boss frames).")
        ResetEncounter()
        return
    end

    -- ── Divine Guile detection ────────────────────────────────────────────────
    -- Count nameplates named "Lothraxion". During Divine Guile, Fractured
    -- Images share the boss name, so 2+ units = mechanic is active.
    local lothraxionCount = 0
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            if UnitName(unit) == BOSS_NAME then
                lothraxionCount = lothraxionCount + 1
            end
            -- Debug: log all NPC IDs seen on nameplates during encounter
            if state.debugMode then
                local guid  = UnitGUID(unit)
                local npcID = GetNPCIDFromGUID(guid)
                local name  = UnitName(unit)
                if npcID and not state.npcIDsFound[npcID] then
                    state.npcIDsFound[npcID] = name or "Unknown"
                    DebugPrint(string.format("Nameplate NPC: %s (ID: %d) GUID: %s%s",
                        name or "?", npcID, SafeGUID(guid),
                        (guid == state.bossGUID) and " <-- REAL BOSS" or ""))
                end
            end
        end
    end

    if lothraxionCount >= 2 then
        if not state.divineGuileActive then
            state.divineGuileActive = true
            state.markerSet         = false
            DebugPrint(string.format("Divine Guile detected! %d Lothraxion units visible.", lothraxionCount))
        end
        if not state.markerSet then
            MarkRealBoss()
        end
    elseif state.divineGuileActive then
        state.divineGuileActive = false
        DebugPrint("Divine Guile ended.")
    end
end

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------

local function HandleSlashCommand(msg)
    local cmd = msg:lower():trim()

    if cmd == "" or cmd == "help" then
        Print("DivineGuileMarker v1.0.6 — Commands:")
        Print("  /dgm            — Show this help")
        Print("  /dgm enable     — Enable the addon")
        Print("  /dgm disable    — Disable the addon")
        Print("  /dgm debug      — Toggle debug mode (logs NPC IDs)")
        Print("  /dgm announce   — Toggle party chat announcement")
        Print("  /dgm sound      — Toggle sound alert")
        Print("  /dgm marker <1-8> — Set raid marker (default: 8 = Skull)")
        Print("  /dgm status     — Show current settings and state")
        Print("  /dgm test       — Test marking on current target")

    elseif cmd == "enable" then
        DivineGuileMarkerDB.enabled = true
        Print("Addon |cff00ff00ENABLED|r.")

    elseif cmd == "disable" then
        DivineGuileMarkerDB.enabled = false
        Print("Addon |cffff0000DISABLED|r.")

    elseif cmd == "debug" then
        state.debugMode = not state.debugMode
        Print("Debug mode: " .. (state.debugMode and "|cff00ff00ON|r" or "|cffff0000OFF|r"))

    elseif cmd == "announce" then
        DivineGuileMarkerDB.announceToParty = not DivineGuileMarkerDB.announceToParty
        Print("Party announce: " ..
            (DivineGuileMarkerDB.announceToParty and "|cff00ff00ON|r" or "|cffff0000OFF|r"))

    elseif cmd == "sound" then
        DivineGuileMarkerDB.soundAlert = not DivineGuileMarkerDB.soundAlert
        Print("Sound alert: " ..
            (DivineGuileMarkerDB.soundAlert and "|cff00ff00ON|r" or "|cffff0000OFF|r"))

    elseif cmd:find("^marker") then
        local idx = tonumber(cmd:match("marker%s+(%d+)"))
        if idx and idx >= 1 and idx <= 8 then
            DivineGuileMarkerDB.markerIndex = idx
            local names = {"Star","Circle","Diamond","Triangle","Moon","Square","Cross","Skull"}
            Print("Marker set to: " .. names[idx] .. " (" .. idx .. ")")
        else
            Print("Usage: /dgm marker <1-8>  (1=Star … 8=Skull)")
        end

    elseif cmd == "status" then
        Print("--- DivineGuileMarker Status ---")
        Print("Enabled: "        .. (DivineGuileMarkerDB.enabled and "Yes" or "No"))
        Print("Debug: "          .. (state.debugMode and "Yes" or "No"))
        Print("Party announce: " .. (DivineGuileMarkerDB.announceToParty and "Yes" or "No"))
        Print("Sound alert: "    .. (DivineGuileMarkerDB.soundAlert and "Yes" or "No"))
        local names = {"Star","Circle","Diamond","Triangle","Moon","Square","Cross","Skull"}
        local mi    = DivineGuileMarkerDB.markerIndex or SKULL_MARKER
        Print("Marker: " .. names[mi] .. " (" .. mi .. ")")
        Print("In encounter: "      .. (state.inEncounter and "Yes" or "No"))
        Print("Boss GUID: "         .. (state.bossGUID and SafeGUID(state.bossGUID) or "Not captured"))
        Print("Divine Guile active: " .. (state.divineGuileActive and "Yes" or "No"))
        Print("In Nexus-Point: "    .. (IsInNexusPoint() and "Yes" or "No"))
        if next(state.npcIDsFound) then
            Print("NPC IDs seen this encounter:")
            for id, name in pairs(state.npcIDsFound) do
                Print("  " .. name .. " = " .. id)
            end
        end

    elseif cmd == "test" then
        if UnitExists("target") then
            local guid  = UnitGUID("target")
            local npcID = GetNPCIDFromGUID(guid)
            Print(string.format("Target: %s | NPC ID: %s | GUID: %s",
                UnitName("target") or "?", tostring(npcID), SafeGUID(guid)))
            state.bossGUID          = guid
            state.divineGuileActive = true
            MarkRealBoss()
            C_Timer.After(5, function()
                state.divineGuileActive = false
                state.markerSet         = false
                Print("Test complete — marker cleared after 5s.")
                if UnitExists("target") then SetRaidTarget("target", 0) end
            end)
        else
            Print("Target an NPC first, then run /dgm test")
        end

    else
        Print("Unknown command: " .. cmd .. ". Type /dgm help for options.")
    end
end

SLASH_DIVINEGUILEMARKER1 = "/dgm"
SLASH_DIVINEGUILEMARKER2 = "/divineguile"
SlashCmdList["DIVINEGUILEMARKER"] = HandleSlashCommand

-------------------------------------------------------------------------------
-- Bootstrap
--
-- C_Timer functions are NOT protected — this works at load time without any
-- Frame:RegisterEvent calls. The ticker polls every 0.5s; Poll() fast-exits
-- when outside Nexus-Point Xenas so overhead outside the dungeon is trivial.
--
-- C_Timer.After(0) fires after the first game frame, by which time
-- SavedVariables have been loaded and DivineGuileMarkerDB has saved values.
-------------------------------------------------------------------------------

C_Timer.NewTicker(POLL_INTERVAL, Poll)

C_Timer.After(0, function()
    -- Ensure DivineGuileMarkerDB has all expected keys (handles addon updates
    -- where new keys were added since the player's last saved session).
    DivineGuileMarkerDB = DivineGuileMarkerDB or {}
    if DivineGuileMarkerDB.enabled        == nil then DivineGuileMarkerDB.enabled        = true  end
    if DivineGuileMarkerDB.announceToParty == nil then DivineGuileMarkerDB.announceToParty = false end
    if DivineGuileMarkerDB.markerIndex    == nil then DivineGuileMarkerDB.markerIndex    = SKULL_MARKER end
    if DivineGuileMarkerDB.soundAlert     == nil then DivineGuileMarkerDB.soundAlert     = true  end
    Print("v1.0.6 loaded. Type /dgm for options.")
end)
