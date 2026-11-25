# Crew character sources

Quaternius released the character models, the original character animations, and the Universal Animation Library Standard clips under CC0 1.0 Universal. The downloads below are pinned public mirrors of the assets. Verified and downloaded on 2026-11-22.

| File | Crew role and outfit | Original pack | Direct download |
|---|---|---|---|
| `pilot.glb` | Finn, teal flight jacket | [Ultimate Modular Men](https://quaternius.com/packs/ultimatemodularcharacters.html), Adventurer | [Adventurer.glb](https://raw.githubusercontent.com/LuanDucate/Ducz.CharacterCreator/fcd215b58eec5c9ed97d0ba5f696d0e7dc085e08/public/models/Male/Adventurer.glb) |
| `engineer.glb` | Chip, orange high-visibility vest and hard hat | [Ultimate Modular Men](https://quaternius.com/packs/ultimatemodularcharacters.html), Worker | [Worker.glb](https://raw.githubusercontent.com/LuanDucate/Ducz.CharacterCreator/fcd215b58eec5c9ed97d0ba5f696d0e7dc085e08/public/models/Male/Worker.glb) |
| `gunner.glb` | Barbara, slate tactical vest, pads and boots | [Ultimate Modular Women](https://quaternius.com/packs/ultimatemodularwomen.html), Soldier | [Soldier.glb](https://raw.githubusercontent.com/LuanDucate/Ducz.CharacterCreator/fcd215b58eec5c9ed97d0ba5f696d0e7dc085e08/public/models/Female/Soldier.glb) |
| `raider.glb` | Fernando, rust shirt, dark vest and red mohawk | [Ultimate Modular Men](https://quaternius.com/packs/ultimatemodularcharacters.html), Punk | [Punk.glb](https://raw.githubusercontent.com/LuanDucate/Ducz.CharacterCreator/fcd215b58eec5c9ed97d0ba5f696d0e7dc085e08/public/models/Male/Punk.glb) |

The original 24 clips per model came with the animated character downloads. The four added jump clips use the in-place `Unreal-Godot/UAL1_Standard.glb` from the [Universal Animation Library Standard](https://quaternius.com/packs/universalanimationlibrary.html). The [direct archive](https://media.githubusercontent.com/media/MightyBubble/Ludots-Assets/fab331eff1cb9c552c60399ea10186ef675cd460/animations/Quaternius-Universal-Animation-Library-Standard.zip) has SHA-256 `cc73fc4e495b82958207316596317a3f40b9fa38065bde1027937452da537724` and contains Quaternius's CC0 notice. `Jump` combines the retargeted takeoff, airborne and landing phases. `Jump_Start`, `Jump_Airborne` and `Jump_Land` are the separately playable phases.

The Blender 5.3.0 export keeps four skinned meshes on one rig per character. The geometry retains Quaternius's faceted style. Each GLB embeds its own 512 × 512 PNG albedo atlas with metallic and roughness values on the PBR materials. The colors, atlas, mesh and bone names, bind-pose grounding, scale, and jump retarget are local adaptations. `Hand.R` is the weapon attachment bone.

The Godot bind-pose measurements, material and bone names, and animation clip names are in [PROBE.txt](PROBE.txt). The assets face +Z in Godot (+Z up and −Y forward in Blender), with a Godot bind-pose height matched to `frog.glb`. Grounding is measured from the lowest bind-pose vertex.
