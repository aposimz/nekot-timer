local QBCore = exports['qb-core']:GetCoreObject()
local isHost = false
local isParticipant = false
local hostageTimerActive = false
local markerActive = false
local joinMarkerActive = false
local hostCoordsCache = nil
local markerRadius = 10.0
local markerHeight = 2.0
local timerDuration = 180 -- タイマーデフォルト3分
local countdownDuration = 5 -- カウントダウンデフォルト5秒
local countdownText = "START!"
local endText = "Time's Up!"
local timerStartTime = 0
local countdownStartTime = 0
local isCountdownActive = false
local function resetAllTimers()
    isCountdownActive = false
    hostageTimerActive = false
    isParticipant = false
    timerStartTime = 0
    countdownStartTime = 0
    SendNUIMessage({ type = "hideCountdown" })
    SendNUIMessage({ type = "hideTimer" })
end

-- サウンド
local sounds = {
    join = "CONFIRM_BEEP",
    countdownTick = "HUD_FRONTEND_DEFAULT_SOUNDSET",
    countdownStart = "RACE_PLACED",
    warning = "TIMER_STOP",
    finalCountdown = "SELECT",
    timerEnd = "TIMER_STOP"
}

-- NUIコールバック
RegisterNUICallback('closeMenu', function(data, cb)
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    -- UIを閉じたら範囲表示を停止
    markerActive = false
    if isHost then
        -- サーバに受付終了を通知
        TriggerServerEvent('nekot-timer:server:closeHostMenu')
    end
    cb('ok')
end)

-- 参加受付の可視状態切替
RegisterNetEvent('nekot-timer:client:enableJoinMarker')
AddEventHandler('nekot-timer:client:enableJoinMarker', function(hostCoordsFromServer, radiusFromServer)
    if not isHost then
        joinMarkerActive = true
        isParticipant = false
        if type(radiusFromServer) == 'number' then
            markerRadius = radiusFromServer
        end
        if hostCoordsFromServer ~= nil then
            -- 受信直後の即時描画のため一度キャッシュ
            hostCoordsCache = hostCoordsFromServer
        end
    end
end)

RegisterNetEvent('nekot-timer:client:disableJoinMarker')
AddEventHandler('nekot-timer:client:disableJoinMarker', function()
    joinMarkerActive = false
    isParticipant = false
end)

-- サーバからのホスト座標更新（参加受付中の円表示で使用）
RegisterNetEvent('nekot-timer:client:updateHostCoords')
AddEventHandler('nekot-timer:client:updateHostCoords', function(coords)
    hostCoordsCache = coords
end)

-- サーバからマーカー半径の反映
RegisterNetEvent('nekot-timer:client:setMarkerRadius')
AddEventHandler('nekot-timer:client:setMarkerRadius', function(serverRadius)
    if type(serverRadius) == 'number' then
        markerRadius = serverRadius
    end
end)
RegisterNUICallback('startTimer', function(data, cb)
    markerRadius = tonumber(data.markerRadius) or 10.0
    timerDuration = tonumber(data.timerDuration) or 180
    countdownDuration = tonumber(data.countdownDuration) or countdownDuration
    -- UIから有効値が来た時のみ上書きし、空なら既定値を維持
    if data.countdownText ~= nil and data.countdownText ~= '' then
        countdownText = data.countdownText
    end
    if data.endText ~= nil and data.endText ~= '' then
        endText = data.endText
    end
    
    -- print("Countdown seconds: " .. countdownDuration)
    -- print("Type: " .. type(countdownDuration))
    
    -- 参加受付終了、カウントダウン開始
    TriggerServerEvent('nekot-timer:server:startCountdown', {
        timerDuration = timerDuration,
        countdownDuration = countdownDuration,
        countdownText = countdownText,
        endText = endText
    })
    
    SetNuiFocus(false, false)
    cb('ok')
end)

-- 参加範囲半径の即時更新
RegisterNUICallback('updateRadius', function(data, cb)
    local newRadius = tonumber(data.markerRadius)
    if newRadius ~= nil then
        markerRadius = newRadius
    end
    cb('ok')
end)

-- コマンド登録
RegisterCommand('timer', function(source, args)
    isHost = true
    markerActive = true
    
    -- サーバーに参加者リストリセットを通知
    TriggerServerEvent('nekot-timer:server:resetParticipants')
    
    -- NUIを表示（動けない）
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({
        type = "openHostMenu",
        markerRadius = markerRadius,
        timerDuration = timerDuration,
        countdownDuration = countdownDuration,
        countdownText = countdownText,
        endText = endText
    })
end, false)

-- サーバーからのイベント
RegisterNetEvent('nekot-timer:client:updateParticipants')
AddEventHandler('nekot-timer:client:updateParticipants', function(participants)
    
    if isHost then
        SendNUIMessage({
            type = "updateParticipants",
            participants = participants
        })
    end
end)

RegisterNetEvent('nekot-timer:client:startCountdown')
AddEventHandler('nekot-timer:client:startCountdown', function(data)
    markerActive = false
    isCountdownActive = true
    countdownStartTime = GetGameTimer()
    timerDuration = data.timerDuration
    countdownDuration = data.countdownDuration
    countdownText = data.countdownText
    endText = data.endText or endText
    
    -- print("Countdown start received: " .. countdownDuration .. "s")
    
    -- カウントダウン開始
    SendNUIMessage({
        type = "startCountdown",
        duration = countdownDuration,
        finalText = countdownText
    })
    
    -- 保険：初期値を即時送信して確実に表示
    Citizen.SetTimeout(100, function()
        SendNUIMessage({
            type = "updateCountdown",
            current = countdownDuration
        })
    end)
end)

-- 強制停止（ホスト再開始時など）
RegisterNetEvent('nekot-timer:client:forceStop')
AddEventHandler('nekot-timer:client:forceStop', function()
    resetAllTimers()
end)

RegisterNetEvent('nekot-timer:client:startTimer')
AddEventHandler('nekot-timer:client:startTimer', function()
    if hostageTimerActive then
        return
    end
    isCountdownActive = false
    hostageTimerActive = true
    timerStartTime = GetGameTimer()
    
    -- タイマー開始（カウントダウン表示はカウントダウン側で1秒後に非表示）
    SendNUIMessage({
        type = "startTimer",
        duration = timerDuration
    })

    -- 念のため最終テキストを即時表示し、1秒後に非表示（レース条件対策）
    SendNUIMessage({
        type = "updateCountdown",
        current = countdownText
    })
    Citizen.SetTimeout(1000, function()
        SendNUIMessage({ type = "hideCountdown" })
    end)
    
    -- タイマー開始音
    PlaySoundFrontend(-1, "RACE_PLACED", "HUD_AWARDS", 1)
end)

-- マーカー描画
Citizen.CreateThread(function()
    while true do
        local sleep = 500
        
        if markerActive or joinMarkerActive then
            sleep = 0
            local playerPed = PlayerPedId()
            local coords = GetEntityCoords(playerPed)
            
            -- マーカーを描画（自分がホストの場合）
            if isHost then
                DrawMarker(1, coords.x, coords.y, coords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 
                    markerRadius * 2.0, markerRadius * 2.0, markerHeight, 
                    0, 200, 255, 120, false, true, 2, false, nil, nil, false)
            end
            
            -- 非ホスト: 参加受付中はホストの円を表示（50m以内）
            if not isHost and joinMarkerActive then
                if hostCoordsCache then
                    local distance = Vdist(coords.x, coords.y, coords.z, hostCoordsCache.x, hostCoordsCache.y, hostCoordsCache.z)
                    
                    if distance <= 50.0 then
                        -- マーカーを描画
                        DrawMarker(1, hostCoordsCache.x, hostCoordsCache.y, hostCoordsCache.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 
                            markerRadius * 2.0, markerRadius * 2.0, markerHeight, 
                            0, 200, 255, 120, false, true, 2, false, nil, nil, false)
                        
                        -- マーカー内にいるかチェック
                        if distance <= markerRadius and not isParticipant then
                            -- [E]で参加 表示
                            DrawText3D(coords.x, coords.y, coords.z + 1.0, "[E]でタイマーに参加")
                            
                            -- Eキー押下で参加
                            if IsControlJustReleased(0, 38) then -- E key
                                TriggerServerEvent('nekot-timer:server:joinEvent')
                                isParticipant = true
                                PlaySoundFrontend(-1, "CONFIRM_BEEP", "HUD_FRONTEND_DEFAULT_SOUNDSET", 1)
                            end
                        end
                    end
                end
            end
        end
        
        Citizen.Wait(sleep)
    end
end)

-- カウントダウンとタイマー処理
Citizen.CreateThread(function()
    local lastSecond = -1
    local currentTime = 0
    local remainingTime = 0
    
    while true do
        local waitMs = (isCountdownActive or hostageTimerActive) and 100 or 500
        Citizen.Wait(waitMs)
        
        if isCountdownActive then
            currentTime = GetGameTimer()
            local elapsedTime = math.floor((currentTime - countdownStartTime) / 1000)
            local currentSecond = countdownDuration - elapsedTime
            
            -- 0到達を検知した瞬間に最終テキスト表示＋タイマー開始＋1秒後に非表示
            if currentSecond <= 0 then
                isCountdownActive = false
                SendNUIMessage({
                    type = "updateCountdown",
                    current = countdownText
                })
                -- print("Countdown reached 0, showing final text: " .. countdownText)
                TriggerEvent('nekot-timer:client:startTimer')
                Citizen.SetTimeout(2000, function()
                    SendNUIMessage({ type = "hideCountdown" })
                end)
            else
            -- 秒数が変わった時に音を鳴らす（0秒は数値更新を送らない）
            if currentSecond ~= lastSecond and currentSecond > 0 then
                lastSecond = currentSecond
                PlaySoundFrontend(-1, "Beep_Red", "DLC_HEIST_HACKING_SNAKE_SOUNDS", 1)
                
                -- NUIにカウントダウン更新を送信
                SendNUIMessage({
                    type = "updateCountdown",
                    current = currentSecond
                })
                
                -- print("Countdown update: " .. currentSecond)
            end
            end
        elseif hostageTimerActive then
            currentTime = GetGameTimer()
            local elapsedTime = math.floor((currentTime - timerStartTime) / 1000)
            remainingTime = timerDuration - elapsedTime
            
            -- 秒数が変わった時の処理
            if remainingTime ~= lastSecond and remainingTime >= 0 then
                lastSecond = remainingTime
                
                -- タイマー更新
                SendNUIMessage({
                    type = "updateTimer",
                    remaining = remainingTime
                })
                
                -- 残り時間に応じた音通知
                if remainingTime == 15 then
                    -- 残り15秒: 警告音
                    PlaySoundFrontend(-1, "10_SEC_WARNING", "HUD_MINI_GAME_SOUNDSET", 1)
                elseif remainingTime <= 5 and remainingTime > 0 then
                    -- 残り5秒〜1秒: 1秒ごとにピッ音
                    PlaySoundFrontend(-1, "Beep_Red", "DLC_HEIST_HACKING_SNAKE_SOUNDS", 1)
                elseif remainingTime <= 0 then
                    -- 0秒: 終了音
                    PlaySoundFrontend(-1, "TIMER_STOP", "HUD_MINI_GAME_SOUNDSET", 1)
                    hostageTimerActive = false

                    -- タイマー終了時に終了テキストを中央に1秒表示
                    SendNUIMessage({
                        type = "updateCountdown",
                        current = endText
                    })
                    Citizen.SetTimeout(2000, function()
                        SendNUIMessage({ type = "hideCountdown" })
                    end)
                    
                    -- タイマー終了通知
                    SendNUIMessage({
                        type = "timerEnd"
                    })
                    
                    -- サーバーにタイマー終了を通知
                    TriggerServerEvent('nekot-timer:server:timerEnded')
                end
            end
        end
    end
end)

-- 3Dテキスト描画用関数
function DrawText3D(x, y, z, text)
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    local px, py, pz = table.unpack(GetGameplayCamCoords())
    
    SetTextScale(0.35, 0.35)
    SetTextFont(0)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry("STRING")
    SetTextCentre(1)
    AddTextComponentString(text)
    DrawText(_x, _y)
    local factor = (string.len(text)) / 370
    DrawRect(_x, _y + 0.0125, 0.015 + factor, 0.03, 41, 11, 41, 68)
end
