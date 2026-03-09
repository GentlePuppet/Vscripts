printl("Running Offline Save V1.1 By GentlePuppet")
::GetSteam64ID <- function(input) {
    local sanitized = NetProps.GetPropString(input, "m_szNetworkIDString").tostring()
    sanitized = sanitized.slice(5, sanitized.len() - 1)         // [U:1:121369335] -> 121369335
    sanitized = sanitized.tointeger() + 76561197960265728       // Convert to Steam64ID
    return sanitized.tostring()
}
::Savelocation <- function(player, steamid) {
    if (player.GetFlags() & Constants.FPlayer.FL_ONGROUND) {
        if (player.GetTeam() == 2 || player.GetTeam() == 3) {
            // Get the players current view and location
            local ang = split(player.EyeAngles().ToKVString(), " ")
            local pos = split(player.GetLocalOrigin().ToKVString(), " ")
            // Covert the values to whole numbers for simplicity
            foreach (i, val in ang) {
                ang[i] = ceil(val.tofloat().tointeger()).tostring()
            }
            foreach (i, val in pos) { 
                pos[i] = ceil(val.tofloat().tointeger()).tostring()
            }
            // Put the values back together into a string
            ang = ang[0] + " " + ang[1] + " " + ang[2]
            pos = pos[0] + " " + pos[1] + " " + pos[2]
            // Save the string to file
            StringToFile("player_saves/" + GetMapName() + "/" + steamid + "/" + player.GetTeam() + player.GetPlayerClass() + ".txt", player.EyeAngles().ToKVString() + " " + player.GetOrigin().ToKVString() + "\n")
            ClientPrint(player,3,"\x04[VSCRIPT]\x01 Saved Location.")
        } else {ClientPrint(player,3,"\x04[VSCRIPT]\x01 You can only save while on a Team.")}
    }
    else {ClientPrint(player,3,"\x04[VSCRIPT]\x01 Can't Save While Airborne.")}
}
::Loadlocation <- function(player, steamid) {
    local savefile = FileToString("player_saves/" + GetMapName() + "/" + steamid + "/" + player.GetTeam() + player.GetPlayerClass() + ".txt")
    if (savefile == null) {
        ClientPrint(player,3,"\x04[VSCRIPT]\x01 No Save Found.")
    }
    else {
        local str = split(savefile, " ")
        local ang = Vector(str[0].tointeger(), str[1].tointeger(), str[2].tointeger())
        local pos = Vector(str[3].tointeger(), str[4].tointeger(), str[5].tointeger())
        local spd = Vector(0, 0, 0)
        player.SetOrigin(pos)
        player.SetAngles(ang.x, ang.y, ang.z)
        player.SetAbsVelocity(spd)
        ClientPrint(player,3,"\x04[VSCRIPT]\x01 Loaded Location.")
    }
}
local savemessage = false
getroottable()["save_teleport"] <- 
{
    OnGameEvent_player_say = function(data) {
        local player = GetPlayerFromUserID(data.userid); 
        local steamid = GetSteam64ID(player)
        local msg = data.text.tolower()        
        if(!player)
            return
        if(!player.IsPlayer())
            return
        if (msg == "!s" || msg == "/s" || msg == "!save" || msg == "/save")
            Savelocation(player, steamid)
        if (msg == "!t" || msg == "/t" || msg == "!teleport" || msg == "/teleport")
            Loadlocation(player, steamid)
        if (msg == "!r" || msg == "/r" || msg == "!reset" || msg == "/reset")
            player.ForceRespawn()
    }
    OnGameEvent_player_spawn = function(data)
    {
        local player = GetPlayerFromUserID(data.userid)
        if(!player)
            return
        if(!player.IsPlayer())
            return
		player.ValidateScriptScope()
		local scope = player.GetScriptScope()
        if ("savemessage" in scope && scope.savemessage != null) {
            return
        } else {
            ClientPrint(player,3,"\x04[VSCRIPT]\x01 Save Script is Now Running.\n\x04[VSCRIPT]\x01 Type /s to Save and /t to teleport to your Save and /r to Return to Spawn.\n\x04[VSCRIPT]\x01 These saves are accessed on this server only.")
            scope.savemessage <- true
        }
    }
}
local EventsTable = getroottable()["save_teleport"]
foreach (name, callback in EventsTable) EventsTable[name] = callback.bindenv(this)
__CollectGameEventCallbacks(EventsTable)