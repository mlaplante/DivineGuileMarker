# DivineGuileMarker

> A World of Warcraft Mythic+ addon for **Nexus-Point Xenas** — automatically finds and skull-marks the real Lothraxion the moment Divine Guile begins.

Created by **Kroth — Haomarush**

---

## What Does This Addon Do?

During the **Divine Guile** mechanic, Lothraxion splits into multiple copies called Fractured Images. You need to interrupt the **real one** — interrupt the wrong copy and your group takes a massive AoE hit plus a nasty debuff for a full minute.

The visual difference (the real boss has no horns of light) is easy to miss in a hectic M+ pull. This addon does the detection for you and instantly places a **Skull marker** on the real Lothraxion so everyone in your group can see it.

---

## Installation

**Option A — CurseForge / Wago (recommended)**
Install and keep up to date automatically through the CurseForge or Wago app.

**Option B — Manual**
1. Download the latest release from the [Releases page](../../releases)
2. Unzip and copy the `DivineGuileMarker` folder into:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
3. Log in (or type `/reload` if already in-game)
4. You should see `[DGM] v1.0.0 loaded` in your chat

---

## Usage

The addon works automatically — no setup needed. Just enter the Nexus-Point Xenas dungeon and it will watch for Divine Guile and mark the real boss as soon as it's detected.

> **Note:** You need to be the key holder, raid leader, or have assist to place markers. If you don't have that permission, the addon will instead show a large **on-screen alert** so you still get the callout.

### Slash Commands

Type `/dgm` in chat to see all options. Here are the most useful ones:

| Command | What it does |
|---|---|
| `/dgm` | Show all commands |
| `/dgm enable` / `/dgm disable` | Turn the addon on or off |
| `/dgm announce` | Toggle a party chat message when the boss is found |
| `/dgm sound` | Toggle the sound alert |
| `/dgm marker <1-8>` | Change the raid marker (default is Skull) |
| `/dgm status` | See your current settings |

---

## Requirements

- **Nameplates must be visible** — press `V` to toggle them if you don't see them
- To place markers you need to be the key holder, raid leader, or have assist — the key holder in M+ always has this automatically

---

## Troubleshooting

**The addon loaded but nothing happened during Divine Guile**
Make sure your nameplates are on (`V` key). If the problem persists, the spell or NPC IDs may have changed in a patch — check the [Issues page](../../issues) or leave a comment.

**A marker appeared on the wrong target**
Please report it on the [Issues page](../../issues) with your `/dgm status` output if possible.

**I can see the marker but my group can't**
You don't have permission to place markers. The addon will show a large on-screen alert as a fallback — make sure you have sound on so you catch it.

---

## About

Built to solve a frustrating mechanic in Nexus-Point Xenas so your group can focus on playing well instead of squinting at boss models mid-pull.

**Author:** Kroth — Haomarush
