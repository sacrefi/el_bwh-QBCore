local QBCore = exports['qb-core']:GetCoreObject()
local pos_before_assist, assisting, assist_target, last_assist, IsFirstSpawn = nil, false, nil, nil, true

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

RegisterNUICallback("ban", function(data, cb)
    if not data.target or not data.reason then
        return
    end
    QBCore.Functions.TriggerCallback("el_bwh:ban", function(success, reason)
        if success then
            QBCore.Functions.Notify("Successfully banned player", "success")
        else
            QBCore.Functions.Notify(reason, "error")
        end -- dont ask why i did it this way, im a bit retarded
    end, data.target, data.reason, data.length, data.offline)
end)

RegisterNUICallback("warn", function(data, cb)
    if not data.target or not data.message then
        return
    end
    QBCore.Functions.TriggerCallback("el_bwh:warn", function(success)
        if success then
            QBCore.Functions.Notify("Successfully warned player", "success")
        else
            QBCore.Functions.Notify("Something went wrong", "error")
            QBCore.Functions.Notify("success: "..tostring(success), "error")
        end
    end, data.target, data.message, data.anon)
end)

RegisterNUICallback("unban", function(data, cb)
    if not data.id then
        return
    end
    QBCore.Functions.TriggerCallback("el_bwh:unban", function(success)
        if success then
            QBCore.Functions.Notify("Successfully unbanned player", "success")
        else
            QBCore.Functions.Notify("Something went wrong", "error")
        end
    end, data.id)
end)

RegisterNUICallback("getListData", function(data, cb)
    if not data.list or not data.page then
        cb(nil);
        return
    end
    QBCore.Functions.TriggerCallback("el_bwh:getListData", function(data)
        cb(data)
    end, data.list, data.page)
end)

RegisterNUICallback("hidecursor", function(data, cb)
    SetNuiFocus(false, false)
end)

AddEventHandler("playerSpawned", function(spawn)
    if IsFirstSpawn and Config.backup_kick_method then
        TriggerServerEvent("el_bwh:backupcheck")
        IsFirstSpawn = false
    end
end)

RegisterNetEvent("el_bwh:gotBanned")
AddEventHandler("el_bwh:gotBanned", function(rsn)
    Citizen.CreateThread(function()
        local scaleform = RequestScaleformMovie("mp_big_message_freemode")
        while not HasScaleformMovieLoaded(scaleform) do
            Citizen.Wait(0)
        end
        BeginScaleformMovieMethod(scaleform, "SHOW_SHARD_WASTED_MP_MESSAGE")
        PushScaleformMovieMethodParameterString("~r~BANNED")
        PushScaleformMovieMethodParameterString(rsn)
        PushScaleformMovieMethodParameterInt(5)
        EndScaleformMovieMethod()
        PlaySoundFrontend(-1, "LOSER", "HUD_AWARDS")
        ClearDrawOrigin()
        while true do
            Citizen.Wait(0)
            DisableAllControlActions(0)
            DisableFrontendThisFrame()
            local ped = GetPlayerPed(-1)
            SetEntityCoords(ped, 0, 0, 0, 0, 0, 0, false)
            FreezeEntityPosition(ped, true)
            DrawRect(0.0, 0.0, 2.0, 2.0, 0, 0, 0, 255)
            DrawScaleformMovieFullscreen(scaleform, 255, 255, 255, 255)
        end
        SetScaleformMovieAsNoLongerNeeded(scaleform)
    end)
end)

RegisterNetEvent("el_bwh:receiveWarn")
AddEventHandler("el_bwh:receiveWarn", function(sender, message)
    TriggerEvent("chat:addMessage", {
        color = {255, 255, 0},
        multiline = true,
        args = {"BWH", "You received a warning" .. (sender ~= "" and " from " .. sender or "") .. "!\n-> " .. message}
    })
    Citizen.CreateThread(function()
        local scaleform = RequestScaleformMovie("mp_big_message_freemode")
        while not HasScaleformMovieLoaded(scaleform) do
            Citizen.Wait(0)
        end
        BeginScaleformMovieMethod(scaleform, "SHOW_SHARD_WASTED_MP_MESSAGE")
        PushScaleformMovieMethodParameterString("~y~WARNING")
        PushScaleformMovieMethodParameterString(message)
        PushScaleformMovieMethodParameterInt(5)
        EndScaleformMovieMethod()
        PlaySoundFrontend(-1, "LOSER", "HUD_AWARDS")
        local drawing = true
        Citizen.SetTimeout((Config.warning_screentime * 1000), function()
            drawing = false
        end)
        while drawing do
            Citizen.Wait(0)
            DrawScaleformMovieFullscreen(scaleform, 255, 255, 255, 255)
        end
        SetScaleformMovieAsNoLongerNeeded(scaleform)
    end)
end)

RegisterNetEvent("el_bwh:requestedAssist")
AddEventHandler("el_bwh:requestedAssist", function(tn, t)
    SendNUIMessage({
        show = true,
        window = "assistreq",
        template = Config.popassistformat,
        data = {tn, t}
    })
    last_assist = t
end)

RegisterNetEvent("el_bwh:acceptedAssist")
AddEventHandler("el_bwh:acceptedAssist", function(t, pos)
    if assisting then
        return
    end
    local target = GetPlayerFromServerId(t)
    if target then
        if not pos then
            pos = NetworkGetPlayerCoords(target)
        end
        local ped = GetPlayerPed(-1)
        pos_before_assist = GetEntityCoords(ped)
        assisting = true
        assist_target = t
        SetEntityCoords(PlayerPedId(), pos.x, pos.y + 0.5, pos.z)
    end
end)

RegisterNetEvent("el_bwh:assistDone")
AddEventHandler("el_bwh:assistDone", function()
    if assisting then
        assisting = false
        if pos_before_assist ~= nil then
            SetEntityCoords(PlayerPedId(), pos_before_assist.x, pos_before_assist.y + 0.5, pos_before_assist.z)
            pos_before_assist = nil
        end
        assist_target = nil
    end
end)

RegisterNetEvent("el_bwh:hideAssistPopup")
AddEventHandler("el_bwh:hideAssistPopup", function(t)
    SendNUIMessage({
        hide = true
    })
    last_assist = nil
end)

RegisterNetEvent("el_bwh:showWindow")
AddEventHandler("el_bwh:showWindow", function(win)
    if win == "ban" or win == "warn" then
        QBCore.Functions.TriggerCallback("el_bwh:getIndexedPlayerList", function(indexedPList)
            SendNUIMessage({
                show = true,
                window = win,
                players = indexedPList
            })
        end)
    elseif win == "banlist" or win == "warnlist" then
        SendNUIMessage({
            loading = true,
            window = win
        })
        QBCore.Functions.TriggerCallback(win == "banlist" and "el_bwh:getBanList" or "el_bwh:getWarnList",
            function(list, pages)
                SendNUIMessage({
                    show = true,
                    window = win,
                    list = list,
                    pages = pages
                })
            end)
    end
    SetNuiFocus(true, true)
end)

RegisterCommand("decassist", function(a, b, c)
    TriggerEvent("el_bwh:hideAssistPopup")
end, false)

if Config.assist_keys.enable then
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(0)
            if IsControlJustPressed(0, Config.assist_keys.accept) then
                if not NetworkIsPlayerActive(GetPlayerFromServerId(last_assist)) then
                    last_assist = nil
                else
                    TriggerServerEvent("el_bwh:acceptAssistKey", last_assist)
                end
            end
            if IsControlJustPressed(0, Config.assist_keys.decline) then
                TriggerEvent("el_bwh:hideAssistPopup")
            end
        end
    end)
end

Citizen.CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/decassist', 'Hide assist popup', {})
    TriggerEvent('chat:addSuggestion', '/assist', 'Request help from admins', {{
        name = "Reason",
        help = "Why do you need help?"
    }})
    TriggerEvent('chat:addSuggestion', '/cassist', 'Cancel your pending help request', {})
    TriggerEvent('chat:addSuggestion', '/finassist', 'Finish assist and tp back', {})
    TriggerEvent('chat:addSuggestion', '/accassist', 'Accept a players help request', {{
        name = "Player ID",
        help = "ID of the player you want to help"
    }})
end)
