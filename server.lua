local QBCore = exports['qb-core']:GetCoreObject()
local discord_webhook = "" -- paste your discord webhook between the quotes if you want to enable discord logs.
local bancache, namecache = {}, {}
local open_assists, active_assists = {}, {}

function split(s, delimiter)
    result = {};
    for match in (s .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match)
    end
    return result
end

local function rPrint(s, l, i) -- recursive Print (structure, limit, indent)
    l = (l) or 100;
    i = i or ""; -- default item limit, indent string
    if (l < 1) then
        print "ERROR: Item limit reached.";
        return l - 1
    end
    local ts = type(s);
    if (ts ~= "table") then
        print(i, ts, s);
        return l - 1
    end
    print(i, ts); -- print "table"
    for k, v in pairs(s) do -- print "[KEY] VALUE"
        l = rPrint(v, l, i .. "\t[" .. tostring(k) .. "]");
        if (l < 0) then break end
    end
    return l
end

Citizen.CreateThread(function() -- startup
    sendToDiscord("el_bwh has been started...")

    QBCore.Functions.CreateCallback("el_bwh:ban",
                                    function(source, cb, target, reason, length,
                                             offline)
        if not target or not reason then return end
        local trgt = tonumber(target)
        local xPlayer = QBCore.Functions.GetPlayer(source)
        local xTarget = QBCore.Functions.GetPlayer(trgt)
        if not xPlayer or (not xTarget and not offline) then
            cb(nil);
            return
        end
        if isAdmin(xPlayer) then
            local success, reason = banPlayer(xPlayer,
                                              offline and target or xTarget,
                                              reason, length, offline)
            cb(success, reason)
        else
            logUnfairUse(xPlayer);
            cb(false)
        end
    end)

    QBCore.Functions.CreateCallback("el_bwh:warn",
                                    function(source, cb, target, message, anon)
        if not target or not message then return end
        local trgt = tonumber(target)
        local xPlayer = QBCore.Functions.GetPlayer(source)
        local xTarget = QBCore.Functions.GetPlayer(trgt)
        if not xPlayer or not xTarget then
            cb(nil);
            return
        end
        if isAdmin(xPlayer) then
            warnPlayer(xPlayer, xTarget, message, anon)
            cb(true)
        else
            logUnfairUse(xPlayer);
            cb(false)
        end
    end)

    QBCore.Functions.CreateCallback("el_bwh:getWarnList", function(source, cb)
        local xPlayer = QBCore.Functions.GetPlayer(source)
        if isAdmin(xPlayer) then
            local warnlist = {}
            -- rPrint(namecache, nil, "namecache")
            for k, v in ipairs(exports.oxmysql:executeSync(
                                   "SELECT * FROM bwh_warnings LIMIT ?",
                                   {Config.page_element_limit})) do
                v.receiver_name = namecache[v.receiver]
                v.sender_name = namecache[v.sender]
                table.insert(warnlist, v)
            end
            cb(json.encode(warnlist),
               exports.oxmysql:executeSync(
                   "SELECT CEIL(COUNT(id)/ ? ) FROM bwh_warnings",
                   {Config.page_element_limit}))
        else
            logUnfairUse(xPlayer);
            cb(false)
        end
    end)

    QBCore.Functions.CreateCallback("el_bwh:getBanList", function(source, cb)
        local xPlayer = QBCore.Functions.GetPlayer(source)
        if isAdmin(xPlayer) then
            local data = exports.oxmysql:executeSync(
                             "SELECT * FROM bwh_bans LIMIT ?",
                             {Config.page_element_limit})
            local banlist = {}
            for k, v in ipairs(data) do
                v.receiver_name = namecache[json.decode(v.receiver)[2]]
                v.sender_name = namecache[v.sender]
                table.insert(banlist, v)
            end
            cb(json.encode(banlist),
               exports.oxmysql:executeSync(
                   "SELECT CEIL(COUNT(id)/ ? ) FROM bwh_bans",
                   {Config.page_element_limit}))
        else
            logUnfairUse(xPlayer);
            cb(false)
        end
    end)

    QBCore.Functions.CreateCallback("el_bwh:getListData",
                                    function(source, cb, list, page)
        local xPlayer = QBCore.Functions.GetPlayer(source)
        if isAdmin(xPlayer) then
            if list == "banlist" then
                local banlist = {}
                for k, v in ipairs(exports.oxmysql:executeSync(
                                       "SELECT * FROM bwh_bans LIMIT ? OFFSET ?",
                                       {
                        Config.page_element_limit,
                        Config.page_element_limit * (page - 1)
                    })) do
                    v.receiver_name = namecache[json.decode(v.receiver)[2]]
                    v.sender_name = namecache[v.sender]
                    table.insert(banlist, v)
                end
                cb(json.encode(banlist))
            else
                local warnlist = {}
                for k, v in ipairs(exports.oxmysql:executeSync(
                                       "SELECT * FROM bwh_warnings LIMIT ? OFFSET ?",
                                       {
                        Config.page_element_limit,
                        Config.page_element_limit * (page - 1)
                    })) do
                    v.sender_name = namecache[v.sender]
                    v.receiver_name = namecache[v.receiver]
                    table.insert(warnlist, v)
                end
                cb(json.encode(warnlist))
            end
        else
            logUnfairUse(xPlayer);
            cb(nil)
        end
    end)

    QBCore.Functions.CreateCallback("el_bwh:unban", function(source, cb, id)
        local xPlayer = QBCore.Functions.GetPlayer(source)
        if isAdmin(xPlayer) then
            exports.oxmysql:update("UPDATE bwh_bans SET unbanned=1 WHERE id=?",
                                   {id}, function(rc)
                local bannedidentifier = "N/A"
                for k, v in ipairs(bancache) do
                    if v.id == id then
                        bannedidentifier = v.receiver[2]
                        bancache[k].unbanned = true
                        break
                    end
                end
                logAdmin(("Admin ^1%s^7 unbanned ^1%s^7 (%s)"):format(
                             xPlayer.PlayerData.name,
                             (bannedidentifier ~= "N/A" and
                                 namecache[bannedidentifier]) and
                                 namecache[bannedidentifier] or "N/A",
                             bannedidentifier))
                cb(rc > 0)
            end)
        else
            logUnfairUse(xPlayer);
            cb(false)
        end
    end)

    QBCore.Functions.CreateCallback("el_bwh:getIndexedPlayerList", function(source, cb)
        local xPlayer = QBCore.Functions.GetPlayer(source)
        if isAdmin(xPlayer) then
            local players = {}
            local auxPlayes = QBCore.Functions.GetQBPlayers()
            for k, v in pairs(auxPlayes) do
                players[tostring(v.PlayerData.source)] = GetPlayerName(v.PlayerData.source) .. (v.PlayerData.source == source and " (self)" or "")
            end
            cb(json.encode(players))
        else
            logUnfairUse(xPlayer);
            cb(false)
        end
    end)
end)

RegisterServerEvent('el_bwh:backupcheck')
AddEventHandler('el_bwh:backupcheck', function()
    local identifiers = GetPlayerIdentifiers(source)
    local banned = isBanned(identifiers)
    if banned then
        DropPlayer(source, "Ban bypass detected, don’t join back!")
    end
end)

AddEventHandler("playerConnecting", function(name, setKick, def)
    local identifiers = GetPlayerIdentifiers(source)
    if #identifiers > 0 and identifiers[1] ~= nil and identifiers[2] ~= nil then
        local banned, data = isBanned(identifiers)
        namecache[identifiers[2]] = GetPlayerName(source)
        if banned then
            print(("[^1" .. GetCurrentResourceName() ..
                      "^7] Banned player %s (%s) tried to join, their ban expires on %s (Ban ID: #%s)"):format(
                      GetPlayerName(source), data.receiver[2], data.length and
                          os.date("%Y-%m-%d %H:%M", data.length) or "PERMANENT",
                      data.id))
            local kickmsg = Config.banformat:format(data.reason,
                                                    data.length and
                                                        os.date(
                                                            "%Y-%m-%d %H:%M",
                                                            data.length) or
                                                        "PERMANENT",
                                                    data.sender_name, data.id)
            if Config.backup_kick_method then
                print("Droped Player: " .. data.receiver[2])
                DropPlayer(source, kickmsg)
            else
                print("Droped Player: " .. data.receiver[2])
                def.done(kickmsg)
            end
        else
            local playername = GetPlayerName(source)
            local saneplayername = "Adjusted Playername"
            if string.gsub(playername, "[^a-zA-Z0-9]", "") ~= "" then
                saneplayername = string.gsub(playername, "[^a-zA-Z0-9 ]", "")
            end
            local data = {["@name"] = saneplayername}
            for k, v in ipairs(identifiers) do
                data["@" .. split(v, ":")[1]] = v
            end
            if not data["@steam"] then
                if Config.kick_without_steam then
                    print("[^1" .. GetCurrentResourceName() ..
                              "^7] Player connecting without steamid, removing player from server.")
                    def.done(
                        "You need to have steam open to play on this server.")
                else
                    print("[^1" .. GetCurrentResourceName() ..
                              "^7] Player connecting without steamid, skipping identifier storage.")
                end
            else
                exports.oxmysql:insert(
                    "INSERT INTO `bwh_identifiers` (`steam`, `license`, `ip`, `name`, `xbl`, `live`, `discord`, `fivem`) VALUES (:steam, :license, :ip, :name, :xbl, :live, :discord, :fivem) ON DUPLICATE KEY UPDATE `steam` = :steam, `license` = :license, `ip` = :ip, `name` = :name, `xbl` = :xbl, `live` = :live, `discord` = :discord, `fivem` = :fivem",
                    {
                        ['steam'] = data["@steam"],
                        ['license'] = data["@license"],
                        ['ip'] = data["@ip"],
                        ['name'] = data["@name"],
                        ['xbl'] = data["@xbl"],
                        ['live'] = data["@live"],
                        ['discord'] = data["@discord"],
                        ['fivem'] = data["@fivem"]
                    })
            end
        end
    else
        if Config.backup_kick_method then
            DropPlayer(source,
                       "[BWH] No identifiers were found when connecting, please reconnect")
        else
            def.done(
                "[BWH] No identifiers were found when connecting, please reconnect")
        end
    end
end)

AddEventHandler("playerDropped", function(reason)
    if open_assists[source] then open_assists[source] = nil end
    for k, v in ipairs(active_assists) do
        if v == source then
            active_assists[k] = nil
            TriggerClientEvent("chat:addMessage", k, {
                color = {255, 0, 0},
                multiline = false,
                args = {
                    "BWH",
                    "The admin that was helping you dropped from the server"
                }
            })
            return
        elseif k == source then
            TriggerClientEvent("el_bwh:assistDone", v)
            TriggerClientEvent("chat:addMessage", v, {
                color = {255, 0, 0},
                multiline = false,
                args = {
                    "BWH",
                    "The player you were helping dropped from the server, teleporting back..."
                }
            })
            active_assists[k] = nil
            return
        end
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    refreshNameCache()
    refreshBanCache()
end)

function refreshNameCache()
    namecache = {}
    for k, v in ipairs(exports.oxmysql:executeSync(
                           "SELECT license,name FROM bwh_identifiers")) do
        namecache[v.license] = v.name
    end
end

function refreshBanCache()
    bancache = {}
    for k, v in ipairs(exports.oxmysql:executeSync(
                           "SELECT id,receiver,sender,reason,UNIX_TIMESTAMP(length) AS length,unbanned FROM bwh_bans")) do
        table.insert(bancache, {
            id = v.id,
            sender = v.sender,
            sender_name = namecache[v.sender] ~= nil and namecache[v.sender] or
                "N/A",
            receiver = json.decode(v.receiver),
            reason = v.reason,
            length = v.length,
            unbanned = v.unbanned == 1
        })
    end
end

function sendToDiscord(msg)
    if discord_webhook ~= "" then
        PerformHttpRequest(discord_webhook, function(a, b, c) end, "POST",
                           json.encode({
            embeds = {
                {
                    title = "BWH Action Log",
                    description = msg:gsub("%^%d", ""),
                    color = 65280
                }
            }
        }), {["Content-Type"] = "application/json"})
    end
end

function logAdmin(msg)
    for k, v in pairs(QBCore.Functions.GetQBPlayers()) do
        if isAdmin(v) then
            TriggerClientEvent("chat:addMessage", v.PlayerData.source, {
                color = {255, 0, 0},
                multiline = false,
                args = {"BWH", msg}
            })
            sendToDiscord(msg)
        end
    end
end

function isBanned(identifiers)
    for _, ban in ipairs(bancache) do
        if not ban.unbanned and (ban.length == nil or ban.length > os.time()) then
            for _, bid in ipairs(ban.receiver) do
                if bid:find("ip:") and Config.ip_ban then
                    for _, pid in ipairs(identifiers) do
                        if bid == pid then
                            return true, ban
                        end
                    end
                end
            end
        end
    end
    return false, nil
end

function isAdmin(xPlayer)
    return QBCore.Functions.HasPermission(xPlayer.PlayerData.source, 'admin')
end

function execOnAdmins(func)
    local ac = 0
    for k, v in pairs(QBCore.Functions.GetQBPlayers()) do
        if isAdmin(v) then
            ac = ac + 1
            func(v)
        end
    end
    return ac
end

function logUnfairUse(xPlayer)
    if not xPlayer then return end
    print(("[^1" .. GetCurrentResourceName() ..
              "^7] Player %s (%s) tried to use an admin feature"):format(
              xPlayer.PlayerData.name, xPlayer.PlayerData.citizenid))
    logAdmin(("Player %s (%s) tried to use an admin feature"):format(
                 xPlayer.PlayerData.name, xPlayer.PlayerData.citizenid))
end

function banPlayer(xPlayer, xTarget, reason, length, offline)
    local targetidentifiers, offlinename, timestring, data = {}, nil, nil, nil
    if offline then
        data = exports.oxmysql:executeSync(
                   "SELECT * FROM bwh_identifiers WHERE license=?", {xTarget})
        if #data < 1 then
            return false, "~r~Identifier is not in identifiers database!"
        end
        offlinename = data[1].name
        for k, v in pairs(data[1]) do
            if k ~= "name" then table.insert(targetidentifiers, v) end
        end
    else
        targetidentifiers = GetPlayerIdentifiers(xTarget.PlayerData.source)
    end
    if length == "" then length = nil end

    exports.oxmysql:insert(
        "INSERT INTO bwh_bans(id,receiver,sender,length,reason) VALUES(NULL,?,?,?,?)",
        {
            json.encode(targetidentifiers), xPlayer.PlayerData.license, length,
            reason
        }, function(_)
            local banid = exports.oxmysql:executeSync(
                              "SELECT MAX(id) FROM bwh_bans")
            logAdmin(
                ("Player ^1%s^7 (%s) got banned by ^1%s^7, expiration: %s, reason: '%s'" ..
                    (offline and " (OFFLINE BAN)" or "")):format(offline and
                                                                     offlinename or
                                                                     xTarget.PlayerData
                                                                         .name,
                                                                 offline and
                                                                     data[1]
                                                                         .license or
                                                                     xTarget.PlayerData
                                                                         .citizenid,
                                                                 xPlayer.PlayerData
                                                                     .name,
                                                                 length ~= nil and
                                                                     length or
                                                                     "PERMANENT",
                                                                 reason))
            if length ~= nil then
                timestring = length
                local year, month, day, hour, minute =
                    string.match(length, "(%d+)/(%d+)/(%d+) (%d+):(%d+)")
                length = os.time({
                    year = year,
                    month = month,
                    day = day,
                    hour = hour,
                    min = minute
                })
            end
            table.insert(bancache, {
                id = banid == nil and "1" or banid,
                sender = xPlayer.PlayerData.license,
                reason = reason,
                sender_name = xPlayer.PlayerData.name,
                receiver = targetidentifiers,
                length = length
            })
            if offline then
                targetSource = QBCore.Functions.GetSource(identifier)
                xTarget = QBCore.Functions.GetPlayer(targetSource)
            end -- just in case the player is on the server, you never know
            if xTarget then
                TriggerClientEvent("el_bwh:gotBanned",
                                   xTarget.PlayerData.source, reason)
                Citizen.SetTimeout(5000, function()
                    DropPlayer(xTarget.PlayerData.source,
                               Config.banformat:format(reason,
                                                       length ~= nil and
                                                           timestring or
                                                           "PERMANENT",
                                                       xPlayer.PlayerData.name,
                                                       banid == nil and "1" or
                                                           banid))
                end)
            else
                return false, "~r~Unknown error (MySQL?)"
            end
            return true, ""
        end)
end

function warnPlayer(xPlayer, xTarget, message, anon)
    exports.oxmysql:insert(
        "INSERT INTO bwh_warnings(id,receiver,sender,message) VALUES(NULL,?,?,?)",
        {xTarget.PlayerData.license, xPlayer.PlayerData.license, message})
    TriggerClientEvent("el_bwh:receiveWarn", xTarget.PlayerData.source,
                       anon and "" or xPlayer.PlayerData.name, message)
    logAdmin(("Admin ^1%s^7 warned ^1%s^7 (%s), Message: '%s'"):format(
                 xPlayer.PlayerData.name, xTarget.PlayerData.name,
                 xTarget.PlayerData.citizenid, message))
end

AddEventHandler("el_bwh:ban", function(sender, target, reason, length, offline)
    if source == "" then -- if it's from server only
        banPlayer(sender, target, reason, length, offline)
    end
end)

AddEventHandler("el_bwh:warn", function(sender, target, message, anon)
    if source == "" then -- if it's from server only
        warnPlayer(sender, target, message, anon)
    end
end)

RegisterCommand("assist", function(source, args, rawCommand)
    local reason = table.concat(args, " ")
    if reason == "" or not reason then
        TriggerClientEvent("chat:addMessage", source, {
            color = {255, 0, 0},
            multiline = false,
            args = {"BWH", "Please specify a reason"}
        });
        return
    end
    if not open_assists[source] and not active_assists[source] then
        local ac = execOnAdmins(function(admin)
            TriggerClientEvent("el_bwh:requestedAssist", admin.PlayerData.source, GetPlayerName(source), source)
            TriggerClientEvent("chat:addMessage", admin.PlayerData.source, {
                color = {0, 255, 255},
                multiline = Config.chatassistformat:find("\n") ~= nil,
                args = {
                    "BWH",
                    Config.chatassistformat:format(GetPlayerName(source),
                                                   source, reason)
                }
            })
        end)
        if ac > 0 then
            open_assists[source] = reason
            Citizen.SetTimeout(120000, function()
                if open_assists[source] then
                    open_assists[source] = nil
                end
                if GetPlayerName(source) ~= nil then
                    TriggerClientEvent("chat:addMessage", source, {
                        color = {255, 0, 0},
                        multiline = false,
                        args = {"BWH", "Your assist request has expired"}
                    })
                end
            end)
            TriggerClientEvent("chat:addMessage", source, {
                color = {0, 255, 0},
                multiline = false,
                args = {
                    "BWH",
                    "Assist request sent (expires in 120s), write ^1/cassist^7 to cancel your request"
                }
            })
        else
            TriggerClientEvent("chat:addMessage", source, {
                color = {255, 0, 0},
                multiline = false,
                args = {"BWH", "There's no admins on the server"}
            })
        end
    else
        TriggerClientEvent("chat:addMessage", source, {
            color = {255, 0, 0},
            multiline = false,
            args = {
                "BWH",
                "Someone is already helping your or you already have a pending assist request"
            }
        })
    end
end)

RegisterCommand("cassist", function(source, args, rawCommand)
    if open_assists[source] then
        open_assists[source] = nil
        TriggerClientEvent("chat:addMessage", source, {
            color = {0, 255, 0},
            multiline = false,
            args = {"BWH", "Your request was successfuly cancelled"}
        })
        execOnAdmins(function(admin)
            TriggerClientEvent("el_bwh:hideAssistPopup", admin.PlayerData.source)
        end)
    else
        TriggerClientEvent("chat:addMessage", source, {
            color = {255, 0, 0},
            multiline = false,
            args = {"BWH", "You don't have any pending help requests"}
        })
    end
end)

RegisterCommand("finassist", function(source, args, rawCommand)
    local xPlayer = QBCore.Functions.GetPlayer(source)
    if isAdmin(xPlayer) then
        local found = false
        for k, v in pairs(active_assists) do
            if v == source then
                found = true
                active_assists[k] = nil
                TriggerClientEvent("chat:addMessage", source, {
                    color = {0, 255, 0},
                    multiline = false,
                    args = {"BWH", "Assist closed, teleporting back"}
                })
                TriggerClientEvent("el_bwh:assistDone", source)
            end
        end
        if not found then
            TriggerClientEvent("chat:addMessage", source, {
                color = {255, 0, 0},
                multiline = false,
                args = {"BWH", "You're not helping anyone"}
            })
        end
    else
        TriggerClientEvent("chat:addMessage", source, {
            color = {255, 0, 0},
            multiline = false,
            args = {"BWH", "You don't have permissions to use this command!"}
        })
    end
end)

RegisterCommand("bwh", function(source, args, rawCommand)
    local xPlayer = QBCore.Functions.GetPlayer(source)
    if isAdmin(xPlayer) then
        if args[1] == "ban" or args[1] == "warn" or args[1] == "warnlist" or
            args[1] == "banlist" then
            TriggerClientEvent("el_bwh:showWindow", source, args[1])
        elseif args[1] == "refresh" then
            TriggerClientEvent("chat:addMessage", source, {
                color = {0, 255, 0},
                multiline = false,
                args = {"BWH", "Refreshing ban & name cache..."}
            })
            refreshNameCache()
            refreshBanCache()
        elseif args[1] == "assists" then
            local openassistsmsg, activeassistsmsg = "", ""
            for k, v in pairs(open_assists) do
                openassistsmsg = openassistsmsg .. "^5ID " .. k .. " (" ..
                                     GetPlayerName(k) .. ")^7 - " .. v .. "\n"
            end
            for k, v in pairs(active_assists) do
                activeassistsmsg = activeassistsmsg .. "^5ID " .. k .. " (" ..
                                       GetPlayerName(k) .. ")^7 - " .. v .. " (" ..
                                       GetPlayerName(v) .. ")\n"
            end
            TriggerClientEvent("chat:addMessage", source, {
                color = {0, 255, 0},
                multiline = true,
                args = {
                    "BWH", "Pending assists:\n" ..
                        (openassistsmsg ~= "" and openassistsmsg or
                            "^1No pending assists")
                }
            })
            TriggerClientEvent("chat:addMessage", source, {
                color = {0, 255, 0},
                multiline = true,
                args = {
                    "BWH", "Active assists:\n" ..
                        (activeassistsmsg ~= "" and activeassistsmsg or
                            "^1No active assists")
                }
            })
        else
            TriggerClientEvent("chat:addMessage", source, {
                color = {255, 0, 0},
                multiline = false,
                args = {
                    "BWH",
                    "Invalid sub-command! (^4ban^7,^4warn^7,^4banlist^7,^4warnlist^7,^4refresh^7)"
                }
            })
        end
    else
        TriggerClientEvent("chat:addMessage", source, {
            color = {255, 0, 0},
            multiline = false,
            args = {"BWH", "You don't have permissions to use this command!"}
        })
    end
end)

function acceptAssist(xPlayer, target)
    if isAdmin(xPlayer) then
        local source = xPlayer.PlayerData.source
        for k, v in pairs(active_assists) do
            if v == source then
                TriggerClientEvent("chat:addMessage", source, {
                    color = {255, 0, 0},
                    multiline = false,
                    args = {"BWH", "You're already helping someone"}
                })
                return
            end
        end
        if open_assists[target] and not active_assists[target] then
            open_assists[target] = nil
            active_assists[target] = source
            local coords = (GetConvar("onesync", false) or
                               GetConvar("onesync_enableInfinity", false)) and
                               GetEntityCoords(GetPlayerPed(target)) or nil
            TriggerClientEvent("el_bwh:acceptedAssist", source, target, coords)
            TriggerClientEvent("el_bwh:hideAssistPopup", source)
            TriggerClientEvent("chat:addMessage", source, {
                color = {0, 255, 0},
                multiline = false,
                args = {"BWH", "Teleporting to player..."}
            })
        elseif not open_assists[target] and active_assists[target] and
            active_assists[target] ~= source then
            TriggerClientEvent("chat:addMessage", source, {
                color = {255, 0, 0},
                multiline = false,
                args = {"BWH", "Someone is already helping this player"}
            })
        else
            TriggerClientEvent("chat:addMessage", source, {
                color = {255, 0, 0},
                multiline = false,
                args = {"BWH", "Player with that id did not request help"}
            })
        end
    else
        TriggerClientEvent("chat:addMessage", source, {
            color = {255, 0, 0},
            multiline = false,
            args = {"BWH", "You don't have permissions to use this command!"}
        })
    end
end

RegisterCommand("accassist", function(source, args, rawCommand)
    local xPlayer = QBCore.Functions.GetPlayer(source)
    local target = tonumber(args[1])
    acceptAssist(xPlayer, target)
end)

RegisterServerEvent("el_bwh:acceptAssistKey")
AddEventHandler("el_bwh:acceptAssistKey", function(target)
    if not target then return end
    local _source = source
    acceptAssist(QBCore.Functions.GetPlayer(_source), target)
end)
