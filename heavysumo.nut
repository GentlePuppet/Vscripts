// Create a trigger_multiple with these Outputs:
// OnStartTouch logic_script RingEnter(activator)
// OnEndTouch logic_script RingExit(activator)
// Then create a logic_script and give it this entity script.

// Print the script version to the console.
printl("Running [Heavy Boxing] V0.4 By GentlePuppet")

// Load global toggles from the config file
::LoadConfig <- function() {
    local path = "JA2/heavysumo/config.txt"
    local data = FileToString(path)
    if (data == null) {
        StringToFile(path, "") // Create the file if it doesn't exist
        return { "CustomLoadouts" : "0" }
    }
    local toggles = {}
    foreach (line in split(strip(data), "\n")) {
        local parts = split(line, ",")
        if (parts.len() == 2) {
            toggles[parts[0]] <- parts[1]
        }
    }
    // Ensure the CustomLoadouts key is in the table with a default of 0 if not found
    if (!("CustomLoadouts" in toggles)) {
        toggles["CustomLoadouts"] <- "0"
    }
    return toggles
}
// Save a toggle value (enabled/disabled) for a feature
::SaveConfig <- function(featureName, state) {
    local path = "JA2/heavysumo/config.txt"
    local toggles = LoadConfig()
    toggles[featureName] <- state ? "1" : "0"

    // Save the updated config file
    local out = ""
    foreach (key, val in toggles) {
        out += key + "," + val + "\n"
    }
    StringToFile(path, out)

    // Update cached config
    ::CachedConfig = toggles
}
local toggles = LoadConfig()
local currentState = (toggles["CustomLoadouts"] == "0")
local enableCustomCosmetics
::CachedConfig <- LoadConfig()
if (toggles["CustomLoadouts"] == "1") {
    // Give the heavy a custom set of clothes
    // Enable custom cosmetics if the variable is set to 1
    enableCustomCosmetics = true
} else {
    enableCustomCosmetics = false
}

// Create tables to track players in the ring and their original class before they entered the ring.
local KnockbackZonePlayers = {};
local OriginalClasses = {};

// Location to teleport defeated players on respawn
// Should be near the ring so defeated players won't have to walk as far from spawn if they want to keep fighting
// Use getpos to get the location and direction for your own ring
local ringTeleport = Vector(3497, -9980, 1880)  // Location
local ringFacing = Vector(0, 76, 0)             // Direction to face, should probably face the ring, just a suggestion 

// Precache the heavy death sound used for the ragdoll
PrecacheScriptSound("Heavy.CritDeath")

//////////////////////
// Helper Functions //
//////////////////////
// Used to clamp a values and limit it's possible min/max number 
// IE if a value is 400 and the max clamp is set to 350 then the value will be set to 350. Same goes for the min clamp. 
// If the value is in between the min and max then it won't be changed. 
// IE min:100 and max:300, and a value of 120 will remain 120.
::Clamp <- function(value, min, max) {
    return value < min ? min : (value > max ? max : value);
}

// This one get's the playerID of the player you pass to the function and returns it as a value.
::GetPlayerUserID <- function(player) {
    return NetProps.GetPropIntArray(Entities.FindByClassname(null, "tf_player_manager"), "m_iUserID", player.entindex())
}

// Resupply the player
::RegeneratePlayer <- function() {
    self.Regenerate(true);
}

// This gets the players steam ID
::GetPlayerSteamID <- function(input) {
	if (input.IsPlayer())
		return NetProps.GetPropString(input, "m_szNetworkIDString").tostring()
}

::ParseSumoConfigList <- function(fileContent) {
	local lines = split(fileContent, "\n")
	local cleanLines = []
	foreach (line in lines) {
		line = strip(line)
		if (line.len() == 0 || startswith(line, "//")) {
			cleanLines.append(line)
			continue
		}

		// Extract comment if it exists
		local commentIndex = line.find("//")
		local idPart = line
		local comment = ""

		if (commentIndex != null) {
			idPart = strip(line.slice(0, commentIndex))
			comment = strip(line.slice(commentIndex))
		}

		local normalized = NormalizeSteamIDs(idPart)
		if (normalized != null) {
			// Reattach comment (with tab for formatting)
			cleanLines.append(idPart + (comment != "" ? "\t\t" + comment : ""))
		}
	}
	return cleanLines
}

// This converts any SteamID's input into a steam3ID for uniform structure.
::NormalizeSteamIDs <- function(id) {
    // Convert Steam64 → Steam3
    if (id.len() == 17 && id.find("7656119") != null) {
		local steam64 = id.tointeger()
		local accountID = steam64 - 76561197960265728
		return "[U:1:" + accountID + "]"
    }

    // Convert Legacy (STEAM_X:Y:Z) → Steam3
    if (startswith(id, "STEAM_")) {
        local parts = split(id, ":")
        local Y = parts[1].tointeger()
        local Z = parts[2].tointeger()
        local accountID = (Z * 2) + Y
        return "[U:1:" + accountID + "]"
    }

    // Already Steam3 format? Return
    if (startswith(id, "[U:1:") && endswith(id, "]")) {
        return id
    }

	// If nothing is a SteamID return null
	return null  
}

// Give Custom Cosmetics Function
::GivePlayerCosmetic <- function(player, item_id) { // Thanks https://developer.valvesoftware.com/wiki/Team_Fortress_2/Scripting/VScript_Examples#Giving_a_cosmetic
	local weapon = Entities.CreateByClassname("tf_weapon_parachute")
	NetProps.SetPropInt(weapon, "m_AttributeManager.m_Item.m_iItemDefinitionIndex", 1101)
	NetProps.SetPropBool(weapon, "m_AttributeManager.m_Item.m_bInitialized", true)
	weapon.SetTeam(player.GetTeam())
	weapon.DispatchSpawn()
	player.Weapon_Equip(weapon)
	local wearable = NetProps.GetPropEntity(weapon, "m_hExtraWearable")
	weapon.Kill()
	
	NetProps.SetPropInt(wearable, "m_AttributeManager.m_Item.m_iItemDefinitionIndex", item_id)
	NetProps.SetPropBool(wearable, "m_AttributeManager.m_Item.m_bInitialized", true)
	NetProps.SetPropBool(wearable, "m_bValidatedAttachedEntity", true)
	wearable.DispatchSpawn()
    if (item_id = 623) { 
        // If the cosmetic is a photo badge set it to the JA logo
        wearable.AddAttribute("custom texture hi", casti2f(12738526), -1)
        wearable.AddAttribute("custom texture lo", casti2f(779202576), -1)
    }

	SendGlobalGameEvent("post_inventory_application", { userid = GetPlayerUserID(player) })

	return wearable
}

// Remove all cosmetics the heavy is wearing
::RemoveCosmetics <- function(input) {
    local wearables = []
    for (local wearable = input.FirstMoveChild(); wearable != null; wearable = wearable.NextMovePeer())
    {
        if (wearable.GetClassname() != "tf_wearable")
            continue
        wearables.append(wearable)
    }
    foreach (hat in wearables)
        hat.Destroy()
}

// Snap players to the ground above them
::UnstickAndGroundPlayer <- function(input) {

    local origin = input.GetOrigin();

    local playertrace = {
        start = origin,
        end   = origin + Vector(0, 0, -512),
        mask  = 33636363, // MASK_PLAYERSOLID
        startsolid = false,
        ignore = input
    };
    TraceLineEx(playertrace);
    if (playertrace.hit && !playertrace.startsolid) {
        // The player is not in the ground
        return;
    }

    local lifted = origin + Vector(0, 0, 256);
    
    // Trace straight down to ground using player hull
    local groundtrace = {
        start = lifted,
        end   = lifted + Vector(0, 0, -512),
        mask  = 33636363, // MASK_PLAYERSOLID
        startsolid = false,
        ignore = input
    };
    TraceLineEx(groundtrace);
    
    // Snap slightly above ground if we hit something
    if (groundtrace.hit && !groundtrace.startsolid) {
        input.SetOrigin(groundtrace.endpos + Vector(0, 0, 2));
    }
}

// Delete orphaned Civ weapons
::CleanupAllGhostWeapons <- function() {
    local ent = null;
    local origin = self.GetOrigin()
    while ((ent = Entities.FindByClassname(ent, "tf_weapon_*")) != null) {
        // Ignore weapons held by players
        local owner = NetProps.GetPropEntity(ent, "m_hOwnerEntity");
        if (owner && owner.IsPlayer())
            continue;

        ent.Kill();
    }
}


///////////////////////////////////
// Functions for handling deaths //
///////////////////////////////////
// This respawns the player and then teleports them to the ringteleport location.
::DelayedRespawn <- function() {
    self.ForceRegenerateAndRespawn();
    self.SetOrigin(ringTeleport);
    self.SetAngles(ringFacing.x, ringFacing.y, ringFacing.z);
}
// This is the function the "kills" the player by creating a ragdoll of them and then forcing them to respawn via the above function
::FakeDeathAndRespawn <- function(attacker, victim, weapon, attackDir) {
    // Store victim position and angles for ragdoll creation
    local victimPos = victim.GetOrigin();
    local victimAngles = victim.EyeAngles();
    local victimIndex = victim.GetEntityIndex()
    victim.SetAbsVelocity(Vector(attackDir.x * 500, attackDir.y * 500, attackDir.z * 500));

    // Spawn a ragdoll
    local ragdoll = Entities.CreateByClassname("tf_ragdoll");
    local playerForce = NetProps.GetPropVector(victim, "m_vecForce");
    // This all sets the properties so they look like the player who "died"
    {
        NetProps.SetPropVector(ragdoll, "m_vecRagdollOrigin", victimPos)
        NetProps.SetPropVector(ragdoll, "m_vecRagdollVelocity", victim.GetAbsVelocity())
        NetProps.SetPropVector(ragdoll, "m_vecForce", playerForce)

        NetProps.SetPropInt(ragdoll, "m_nForceBone", 1)
        NetProps.SetPropInt(ragdoll, "m_iTeam", victim.GetTeam())
        NetProps.SetPropInt(ragdoll, "m_iClass", victim.GetPlayerClass())
        NetProps.SetPropInt(ragdoll, "m_iPlayerIndex", victim.GetEntityIndex())
        NetProps.SetPropEntity(ragdoll, "m_hPlayer", victim)

        NetProps.SetPropFloat(ragdoll, "m_flHeadScale", 1.0)
        NetProps.SetPropFloat(ragdoll, "m_flTorsoScale", 1.0)
        NetProps.SetPropFloat(ragdoll, "m_flHandScale", 1.0)

        // This spawns the ragdoll
        ragdoll.DispatchSpawn();
    }
    // This plays a sound on the ragdoll to fake the heavy dying yell
    EmitSoundEx({
        sound_name = "Heavy.CritDeath",
        origin = victimPos,
        speaker_entity = ragdoll
    })

    // This makes the attacker say 1 in 31 random victory voicelines
    switch (RandomInt(5, 36)) {
        case 5: attacker.PlayScene("scenes/Player/Heavy/low/1948", 2.5); break;
        case 6: attacker.PlayScene("scenes/Player/Heavy/low/1950", 2.5); break;
        case 7: attacker.PlayScene("scenes/Player/Heavy/low/2074", 2.5); break;
        case 8: attacker.PlayScene("scenes/Player/Heavy/low/2075", 2.5); break;
        case 9: attacker.PlayScene("scenes/Player/Heavy/low/2076", 2.5); break;
        case 10: attacker.PlayScene("scenes/Player/Heavy/low/2077", 2.5); break;
        case 11: attacker.PlayScene("scenes/Player/Heavy/low/2078", 2.5); break;
        case 12: attacker.PlayScene("scenes/Player/Heavy/low/2079", 2.5); break;
        case 13: attacker.PlayScene("scenes/Player/Heavy/low/2080", 2.5); break;
        case 14: attacker.PlayScene("scenes/Player/Heavy/low/2083", 2.5); break;
        case 15: attacker.PlayScene("scenes/Player/Heavy/low/2084", 2.5); break;
        case 16: attacker.PlayScene("scenes/Player/Heavy/low/2085", 2.5); break;
        case 17: attacker.PlayScene("scenes/Player/Heavy/low/2103", 2.5); break;
        case 18: attacker.PlayScene("scenes/Player/Heavy/low/2115", 2.5); break;
        case 19: attacker.PlayScene("scenes/Player/Heavy/low/2194", 2.5); break;
        case 20: attacker.PlayScene("scenes/Player/Heavy/low/2256", 2.5); break;
        case 21: attacker.PlayScene("scenes/Player/Heavy/low/235", 2.5); break;
        case 22: attacker.PlayScene("scenes/Player/Heavy/low/263", 2.5); break;
        case 23: attacker.PlayScene("scenes/Player/Heavy/low/267", 2.5); break;
        case 24: attacker.PlayScene("scenes/Player/Heavy/low/268", 2.5); break;
        case 25: attacker.PlayScene("scenes/Player/Heavy/low/269", 2.5); break;
        case 26: attacker.PlayScene("scenes/Player/Heavy/low/1268", 2.5); break;
        case 27: attacker.PlayScene("scenes/Player/Heavy/low/1269", 2.5); break;
        case 28: attacker.PlayScene("scenes/Player/Heavy/low/1272", 2.5); break;
        case 29: attacker.PlayScene("scenes/Player/Heavy/low/270", 2.5); break;
        case 30: attacker.PlayScene("scenes/Player/Heavy/low/271", 2.5); break;
        case 31: attacker.PlayScene("scenes/Player/Heavy/low/2067", 2.5); break;
        case 32: attacker.PlayScene("scenes/Player/Heavy/low/2265", 2.5); break;
        case 33: attacker.PlayScene("scenes/Player/Heavy/low/2266", 2.5); break;
        case 34: attacker.PlayScene("scenes/Player/Heavy/low/303", 2.5); break;
        case 35: attacker.PlayScene("scenes/Player/Heavy/low/304", 2.5); break;
        case 36: attacker.PlayScene("scenes/Player/Heavy/low/336", 2.5); break;
        default:
    }
    
    EntFireByHandle(ragdoll, "kill", "", 5, null, null);

    // Trigger a killfeed notification
    local weaponID = NetProps.GetPropInt(weapon, "m_AttributeManager.m_Item.m_iItemDefinitionIndex")
    local weaponClass = weapon.GetClassname()
    local weaponName = ""
    if (weaponID == 474) weaponName = "The Conscientious Objector"
    else                weaponName = "The Killing Gloves Of Boxing"

    SendGlobalGameEvent("player_death", {
        userid = GetPlayerUserID(victim),
        attacker = GetPlayerUserID(attacker),
        weapon = weaponClass,
        weapon_logclassname = weaponName,
        weaponid = weaponID,
        weapon_def_index = weaponID,
        crit_type = 0
    });

    // Respawn the victim instantly to avoid actual death
    EntFireByHandle(victim, "CallScriptFunction", "DelayedRespawn", 0.1, null, null);
    
}

//////////////////////////////////////////////
// Functions for dealing damage in the ring //
//////////////////////////////////////////////
::ApplyKnockback <- function(attacker, victim, weapon) { 
    ///////////////////////////
    // Configurable varibles //
    ///////////////////////////
    local
    // Base damage per hit
    baseDamage = 10,
    // Minimum damage per hit
    minDamage = 10,
    // Maximum damage per hit
    maxDamage = 50,
    // Base horizontal knockback 
    baseForce = 35,
    // Minimum horizontal knockback
    minForce = 0,
    // Maximum horizontal knockback
    maxForce = 175,
    // Base vertical knockback strength
    baseUpwardForce = 250,
    // Minimum vertical knockback strength
    minUpwardForce = 251,
    // Maximum vertical knockback strength
    maxUpwardForce = 300,

    // Get attacker's forward direction
    attackDir = attacker.EyeAngles().Forward(), 
    // Get attacker's velocity
    attackerVelocity = attacker.GetAbsVelocity(), 
    // Attackers forward facing direction and their velocity in the same direction
    forwardSpeed = abs((attackDir.x * attackerVelocity.x) + (attackDir.y * attackerVelocity.y)), 
    // Get victim's forward direction
    victimDir = victim.EyeAngles().Forward(), 
    // Get victim's velocity
    victimVelocity = victim.GetAbsVelocity(), 
    // Forward movement checks
    attackerMovingForward = ((attackerVelocity.x >= 0 && attackDir.x >= 0) || (attackerVelocity.x < 0 && attackDir.x < 0)) && ((attackerVelocity.y >= 0 && attackDir.y >= 0) || (attackerVelocity.y < 0 && attackDir.y < 0)),
    victimMovingForward = ((victimVelocity.x >= 0 && victimDir.x >= 0) || (victimVelocity.x < 0 && victimDir.x < 0)) && ((victimVelocity.y >= 0 && victimDir.y >= 0) || (victimVelocity.y < 0 && victimDir.y < 0)),

    // Movement modifiers
    attackerModifier = 1,
    victimModifier = 1,
    attackerDamageModifier = 1,
    victimDamageModifier = 1,
    victimUpModifier = 1;

    // Determine attacker modifier (1.25 for moving forward, 0.75 for moving backward)
    {
        if ((attackerVelocity.x == 0 && attackerVelocity.y == 0)) {
        } else if (attackerMovingForward) {
            attackerModifier = 1.25;
            attackerDamageModifier = 1.25;
        } else if (!attackerMovingForward) {
            attackerModifier = 0.75;
            attackerDamageModifier = 0.5; 
        }
    }

    // Determine victim modifiers (0.75 for moving forward, 1.25 for moving backward)
    {
        if ((victimVelocity.x == 0 && victimVelocity.y == 0)) {
        } else if (victimMovingForward) {
            victimModifier = 0.75;
            victimDamageModifier = 1.25;
        } else if (!victimMovingForward) {
            victimModifier = 1.25;
            victimDamageModifier = 0.5; 
        } 
        local victimUpModifier = 1;
        if ((victimVelocity.z > 0)) {
            victimUpModifier = 1.25; // 25% more knockback if airborne
        }
    }

    // Apply Modifiers
    {
        // Apply modifiers, Clamp, and Round to the base knockback force
        baseForce = Clamp(abs((((baseForce + (forwardSpeed * 0.50)) * attackerModifier) * victimModifier)), minForce, maxForce);

        // Apply modifiers, Clamp, and Round vertical knockback force
        baseUpwardForce = Clamp(abs((baseUpwardForce + (forwardSpeed * 0.30) * victimUpModifier)), minUpwardForce, maxUpwardForce);

        // Apply modifiers, Clamp, and Round damage
        baseDamage = Clamp(abs(((baseDamage + (forwardSpeed * 0.10) * attackerDamageModifier) * victimDamageModifier)), minDamage, maxDamage);
    }

    // Debug damage for quickly testing kills
    if (0 == 1) 
        baseDamage = 500

    // Display hitmarkers and damage numbers
    SendGlobalGameEvent("player_hurt", {
        userid = GetPlayerUserID(victim)
        health = victim.GetHealth()
        attacker = GetPlayerUserID(attacker)
        damageamount = baseDamage
        weaponid = 43
        bonuseffect = 7
    })

    // Reward Attacker for their kill
    if (baseDamage > victim.GetHealth()) { // Check if the damage dealth to the Victim will kill them
        // Give the attacker a point
        SendGlobalGameEvent("player_escort_score", {attacker = attacker.entindex(), points = 1})
        SendGlobalGameEvent("player_healed", {patient = attacker.entindex(), healer = attacker.entindex(), amount = 50})
        // "Kill" the victim
        FakeDeathAndRespawn(attacker, victim, self, attackDir)
    } else { // If damage won't kill them do a normal attack and knockback
        // Deal Damage
        victim.TakeDamageCustom(
            self, 
            victim, 
            weapon, 
            Vector(0.01,0.01,0.01),
            Vector(0.01,0.01,0.01), 
            baseDamage, 
            2048, 
            37
        )

        // Deal Knockback
        victim.SetAbsVelocity(Vector(attackDir.x * baseForce, attackDir.y * baseForce, baseUpwardForce));
    }
}
::CheckMeleeAttack <- function() { // Thanks https://developer.valvesoftware.com/wiki/Team_Fortress_2/Scripting/VScript_Examples#Detecting_weapon_firing
	// Check if the weapon still exists
    if(!CBaseEntity.IsValid.call(self)) return;

    local attacker = self.GetOwner();
    if (!attacker || !(attacker.GetEntityIndex() in KnockbackZonePlayers)) return -1;

    // Detect melee swing
    if (NetProps.GetPropInt(attacker, "m_Shared.m_iNextMeleeCrit") == 0)
    {
        if (attacker.GetActiveWeapon() == self)
        {
            local trace = {
                start = attacker.EyePosition() // The attackers eye position
                end = attacker.EyePosition() + (attacker.EyeAngles().Forward() * 70)
                ignore = attacker // Don't hit ourself, obviously
            }
            local victim = TraceLineEx(trace); // Variable to check for if we hit a player

            if (trace) // Check if trace fired
                if (trace.hit) // Check if trace hit something
                    if ((trace.enthit.GetClassname() == "player")) // Check if the trace hit a player
                        if (trace.enthit.GetEntityIndex() in KnockbackZonePlayers) // Check if they in the knockback table
                            ApplyKnockback(attacker, trace.enthit, self); // Knock them back, obviously
        }

        // Reset melee detection
        NetProps.SetPropInt(attacker, "m_Shared.m_iNextMeleeCrit", -2);
    }

    return -1;
}


////////////////////////////////////
// Simple Config for Admin Usage //
//////////////////////////////////
local adminsFile = FileToString("JA2/heavysumo/Admins.txt") // Saved to "tf/scriptdata/JA2/heavysumo/Admins.txt"
if (adminsFile == null || strip(adminsFile) == "") {
    StringToFile("JA2/heavysumo/Admins.txt", "// List of Steam IDs that allow players to use the sumo commands.\n[U:1:121369335]\t\t// Gentle Puppet\n\n[U:1:22202]\t\t// Gaben Newell\nSTEAM_1:1:16\t\t// BAILOPAN\n76561197960435530\t\t// Robin Walker\n")
	::Admins <- ParseSumoConfigList(adminsFile)
} else {
	::Admins <- ParseSumoConfigList(adminsFile)
}
::CheckSumoAdmins <- function(input) {
	local playerid = GetPlayerSteamID(input)
	local normalizedInput = NormalizeSteamIDs(playerid)

	if (input == GetListenServerHost()) {return true}
    if (playerid == "BOT") {return false}
    if (normalizedInput == null) {return false}
	
	foreach (id in Admins) {
		local normalizedID = NormalizeSteamIDs(id)
		if (normalizedID == normalizedInput) return true
	}
    return false
}
::CheckSumoPerms <- function(input) {
	local playerid = GetPlayerSteamID(input)
	local normalizedInput = NormalizeSteamIDs(playerid)

	if (input == GetListenServerHost()) {return true}
    if (playerid == "BOT") {return false}
    if (normalizedInput == null) {return false}

    // Check against default JA IDs
    local defaultList = split(defaultJAIDs, " ")
    foreach (defaultID in defaultList) {
        local normalizedDefault = NormalizeSteamIDs(defaultID)
        if (normalizedDefault != null && normalizedDefault == normalizedInput) {
            return true
        }
    }

    // Check user-added sumoIDs (lines like "ID\t\t// alias")
	foreach (id in sumoIDs) {
		local normalizedID = NormalizeSteamIDs(id)
		if (normalizedID == normalizedInput) return true
	}

    return false
}


/////////////////////////////////////////
// Functions for touching the triggers //
/////////////////////////////////////////
// Player Entered Trigger / Broke up into parts with a delay to reduce doing too much, all at once.
::RingEnter <- function(input) {
    // Check if the activator is a player
    if (!input || !input.IsPlayer()) return;

    // Get the player's server index
    local playerIndex = input.GetEntityIndex(); 

    // Store original class if not already stored
    if (!(playerIndex in OriginalClasses)) {
        // Add player and class to original class table
        OriginalClasses[playerIndex] <- NetProps.GetPropInt(input, "m_PlayerClass.m_iClass");
    }   

    EntFireByHandle(input, "CallScriptFunction", "ChangeToHeavy", 0.05, null, null);
}
::ChangeToHeavy <- function() {
    // Change to Heavy
    self.SetPlayerClass(6);
    NetProps.SetPropInt(self, "m_Shared.m_iDesiredPlayerClass", 6);
    EntFireByHandle(self, "CallScriptFunction", "RegeneratePlayer", 0.01, null, null);
    EntFireByHandle(self, "CallScriptFunction", "SetWeapon", 0.05, null, null);
}
::SetWeapon <- function() {
    local playerID = NetProps.GetPropString(self,"m_szNetworkIDString").tostring()
    local RandomPercent = RandomInt(0, 10)
    local type = "Default"

    // Handle Custom Boxing Cosmetics
    {
        // Give the heavy a custom set of clothes
        if (CachedConfig["CustomLoadouts"] == "1") {
            switch (RandomPercent) {
                case 0: // Luchadore
                    type = "Luchadore"
                    RemoveCosmetics(self)
                    GivePlayerCosmetic(self, 380)      // Large Luchadore
                    GivePlayerCosmetic(self, 30080)    // The Heavy-Weight Champ
                    GivePlayerCosmetic(self, 30342)    // Heavy Lifter
                    ClientPrint(self, 3, "\x04[Heavy Boxing]\x01 You've received the \x03Luchadore\x01 Costume Set!")
                    break

                case 1: // Boxer
                    type = "Boxer"
                    RemoveCosmetics(self)
                    GivePlayerCosmetic(self, 246)      // Pugilist's Protector
                    GivePlayerCosmetic(self, 757)      // The Toss-Proof Towel
                    GivePlayerCosmetic(self, 30178)    // Weight Room Warmer
                    ClientPrint(self, 3, "\x04[Heavy Boxing]\x01 You've received the \x03Boxer\x01 Costume Set!")
                    break

                case 2: // Yeti
                    type = "Yeti"
                    RemoveCosmetics(self)
                    GivePlayerCosmetic(self, 1187)    // Yeti Head
                    GivePlayerCosmetic(self, 1188)    // Yeti Arms
                    GivePlayerCosmetic(self, 1189)    // Yeti Legs
                    ClientPrint(self, 3, "\x04[Heavy Boxing]\x01 You've received the \x03Yeti\x01 Costume Set!")
                    break

                case 3: // Carl
                    type = "Carl"
                    RemoveCosmetics(self)
                    GivePlayerCosmetic(self, 989)    // The Carl
                    GivePlayerCosmetic(self, 990)    // Aqua Flops
                    GivePlayerCosmetic(self, 991)    // The Hunger Force
                    ClientPrint(self, 3, "\x04[Heavy Boxing]\x01 You've received the \x03Carl\x01 Costume Set!")
                    break

                case 4: // Santa
                    type = "Santa"
                    RemoveCosmetics(self)
                    GivePlayerCosmetic(self, 666)    // B.M.O.C
                    GivePlayerCosmetic(self, 647)    // All-Father
                    GivePlayerCosmetic(self, 30747)    // Gift Bringer
                    ClientPrint(self, 3, "\x04[Heavy Boxing]\x01 You've received the \x03Santa\x01 Costume Set!")
                    break

                case 5: // Tank
                    type = "Tank"
                    RemoveCosmetics(self)
                    GivePlayerCosmetic(self, 1087)    // Der Maschinensoldaten-Helm
                    GivePlayerCosmetic(self, 1088)    // Die Regime-Panzerung
                    GivePlayerCosmetic(self, 524)    // Purity Fist
                    ClientPrint(self, 3, "\x04[Heavy Boxing]\x01 You've received the \x03Tank\x01 Costume Set!")
                    break

                case 6: // Sensi
                    type = "Sensi"
                    RemoveCosmetics(self)
                    GivePlayerCosmetic(self, 647)    // All-Father
                    GivePlayerCosmetic(self, 30177)    // Hong Kong Cone
                    GivePlayerCosmetic(self, 30342)    // Heavy Lifter
                    ClientPrint(self, 3, "\x04[Heavy Boxing]\x01 You've received the \x03Sensi\x01 Costume Set!")
                    break

                case 7: // Batmann
                    type = "Batmann"
                    RemoveCosmetics(self)
                    GivePlayerCosmetic(self, 30738)    // Batbelt
                    GivePlayerCosmetic(self, 30720)    // Arkham Cowl
                    GivePlayerCosmetic(self, 30309)    // Dead of Night
                    ClientPrint(self, 3, "\x04[Heavy Boxing]\x01 You've received the \x03Batmann\x01 Costume Set!")
                    break

                case 8: // 'Cop'
                    type = "Cop"
                    RemoveCosmetics(self)
                    GivePlayerCosmetic(self, 30362)    // Law
                    GivePlayerCosmetic(self, 30085)    // Macho Mann
                    GivePlayerCosmetic(self, 30563)    // Jungle Booty
                    GivePlayerCosmetic(self, 30342)    // Heavy Lifter
                    ClientPrint(self, 3, "\x04[Heavy Boxing]\x01 You've received the \x03'Definitely a Real Cop'\x01 Costume Set!")
                    break

                case 9: // 'Poot Nukem'
                    type = "Poot Nukem"
                    RemoveCosmetics(self)
                    GivePlayerCosmetic(self, 30344)    // Bullet Buzz
                    GivePlayerCosmetic(self, 30104)    // Graybanns
                    GivePlayerCosmetic(self, 30342)    // Heavy Lifter
                    ClientPrint(self, 3, "\x04[Heavy Boxing]\x01 You've received the \x03'Poot Nukem'\x01 Costume Set!")
                    break

                default: // No Custom Outfit
                    type = "Default"
                    break
            }
        }
        
        if (CheckSumoPerms(self)) { 
            GivePlayerCosmetic(self, 623) // JA Branded Photo Badge
        }
    }

    // Apply Melee Weapon
    {
        for(local i = 0; i < 8; i++) 
        {
            local wep = NetProps.GetPropEntityArray(self,"m_hMyWeapons",i)
            if(CBaseEntity.IsValid.call(wep) && wep.GetSlot() == 2)
            {
                wep.Kill()
            }
        }
        // Give Objector or KGB
        local weaponID = null
        local weaponname = ""
        // 5% chance to get a JA Branded Objector
        if (CheckSumoPerms(self)) {
            weaponID = 474 // Objector
            weaponname = "tf_weapon_fireaxe"
        } else if (RandomInt(1, 100) <= 5) { 
            ClientPrint(self, 3, "\x04[Heavy Boxing]\x01 You've received the \x03JA Objector\x01!")
            weaponID = 474 // Objector
            weaponname = "tf_weapon_fireaxe"
        } else {
            weaponID = 43
            weaponname = "tf_weapon_fists"
            
            if (CachedConfig["CustomLoadouts"] == "1") {
                switch (type) {
                    case "Luchadore":
                        weaponID = 239 // GRU
                        break

                    case "Boxer":
                        weaponID = 43 // KGB
                        break

                    case "Yeti":
                        weaponID = 1127 // The Crossing Guard
                        break

                    case "Carl":
                        weaponID = 426 // Eviction Notice
                        break

                    case "Santa":
                        weaponID = 656 // Holiday Punch
                        break

                    case "Tank":
                        weaponID = 331 // Fists of Steel
                        break

                    case "Sensi":
                        weaponID = 1123 // Necro Smasher
                        break

                    case "Batmann":
                        weaponID = 880 // The Freedom Staff
                        break

                    case "Cop":
                        weaponID = 954 // Memory Maker
                        break

                    case "Poot Nukem":
                        weaponID = 5 // Fists
                        break

                    case "Default":
                        weaponID = 43 // Default KGB
                        break

                    default:
                        weaponID = 43 // Default KGB
                        break
                }
            }
        }
        // Create the new weapon
        local weapon = Entities.CreateByClassname(weaponname)
        NetProps.SetPropInt(weapon, "m_AttributeManager.m_Item.m_iItemDefinitionIndex", weaponID)

        if (RandomInt(1, 100) <= 50)
            NetProps.SetPropInt(weapon, "m_AttributeManager.m_Item.m_iEntityLevel", 69)
        else
            NetProps.SetPropInt(weapon, "m_AttributeManager.m_Item.m_iEntityLevel", 42)

        NetProps.SetPropBool(weapon, "m_bValidatedAttachedEntity", true)
        NetProps.SetPropBool(weapon, "m_AttributeManager.m_Item.m_bInitialized", true)
        weapon.SetTeam(self.GetTeam())
        weapon.DispatchSpawn()

        // If the weapon is an objector set the decal to the JA logo
        if (weaponID == 474) { 
            weapon.AddAttribute("custom texture hi", casti2f(12738526), -1)
            weapon.AddAttribute("custom texture lo", casti2f(779202576), -1)
        }

        // Remove the Eviction attack speed
        if (weaponID == 426) {
            weapon.AddAttribute("fire rate bonus", 1, -1)
            weapon.AddAttribute("mult_player_movespeed_active", 1, -1)
            weapon.AddAttribute("mod_maxhealth_drain_rate", 1, -1)
            weapon.AddAttribute("speed_boost_on_hit", 1, -1)
        }

        // Remove the GRU's health drain and penalty
        if (weaponID == 239) { 
            weapon.AddAttribute("mod_maxhealth_drain_rate", 0, -1)
            weapon.AddAttribute("lunchbox adds minicrits", 0, -1)
            weapon.AddAttribute("single wep holster time increased", 1, -1)
            weapon.AddAttribute("mult_player_movespeed_active", 1, -1)
        }

        // Remove the Fists of Steel Melee penalty
        if (weaponID == 239) { 
            weapon.AddAttribute("dmg from melee increased", 1, -1)
            weapon.AddAttribute("dmg from ranged reduced", 1, -1)
            weapon.AddAttribute("single wep holster time increased", 1, -1)
        }

        // Make the weapons match the slightly slower attack speed of the KGB
        weapon.AddAttribute("fire rate penalty", 1.2, -1)

        // Equip the weapon on the heavy
        self.Weapon_Equip(weapon)
        NetProps.SetPropEntity(self, "m_hActiveWeapon", null)	
        // Remove reving and sniper aiming conditions
        self.RemoveCond(Constants.ETFCond.TF_COND_AIMING)
        self.RemoveCond(Constants.ETFCond.TF_COND_ZOOMED)
        // Switch to the weapon
        self.Weapon_Switch(weapon)
        // Add the melee check function
        NetProps.SetPropInt(self, "m_Shared.m_iNextMeleeCrit", -2)
        AddThinkToEnt(weapon, "CheckMeleeAttack")
        // Lock the heavy to melee only
        self.AddCond(Constants.ETFCond.TF_COND_CANNOT_SWITCH_FROM_MELEE)
    }

    // Add the heavy to knockback tracking table
    local playerIndex = self.GetEntityIndex(); // Get the player's server index
    KnockbackZonePlayers[playerIndex] <- true; // Add player to knockback table (this is used to check if a player is in the ring, only players in the ring can be hit by others)
}

// Player Exited Trigger
::RingExit <- function(input) {
    if (!input || !input.IsPlayer()) {return;} // Check if the activator is a player

    local playerIndex = input.GetEntityIndex(); // Get the player's server index
    
    // Remove melee detection to the player's weapon
    // Thanks https://developer.valvesoftware.com/wiki/Team_Fortress_2/Scripting/VScript_Examples#Detecting_weapon_firing
    for (local i = 0; i < 8; i++) {
        local weapon = NetProps.GetPropEntityArray(input, "m_hMyWeapons", i);
        if (weapon && weapon.IsMeleeWeapon()) {
            NetProps.SetPropString(weapon, "m_iszScriptThinkFunction", "");
            break;
        }
    }
    // Remove their melee lock
    input.RemoveCond(Constants.ETFCond.TF_COND_CANNOT_SWITCH_FROM_MELEE) 
    
    // Remove all given cosmetics
    RemoveCosmetics(input)

    // Restore original class if it was stored
    if (playerIndex in OriginalClasses) // Check the original class table for the player
    {
        // Get the player from the orginal class table
        local originalClass = OriginalClasses[playerIndex]; 
        // Restore original class
        input.SetPlayerClass(originalClass);
        NetProps.SetPropInt(input, "m_Shared.m_iDesiredPlayerClass", originalClass);
        // Remove player from the orginal class table            
        delete OriginalClasses[playerIndex];                
    }

    // Remove from tracking table
    if (playerIndex in KnockbackZonePlayers) // Check the knockback table for the player
    {
        delete KnockbackZonePlayers[playerIndex]; // Remove player from knockback table
    }

    EntFireByHandle(input, "CallScriptFunction", "RegeneratePlayer", 0.01, null, null);
    EntFireByHandle(input, "CallScriptFunction", "CleanRing", 0.03, null, null);
}
::CleanRing <- function() {
    // Remove nearby dropped weapons
    if (Entities.FindByClassnameNearest("tf_dropped_weapon", self.GetOrigin(), 200))
        EntFire("tf_dropped_weapon", "kill", null, 0)
    
    // Backup to delete any orphaned weapons if they exist
    EntFire("worldspawn", "CallScriptFunction", "CleanupAllGhostWeapons", 1.0)
}


/////////////////////////////////////////////////////
// Special filter list for the JA branded Objector //
/////////////////////////////////////////////////////
// These listed users are the Map updater, JA Admins, and Pinecone; who donated the JA Objector used as the reference for the script.
//                 Gentle          Volkan          AI            Squid           Grandma         Adolf          Pinecone donated a JA Objector for the reference.
::defaultJAIDs <- "[U:1:121369335] [U:1:166628253] [U:1:4090272] [U:1:299484545] [U:1:232154211] [U:1:64288039] [U:1:219865847]"
 
local sumofile = FileToString("JA2/heavysumo/sumoIDs.txt")
if (sumofile == null || strip(sumofile) == "") {
    // File doesn't exist or is empty, create it and initialize sumoIDs as the default list
    StringToFile("JA2/heavysumo/sumoIDs.txt", "// List of Steam IDs that are given a JA Sign.\n[U:1:22202]\t\t// Gaben Newell\nSTEAM_1:1:16\t\t// BAILOPAN\n76561197960435530\t\t// Robin Walker\n")
    sumofile = FileToString("JA2/heavysumo/sumoIDs.txt")
    ::sumoIDs <- split(strip(sumofile), "\n")
} else {
    // Split file contents into sumoIDs list
    ::sumoIDs <- split(strip(sumofile), "\n")
}
::AddToSumoList <- function(text, player) {
    local sumoFilePath = "JA2/heavysumo/sumoIDs.txt"
    local sumoFileContent = FileToString(sumoFilePath)
    local sumoExtraList = split(sumoFileContent, "\n") // Unnormalized lines
    
    local rawArgs = strip(text.slice(10))
    local parts = split(rawArgs, " ")

    if (parts.len() < 2) {
        ClientPrint(player, 3, "Failed to find both ID and alias.")
        ClientPrint(player, 3, "\x04[Heavy Boxing]\x01 Usage: $sumolist <ID> <Alias>")
        return
    }

    local rawID = strip(parts[0])
    local alias = strip(rawArgs.slice(rawID.len() + 1))

    if (alias.len() > 32) {
        alias = alias.slice(0, 32)
    }

    local normalizedInputID = NormalizeSteamIDs(rawID)
    if (normalizedInputID == null) {
        ClientPrint(player, 3, "Invalid ID format.")
        ClientPrint(player, 3, "\x04[Heavy Boxing]\x01 Usage: $sumolist <ID> <Alias>")
        return
    }

    // Check if ID is in defaultJAIDs to prevent duplicates
    if (defaultJAIDs.find(normalizedInputID) != null) {
        ClientPrint(player, 3, "\x04[Heavy Boxing]\x01 ID is in default JA list and cannot be added.")
        return
    }

    local replaced = false

    // Check existing list for matching normalized ID and update alias if found
    for (local i = 0; i < sumoExtraList.len(); i++) {
        local line = sumoExtraList[i]
        if (strip(line) == "" || startswith(strip(line), "//")) continue

        local commentPos = line.find("//")
        local idPart = (commentPos != null) ? strip(line.slice(0, commentPos)) : strip(line)
        local normalizedExisting = NormalizeSteamIDs(idPart)

        if (normalizedExisting != null && normalizedExisting == normalizedInputID) {
            // Replace alias for existing ID, preserving format
            sumoExtraList[i] = idPart + "\t\t// " + alias
            replaced = true
            break
        }
    }

    if (!replaced) {
        // New entry with tab and comment formatting
        local newEntry = normalizedInputID + "\t\t// " + alias
        sumoExtraList.append(newEntry)
        ClientPrint(player, 3, "\x04[Heavy Boxing]\x01 Added: " + rawID + " (" + alias + ")")
        ClientPrint(player, 3, "\x04[Heavy Boxing]\x01 Usage: $removesumolist <ID/Name>")
    } else {
        ClientPrint(player, 3, "\x04[Heavy Boxing]\x01 Updated alias for ID: " + rawID + " (" + alias + ")")
    }

    // Write back to file
    local outString = ""
    foreach (line in sumoExtraList) {
        outString += line + "\n"
    }
    StringToFile(sumoFilePath, strip(outString) + "\n")

    // Reinitialize global sumoIDs variable with normalized list
    local newSumoFileContent = FileToString(sumoFilePath)
    ::sumoIDs <- ParseSumoConfigList(newSumoFileContent)
}
::ShowSumoList <- function(input) {
    local fileData = FileToString("JA2/heavysumo/sumoIDs.txt")
    if (fileData == null || strip(fileData) == "") {
        ClientPrint(input, 3, "\x04[Heavy Boxing]\x01 Sumo List is empty.")
        return
    }

    local sumoExtraList = split(strip(fileData), "\n")
    ClientPrint(input, 3, "\x04[Heavy Boxing]\x01 Allowed Players:\n")

    foreach (entry in sumoExtraList) {
        local parts = split(entry, ",")
        if (parts.len() >= 2) {
            ClientPrint(input, 3, "\x04[Allowed]\x01 " + parts[0] + " - " + parts[1])
        } else if (parts.len() == 1 && parts[0] != "") {
            ClientPrint(input, 3, "\x04[Allowed]\x01 " + parts[0])
        }
    }
}
::RemoveFromSumoList <- function(text, player) {
    local searchTerm = strip(text.slice(16))  // Extract argument after "$removesumolist "
    
    if (searchTerm == "") {
        ClientPrint(player, 3, "\x04[Heavy Boxing]\x01 Usage: $removesumolist <ID/Name>")
        return
    }

    local sumoFilePath = "JA2/heavysumo/sumoIDs.txt"
    local sumoExtraList = split(FileToString(sumoFilePath), "\n")
    local found = false
    local normalizedSearchID = NormalizeSteamIDs(searchTerm)

    for (local i = 0; i < sumoExtraList.len(); i++) {
        local line = sumoExtraList[i]
        if (strip(line) == "" || startswith(strip(line), "//")) continue

        local commentPos = line.find("//")
        local idPart = (commentPos != null) ? strip(line.slice(0, commentPos)) : strip(line)
        local aliasPart = (commentPos != null) ? strip(line.slice(commentPos + 2)) : ""

        local normalizedExistingID = NormalizeSteamIDs(idPart)

        // Check if searchTerm matches ID (normalized) or alias (case-insensitive)
        if ((normalizedSearchID != null && normalizedSearchID == normalizedExistingID) || 
            (aliasPart.len() > 0 && aliasPart.tolower() == searchTerm.tolower())) {
            sumoExtraList.remove(i)
            found = true
            break
        }
    }

    if (found) {
        // Save updated list back to file
        local outString = ""
        foreach (line in sumoExtraList) {
            outString += line + "\n"
        }
        StringToFile(sumoFilePath, strip(outString) + "\n")

        ClientPrint(player, 3, "\x04[Heavy Boxing]\x01 Removed: " + searchTerm)

        // Reload the sumoIDs global with normalized parsed list
        local newSumoFileContent = FileToString(sumoFilePath)
        ::sumoIDs <- ParseConfigList(newSumoFileContent)
    } else {
        ClientPrint(player, 3, "\x04[Heavy Boxing]\x01 No matching entry found for: " + searchTerm)
    }
}

// Chat event for player commands
getroottable()["chatcommands"] <- {
    OnGameEvent_player_say = function(data) {
        local player = GetPlayerFromUserID(data.userid)
        local playerID = NetProps.GetPropString(player, "m_szNetworkIDString").tostring()
        local msg = data.text

        // Early exit for commands not starting with $costumes, $sumolist or $removesumolist
        if (!(startswith(msg, "$costumes") || startswith(msg, "$sumolist") || startswith(msg, "$removesumolist"))) {
            return
        }

        // Helper for permission check
        local hasPerm = defaultJAIDs.find(playerID) != null

        if (startswith(msg, "$costumes")) {
            if (!CheckSumoAdmins(player)) {
                ClientPrint(player, 3, "\x04[Heavy Boxing]\x01 You don't have permission to use this command.")
                return
            }
            local currentState = ("CustomLoadouts" in CachedConfig && CachedConfig["CustomLoadouts"] == "1")
            SaveConfig("CustomLoadouts", !currentState)
            local newState = !currentState ? "enabled" : "disabled"
            ClientPrint(player, 3, "\x04[Heavy Boxing]\x01 Custom Loadouts are now " + newState + ".")
            return
        }

        if (startswith(msg, "$sumolist") && msg.len() >= 11) {
            if (!CheckSumoAdmins(player)) {
                ClientPrint(player, 3, "\x04[Heavy Boxing]\x01 You don’t have permission to use that.")
                return
            }
            AddToSumoList(msg, player)
            return
        }

        if (msg == "$sumolist") {
            ShowSumoList(player)
            return
        }

        if (startswith(msg, "$removesumolist") && msg.len() >= 16) {
            if (!CheckSumoAdmins(player)) {
                ClientPrint(player, 3, "\x04[Heavy Boxing]\x01 You don’t have permission to use that.")
                return
            }
            RemoveFromSumoList(msg, player)
            return
        }
    }
}


// Bind the event callbacks
local EventsTable = getroottable()["chatcommands"]
foreach (name, callback in EventsTable) EventsTable[name] = callback.bindenv(this)
__CollectGameEventCallbacks(EventsTable)