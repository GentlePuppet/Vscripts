# Gentle's TF2 Vscripts
This is where I store any of the vscripts I make for tf2.

Anyone is free to use and modify these scripts.

Do Not Sell Them.

I would like if you credit me should you do use or modify any of them.

Have fun!

---

## [Offline Save](https://github.com/GentlePuppet/Vscripts/blob/main/save.nut)

This script adds chat commands to save your current location on a map.<br>
Saves are stored in `tf/scriptdata/player_saves/[map]/[steamid]/[team][class].txt`

**Chat Commands**

* `/s`, `!s`, `/save`, `!save` - Save your location.
* `/t`, `!t`, `/teleport`, `!teleport` - Teleport to your saved spot.
* `/r`, `!r`, `/reset`, `!reset` - Return to the map spawn.

---

## [Heavy Boxing Script](https://github.com/GentlePuppet/Vscripts/blob/main/heavysumo.nut)

This script converts players who enter a designated ring area into melee-only Heavy fighters for a “sumo/boxing” style minigame.<br>
This is designed to work for teamlocked maps so you can fight teammates.

When a player enters the ring, the script temporarily forces them to the Heavy class.<br>
If costumes are enabled (disabled by default) then it also removes their current cosmetics, and assigns a random predefined themed costume set.<br>
Each costume also gives a themed weapon when costumes are enabled.

The player’s normal loadout is replaced with a single melee weapon. All other weapons are removed and weapon switching is disabled to enforce melee-only.<br>
Any themed weapons are modified to make them act the same as the boxing gloves, for fair balance.

Special players listed in a config file, with some being hardcoded as special thanks, receive a **JA-branded Objector** and JA-Branded Photobadge.
Additional IDs can be added or removed using chat commands, and the list is stored in `tf/scriptdata/JA2/heavysumo/sumoIDs.txt`.

The script also tracks which players are inside the ring so only participants can damage each other.<br>
When a player exits the ring their original class and weapons are restored.

**Chat Commands**

* *`$costumes` – Toggle custom costume loadouts on/off.
* *`$sumolist <SteamID> <Alias>` – Add a SteamID in the special players JA Objector list.
* *`$removesumolist <ID/Name>` – Remove an entry from the list.
* `$sumolist` – Display the current list.

*Usage requires either host or player to be in the `tf/scriptdata/JA2/heavysumo/Admins.txt`.

To use the script create a logic_script and a trigger multiple for the area you want the boxing to be in your map and give it the outputs
`OnStartTouch logic_script RunsScriptCode RingEnter(activator)`
`OnEndTouch logic_script RunScriptCode RingExit(activator)`

The script is fairly clearly written and commented so it should be easy to read, even if you don't know vscript.


  
