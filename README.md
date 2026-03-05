# DivineGuileMarker

Automatically identifies and skull-marks the **real Lothraxion** during **Divine Guile** in the Nexus-Point Xenas Mythic+ dungeon (WoW 12.0.1 Midnight).

## The Problem

During Divine Guile, Lothraxion hides among multiple Fractured Images. In Mythic, interrupting the wrong one triggers **Core Exposure** (76k+ AoE damage + 20% Holy damage taken for 1 min). The visual tell is that the real boss has no horns of light, but this is easy to miss in chaotic pulls.

## How It Works

The addon uses a layered detection strategy:

1. **GUID Tracking** — Captures the boss's unique GUID when the encounter starts. During Divine Guile, scans all nameplate units to find the one matching that GUID.
2. **Cast Detection** — The real Lothraxion is the source of the Divine Guile spell in the combat log, which confirms/updates the tracked GUID.
3. **Nameplate Scanning** — Rapid (0.1s interval) nameplate scanning during Divine Guile to find and mark the correct unit token.

Once found, the addon places a **Skull raid marker** on the real boss.

## Installation

1. Copy the `DivineGuileMarker` folder into your WoW addons directory:
   ```
   World of Warcraft/_retail_/Interface/AddOns/DivineGuileMarker/
   ```
2. Restart WoW or type `/reload` if already in-game.
3. Verify it loaded: you should see `[DGM] v1.0.0 loaded` in chat.

## Commands

| Command | Description |
|---|---|
| `/dgm` | Show help |
| `/dgm enable` | Enable the addon |
| `/dgm disable` | Disable the addon |
| `/dgm debug` | Toggle debug mode (logs all NPC IDs — use this first!) |
| `/dgm announce` | Toggle party chat announcement when boss is found |
| `/dgm sound` | Toggle sound alert |
| `/dgm marker <1-8>` | Change which raid marker to use (default: 8 = Skull) |
| `/dgm status` | Show current settings and state |
| `/dgm test` | Target any NPC and test the marking system |

## IMPORTANT: First-Run Verification

Several IDs in this addon need to be verified in-game since they may differ from datamined values:

### Step 1 — Verify NPC IDs
1. Enable debug mode: `/dgm debug`
2. Pull Lothraxion in any difficulty
3. During the fight (especially during Divine Guile), the addon will log every NPC ID it sees
4. After the fight, run `/dgm status` to see all captured NPC IDs
5. Note the Lothraxion boss ID and the Fractured Image ID

### Step 2 — Verify Spell IDs
Debug mode also logs Divine Guile spell casts with their spell IDs. Confirm the addon is detecting the cast. If it isn't, you may need to update `DIVINE_GUILE_SPELL_IDS` in the Lua file.

### Step 3 — Verify Encounter ID
The addon currently accepts any encounter in Nexus-Point Xenas. Once you know the Lothraxion encounter ID from debug output, you can set `LOTHRAXION_ENCOUNTER_ID` for tighter filtering.

### What to Update

Open `DivineGuileMarker.lua` and look for the constants at the top:

```lua
local LOTHRAXION_NPC_ID = 241546          -- Verify this
local FRACTURED_IMAGE_NPC_ID = 0          -- Fill in from debug
local LOTHRAXION_ENCOUNTER_ID = 0         -- Fill in from debug
```

## Requirements

- You need **raid lead or assist** to set raid markers. In M+ the key holder automatically has this.
- If you can't set markers, the addon falls back to a **large on-screen text alert**.
- Nameplates must be enabled (`V` key by default) for nameplate scanning to work.

## Troubleshooting

| Issue | Solution |
|---|---|
| Addon doesn't detect the boss | Run `/dgm debug` and check if the NPC ID matches. Update `LOTHRAXION_NPC_ID` if needed. |
| Marker doesn't appear | You may not have lead/assist. The addon will show a screen alert instead. |
| Marker appears on wrong target | The GUID tracking may need the encounter ID set. Update `LOTHRAXION_ENCOUNTER_ID`. |
| No detection during Divine Guile | The spell IDs may have changed. Check debug output for the actual spell ID being cast. |

## Design Notes

- The addon is intentionally **lightweight** — no UI frames, no configuration panels, just event-driven detection and marking.
- All scanning stops when Divine Guile ends, so there's zero CPU cost outside the mechanic window.
- The 0.1s scan interval during Divine Guile ensures the marker appears almost instantly.
- SavedVariables persist your settings across sessions.
