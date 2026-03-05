-------------------------------------------------------------------------------
-- DivineGuileMarker
-- Automatically identifies and skull-marks the real Lothraxion during
-- Divine Guile in Nexus-Point Xenas (Mythic+).
--
-- Detection strategy (layered):
--   1. GUID tracking: capture boss GUID on pull, match during Divine Guile
--   2. Cast detection: the real boss is the one casting Divine Guile
--   3. NPC ID fallback: if boss/images have different NPC IDs, use that
--
-- The addon scans nameplate units to find a targetable unit token for the
-- real boss and applies raid marker 8 (skull).
-------------------------------------------------------------------------------

local ADDON_NAME = "DivineGuileMarker"
local DGM = CreateFrame("Frame", ADDON_NAME .. "Frame", UIParent)

-------------------------------------------------------------------------------
-- Constants
-- NOTE: These IDs need to be verified in-game. The addon includes a
-- diagnostic mode (/dgm debug) to help capture the correct values.
-------------------------------------------------------------------------------

-- Lothraxion boss NPC ID (from wowhead: npc=241546)
local LOTHRAXION_NPC_ID = 241546

-- Fractured Image NPC ID — UNKNOWN, set to 0 until verified in-game.
-- When debug mode captures it, update this value.
local FRACTURED_IMAGE_NPC_ID = 0

-- Divine Guile spell IDs (both versions seen on wowhead)
local DIVINE_GUILE_SPELL_IDS = {
    [1257613] = true,
    [1257567] = true,
}

-- Brilliant Dispersion spell IDs (used to detect phase transitions)
local BRILLIANT_DISPERSION_SPELL_IDS = {
    [1257547] = true, -- primary ID from wowhead
}

-- Nexus-Point Xenas encounter ID for Lothraxion
-- NOTE: This may need to be verified. If unknown, the addon also keys off
-- NPC ID detection as a fallback for encounter identification.
local LOTHRAXION_ENCOUNTER_ID = 0  -- Set to 0 = match any encounter in the zone

-- Nexus-Point Xenas map/instance IDs
-- The dungeon instance ID needs verification; we use zone name as fallback
local NEXUS_POINT_INSTANCE_NAME = "Nexus-Point Xenas"

-- Raid marker index for skull
local SKULL_MARKER = 8

-- How often (seconds) to re-scan nameplates during Divine Guile
local SCAN_INTERVAL = 0.1

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local state = {
    bossGUID = nil,           -- captured on encounter start
    bossUnitToken = nil,      -- current unit token for the real boss
    divineGuileActive = false,-- true while Divine Guile is being cast
    markerSet = false,        -- true once we've set the skull marker
    inEncounter = false,      -- true between ENCOUNTER_START / ENCOUNTER_END
    debugMode = false,        -- verbose printing for ID discovery
    scanTicker = nil,         -- C_Timer ticker for nameplate scanning
    npcIDsFound = {},         -- tracks all NPC IDs seen (debug)
}

-------------------------------------------------------------------------------
-- Saved variables (persisted across sessions)
-------------------------------------------------------------------------------

DivineGuileMarkerDB = DivineGuileMarkerDB or {
    enabled = true,
    announceToParty = false,  -- optionally announce in party chat
    markerIndex = SKULL_MARKER,
    soundAlert = true,
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

--- Extract NPC ID from a GUID string.
-- GUID format: "Creature-0-XXXX-XXXX-XXXX-NPCID-SPAWNID"
local function GetNPCIDFromGUID(guid)
    if not guid then return nil end
    local npcID = select(6, strsplit("-", guid))
    return npcID and tonumber(npcID) or nil
end

--- Check if we are in the correct dungeon.
local function IsInNexusPoint()
    local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
    if instanceType == "party" then
        -- Check by instance name as a fallback since we may not know the ID
        local zoneName = GetInstanceInfo()
        if zoneName and zoneName:find("Nexus") then
            return true
        end
    end
    return false
end

--- Try to find a unit token for a given GUID by scanning nameplates and boss units.
local function FindUnitByGUID(targetGUID)
    -- Check boss unit frames first (boss1 through boss5)
    for i = 1, 5 do
        local unit = "boss" .. i
        if UnitExists(unit) and UnitGUID(unit) == targetGUID then
            return unit
        end
    end

    -- Scan nameplate units
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) and UnitGUID(unit) == targetGUID then
            return unit
        end
    end

    -- Check target and focus
    if UnitExists("target") and UnitGUID("target") == targetGUID then
        return "target"
    end
    if UnitExists("focus") and UnitGUID("focus") == targetGUID then
        return "focus"
    end

    return nil
end

--- Attempt to set the raid marker on the real boss.
local function MarkRealBoss()
    if not state.bossGUID then
        DebugPrint("No boss GUID stored, cannot mark.")
        return false
    end

    local unit = FindUnitByGUID(state.bossGUID)
    if not unit then
        DebugPrint("Boss GUID found but no visible unit token yet.")
        return false
    end

    state.bossUnitToken = unit

    -- Check if we can set markers (need lead/assist, or in M+ the key holder)
    local marker = DivineGuileMarkerDB.markerIndex or SKULL_MARKER
    local currentMarker = GetRaidTargetIndex(unit)

    if currentMarker == marker then
        -- Already marked
        if not state.markerSet then
            state.markerSet = true
            DebugPrint("Boss already has skull marker.")
        end
        return true
    end

    -- Attempt to set the marker
    SetRaidTarget(unit, marker)

    -- Verify it took
    C_Timer.After(0.05, function()
        local newMarker = GetRaidTargetIndex(unit)
        if newMarker == marker then
            state.markerSet = true
            Print("Real Lothraxion marked with {skull}!")

            if DivineGuileMarkerDB.soundAlert then
                PlaySound(8959) -- RAID_WARNING sound
            end

            if DivineGuileMarkerDB.announceToParty then
                local msg = "{skull} REAL LOTHRAXION FOUND — Interrupt this one! {skull}"
                SendChatMessage(msg, "PARTY")
            end
        else
            DebugPrint("Could not set marker. You may need lead/assist.")
            -- Still show a local alert even if we can't mark
            ShowScreenAlert()
        end
    end)

    return true
end

--- Display a large on-screen alert as a fallback when marking fails.
local function ShowScreenAlert()
    -- Use RaidWarningFrame for a big center-screen message
    RaidNotice_AddMessage(RaidWarningFrame,
        "|cffFFFF00REAL LOTHRAXION FOUND!|r Target the one WITHOUT horns!",
        ChatTypeInfo["RAID_WARNING"])

    if DivineGuileMarkerDB.soundAlert then
        PlaySound(8959)
    end
end

-------------------------------------------------------------------------------
-- Nameplate scanning during Divine Guile
-------------------------------------------------------------------------------

local function StartNameplateScan()
    if state.scanTicker then return end -- already scanning

    DebugPrint("Starting nameplate scan for real Lothraxion...")

    state.scanTicker = C_Timer.NewTicker(SCAN_INTERVAL, function()
        if not state.divineGuileActive then
            StopNameplateScan()
            return
        end

        -- If already marked successfully, reduce scan frequency
        if state.markerSet then
            -- Verify marker is still on the boss (could be cleared)
            if state.bossUnitToken and UnitExists(state.bossUnitToken) then
                local currentMarker = GetRaidTargetIndex(state.bossUnitToken)
                if currentMarker == (DivineGuileMarkerDB.markerIndex or SKULL_MARKER) then
                    return -- still good
                end
            end
            -- Marker lost, try again
            state.markerSet = false
        end

        MarkRealBoss()

        -- Debug: log all nameplate NPCs during Divine Guile
        if state.debugMode then
            for i = 1, 40 do
                local unit = "nameplate" .. i
                if UnitExists(unit) then
                    local guid = UnitGUID(unit)
                    local npcID = GetNPCIDFromGUID(guid)
                    local name = UnitName(unit)
                    if npcID and not state.npcIDsFound[npcID] then
                        state.npcIDsFound[npcID] = name or "Unknown"
                        DebugPrint(string.format(
                            "NPC found: %s (ID: %d) GUID: %s %s",
                            name or "?", npcID, guid or "?",
                            (guid == state.bossGUID) and "<-- REAL BOSS" or ""
                        ))
                    end
                end
            end
        end
    end)
end

local function StopNameplateScan()
    if state.scanTicker then
        state.scanTicker:Cancel()
        state.scanTicker = nil
        DebugPrint("Nameplate scan stopped.")
    end
end

-------------------------------------------------------------------------------
-- Event handlers
-------------------------------------------------------------------------------

--- Capture the boss GUID when the encounter begins.
local function OnEncounterStart(encounterID, encounterName, difficultyID, groupSize)
    DebugPrint(string.format(
        "ENCOUNTER_START: id=%d name=%s diff=%d size=%d",
        encounterID, encounterName or "?", difficultyID, groupSize
    ))

    -- If we know the encounter ID, filter on it. Otherwise accept any
    -- encounter in this zone and rely on NPC ID detection.
    if LOTHRAXION_ENCOUNTER_ID ~= 0 and encounterID ~= LOTHRAXION_ENCOUNTER_ID then
        return
    end

    -- Try to grab the boss GUID immediately from boss unit frames
    for i = 1, 5 do
        local unit = "boss" .. i
        if UnitExists(unit) then
            local guid = UnitGUID(unit)
            local npcID = GetNPCIDFromGUID(guid)
            if npcID == LOTHRAXION_NPC_ID then
                state.bossGUID = guid
                state.inEncounter = true
                DebugPrint("Boss GUID captured from " .. unit .. ": " .. guid)
                Print("Lothraxion detected — tracking for Divine Guile.")
                return
            end
        end
    end

    -- Fallback: scan nameplates
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            local guid = UnitGUID(unit)
            local npcID = GetNPCIDFromGUID(guid)
            if npcID == LOTHRAXION_NPC_ID then
                state.bossGUID = guid
                state.inEncounter = true
                DebugPrint("Boss GUID captured from " .. unit .. ": " .. guid)
                Print("Lothraxion detected — tracking for Divine Guile.")
                return
            end
        end
    end

    -- If we still haven't found it, mark encounter as active and try
    -- to pick up the GUID from combat log events
    state.inEncounter = true
    DebugPrint("Encounter started but boss GUID not yet captured. Waiting for combat log...")
end

--- Clean up when the encounter ends.
local function OnEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
    DebugPrint(string.format("ENCOUNTER_END: id=%d success=%d", encounterID, success or 0))

    -- Clear the raid marker if we set one
    if state.markerSet and state.bossUnitToken and UnitExists(state.bossUnitToken) then
        SetRaidTarget(state.bossUnitToken, 0)
    end

    -- Reset all state
    state.bossGUID = nil
    state.bossUnitToken = nil
    state.divineGuileActive = false
    state.markerSet = false
    state.inEncounter = false
    state.npcIDsFound = {}
    StopNameplateScan()
end

--- Process relevant combat log events.
local function OnCombatLogEvent()
    if not state.inEncounter and not IsInNexusPoint() then return end

    local timestamp, subevent, _, sourceGUID, sourceName, sourceFlags,
          sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags,
          spellID, spellName = CombatLogGetCurrentEventInfo()

    -- Capture boss GUID from any combat event if we don't have it yet
    if not state.bossGUID and sourceGUID then
        local npcID = GetNPCIDFromGUID(sourceGUID)
        if npcID == LOTHRAXION_NPC_ID then
            state.bossGUID = sourceGUID
            state.inEncounter = true
            DebugPrint("Boss GUID captured from combat log: " .. sourceGUID)
        end
    end

    -- Detect Divine Guile cast start
    if subevent == "SPELL_CAST_START" or subevent == "SPELL_CAST_SUCCESS" then
        if DIVINE_GUILE_SPELL_IDS[spellID] then
            DebugPrint(string.format(
                "Divine Guile detected! Source: %s (%s) SpellID: %d",
                sourceName or "?", sourceGUID or "?", spellID
            ))

            -- This confirms the real boss GUID
            if sourceGUID then
                state.bossGUID = sourceGUID
            end

            state.divineGuileActive = true
            state.markerSet = false

            -- Immediately try to mark
            if not MarkRealBoss() then
                -- Start scanning if immediate mark failed
                StartNameplateScan()
            else
                -- Still start scanning to maintain the marker
                StartNameplateScan()
            end
        end
    end

    -- Detect Divine Guile channel start (may fire as SPELL_CAST_CHANNEL_START in some versions)
    if subevent == "SPELL_AURA_APPLIED" then
        if DIVINE_GUILE_SPELL_IDS[spellID] and sourceGUID then
            if not state.divineGuileActive then
                state.bossGUID = sourceGUID
                state.divineGuileActive = true
                state.markerSet = false
                StartNameplateScan()
                DebugPrint("Divine Guile aura detected on: " .. (sourceName or sourceGUID))
            end
        end
    end

    -- Detect Divine Guile ending (interrupted or completed)
    if subevent == "SPELL_INTERRUPT" or subevent == "SPELL_CAST_FAILED" then
        if DIVINE_GUILE_SPELL_IDS[spellID] then
            DebugPrint("Divine Guile interrupted/ended.")
            state.divineGuileActive = false
            state.markerSet = false
            StopNameplateScan()
        end
    end

    -- Also catch the channel ending
    if subevent == "SPELL_AURA_REMOVED" then
        if DIVINE_GUILE_SPELL_IDS[spellID] then
            DebugPrint("Divine Guile aura removed.")
            state.divineGuileActive = false
            StopNameplateScan()
        end
    end

    -- Debug: log Fractured Image NPC IDs
    if state.debugMode and sourceGUID then
        local npcID = GetNPCIDFromGUID(sourceGUID)
        if npcID and npcID ~= LOTHRAXION_NPC_ID and not state.npcIDsFound[npcID] then
            state.npcIDsFound[npcID] = sourceName or "Unknown"
            DebugPrint(string.format(
                "New NPC in combat: %s (ID: %d) GUID: %s",
                sourceName or "?", npcID, sourceGUID
            ))
        end
    end
end

--- Handle UNIT_TARGET and NAME_PLATE_UNIT_ADDED to catch boss GUID early.
local function OnNameplateAdded(unit)
    if not state.inEncounter then return end
    if state.bossGUID then return end -- already have it

    local guid = UnitGUID(unit)
    local npcID = GetNPCIDFromGUID(guid)
    if npcID == LOTHRAXION_NPC_ID then
        state.bossGUID = guid
        DebugPrint("Boss GUID captured from nameplate: " .. guid)
    end
end

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------

local function HandleSlashCommand(msg)
    local cmd = msg:lower():trim()

    if cmd == "" or cmd == "help" then
        Print("DivineGuileMarker v1.0.0 — Commands:")
        Print("  /dgm — Show this help")
        Print("  /dgm enable — Enable the addon")
        Print("  /dgm disable — Disable the addon")
        Print("  /dgm debug — Toggle debug mode (logs NPC IDs)")
        Print("  /dgm announce — Toggle party chat announcement")
        Print("  /dgm sound — Toggle sound alert")
        Print("  /dgm marker <1-8> — Set which raid marker to use")
        Print("  /dgm status — Show current settings and state")
        Print("  /dgm test — Simulate Divine Guile detection (target an NPC)")

    elseif cmd == "enable" then
        DivineGuileMarkerDB.enabled = true
        Print("Addon |cff00ff00ENABLED|r.")

    elseif cmd == "disable" then
        DivineGuileMarkerDB.enabled = false
        Print("Addon |cffff0000DISABLED|r.")

    elseif cmd == "debug" then
        state.debugMode = not state.debugMode
        Print("Debug mode: " .. (state.debugMode and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        if state.debugMode then
            Print("Debug will log all NPC IDs seen during the encounter.")
            Print("Use this to find the Fractured Image NPC ID.")
        end

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
            Print("Usage: /dgm marker <1-8> (1=Star, 8=Skull)")
        end

    elseif cmd == "status" then
        Print("--- DivineGuileMarker Status ---")
        Print("Enabled: " .. (DivineGuileMarkerDB.enabled and "Yes" or "No"))
        Print("Debug: " .. (state.debugMode and "Yes" or "No"))
        Print("Party announce: " .. (DivineGuileMarkerDB.announceToParty and "Yes" or "No"))
        Print("Sound alert: " .. (DivineGuileMarkerDB.soundAlert and "Yes" or "No"))
        local names = {"Star","Circle","Diamond","Triangle","Moon","Square","Cross","Skull"}
        local mi = DivineGuileMarkerDB.markerIndex or SKULL_MARKER
        Print("Marker: " .. names[mi] .. " (" .. mi .. ")")
        Print("In encounter: " .. (state.inEncounter and "Yes" or "No"))
        Print("Boss GUID: " .. (state.bossGUID or "Not captured"))
        Print("Divine Guile active: " .. (state.divineGuileActive and "Yes" or "No"))
        Print("In Nexus-Point: " .. (IsInNexusPoint() and "Yes" or "No"))
        if next(state.npcIDsFound) then
            Print("NPC IDs seen this encounter:")
            for id, name in pairs(state.npcIDsFound) do
                Print("  " .. name .. " = " .. id)
            end
        end

    elseif cmd == "test" then
        -- Test mode: try to mark current target
        if UnitExists("target") then
            local guid = UnitGUID("target")
            local npcID = GetNPCIDFromGUID(guid)
            Print(string.format("Target: %s | NPC ID: %s | GUID: %s",
                UnitName("target") or "?",
                tostring(npcID),
                guid or "?"
            ))
            state.bossGUID = guid
            state.divineGuileActive = true
            MarkRealBoss()
            C_Timer.After(5, function()
                state.divineGuileActive = false
                state.markerSet = false
                Print("Test complete — marker cleared after 5s.")
                if UnitExists("target") then
                    SetRaidTarget("target", 0)
                end
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
-- Main event dispatcher
-------------------------------------------------------------------------------

DGM:RegisterEvent("PLAYER_LOGIN")
DGM:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
DGM:RegisterEvent("ENCOUNTER_START")
DGM:RegisterEvent("ENCOUNTER_END")
DGM:RegisterEvent("NAME_PLATE_UNIT_ADDED")

DGM:SetScript("OnEvent", function(self, event, ...)
    if not DivineGuileMarkerDB.enabled then return end

    if event == "PLAYER_LOGIN" then
        Print("v1.0.0 loaded. Type /dgm for options.")
        Print("Tip: Run '/dgm debug' during Lothraxion to capture NPC IDs.")

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLogEvent()

    elseif event == "ENCOUNTER_START" then
        OnEncounterStart(...)

    elseif event == "ENCOUNTER_END" then
        OnEncounterEnd(...)

    elseif event == "NAME_PLATE_UNIT_ADDED" then
        OnNameplateAdded(...)
    end
end)

-------------------------------------------------------------------------------
-- ShowScreenAlert - defined earlier but needs to be accessible
-- (Lua hoisting means the local function above works fine)
-------------------------------------------------------------------------------

Print("DivineGuileMarker file loaded.")
