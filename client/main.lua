local QBCore = exports['qb-core']:GetCoreObject()
local isHost = false
local isParticipant = false
local hostageTimerActive = false
local markerActive = false
local joinMarkerActive = false

-- 複数ホスト対応のための変数
local nearbyHosts = {} -- 近くのホスト一覧 {id = ホストID, coords = 座標, radius = 半径}
local currentHostId = nil -- 現在参加中のホストID。参加先一致チェックやクリーンアップに使用
local lastHostUpdateTime = 0 -- 最後にホスト一覧を更新した時間
local lastQueryCoords = nil -- 前回クエリ時のプレイヤー座標

local markerRadius = 10.0
local markerHeight = 2.0
local timerDuration = 180 -- タイマーデフォルト3分
local countdownDuration = 5 -- カウントダウンデフォルト5秒
local DEFAULT_COUNTDOWN_TEXT = "START!"
local DEFAULT_END_TEXT = "Time's Up!"
local countdownText = DEFAULT_COUNTDOWN_TEXT
local endText = DEFAULT_END_TEXT

-- ホスト設定の保存（セッション中のみ）
local sessionHostConfig = nil

local function loadLastHostConfig()
    return sessionHostConfig
end

local function saveLastHostConfig(cfg)
    if type(cfg) ~= 'table' then return end
    sessionHostConfig = {
        markerRadius = tonumber(cfg.markerRadius) or markerRadius,
        timerDuration = tonumber(cfg.timerDuration) or timerDuration,
        countdownDuration = tonumber(cfg.countdownDuration) or countdownDuration,
        countdownText = (type(cfg.countdownText) == 'string' and cfg.countdownText ~= '') and cfg.countdownText or DEFAULT_COUNTDOWN_TEXT,
        endText = (type(cfg.endText) == 'string' and cfg.endText ~= '') and cfg.endText or DEFAULT_END_TEXT
    }
end
local timerStartTime = 0
local countdownStartTime = 0
local isCountdownActive = false
local function resetAllTimers()
    isCountdownActive = false
    hostageTimerActive = false
    isParticipant = false
    timerStartTime = 0
    countdownStartTime = 0
    currentHostId = nil
    SendNUIMessage({ type = "hideCountdown" })
    SendNUIMessage({ type = "hideTimer" })
end

-- 初回起動時に近くのホスト一覧を取得
Citizen.CreateThread(function()
    Citizen.Wait(2000) -- サーバー接続完了を待つ
    UpdateNearbyHosts()
end)

-- NUIコールバック
RegisterNUICallback('closeMenu', function(data, cb)
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    -- UIを閉じたら範囲表示を停止
    markerActive = false
    local wasHost = isHost
    if wasHost then
        -- サーバに受付終了を通知（他ホストのマーカー維持のため必須）
        TriggerServerEvent('nekot-timer:server:closeHostMenu')
    end
    -- 最後にホストフラグを下ろす
    isHost = false
    cb('ok')
end)

-- 参加受付の可視状態切替
RegisterNetEvent('nekot-timer:client:enableJoinMarker')
AddEventHandler('nekot-timer:client:enableJoinMarker', function(hostCoordsFromServer, radiusFromServer, hostId)
    if not isHost then
        joinMarkerActive = true
        isParticipant = false
        
        -- ホスト情報を追加/更新
        local found = false
        for i, host in ipairs(nearbyHosts) do
            if host.id == hostId then
                host.coords = hostCoordsFromServer
                host.radius = radiusFromServer or host.radius
                found = true
                break
            end
        end
        
        -- 新しいホストの場合は追加
        if not found then
            table.insert(nearbyHosts, {
                id = hostId,
                coords = hostCoordsFromServer,
                radius = radiusFromServer or 10.0
            })
        end
    end
end)

RegisterNetEvent('nekot-timer:client:disableJoinMarker')
AddEventHandler('nekot-timer:client:disableJoinMarker', function(hostId)
    -- 特定のホストのマーカーを無効化
    for i, host in ipairs(nearbyHosts) do
        if host.id == hostId then
            table.remove(nearbyHosts, i)
            break
        end
    end
    
    -- 自分がそのホストに参加中だったら離脱扱いにして再参加を許可
    if currentHostId and hostId == currentHostId then
        isParticipant = false
        currentHostId = nil
    end

    -- 全てのホストが無くなったら参加状態をリセット
    if #nearbyHosts == 0 then
        joinMarkerActive = false
        isParticipant = false
        currentHostId = nil
    end
end)

-- サーバからのホスト座標更新（参加受付中の円表示で使用）
RegisterNetEvent('nekot-timer:client:updateHostCoords')
AddEventHandler('nekot-timer:client:updateHostCoords', function(coords, hostId)
    -- 特定のホストの座標を更新
    for i, host in ipairs(nearbyHosts) do
        if host.id == hostId then
            host.coords = coords
            break
        end
    end
end)

-- 近くのホスト一覧を更新（定期的に呼び出す）
function UpdateNearbyHosts()
    QBCore.Functions.TriggerCallback('nekot-timer:server:getNearbyHosts', function(hosts)
        nearbyHosts = hosts
        joinMarkerActive = #hosts > 0
    end)
end

-- サーバからマーカー半径の反映
RegisterNetEvent('nekot-timer:client:setMarkerRadius')
AddEventHandler('nekot-timer:client:setMarkerRadius', function(serverRadius, hostId)
    if type(serverRadius) ~= 'number' or not hostId then
        return
    end
    -- 非ホスト側: 該当ホストのみの半径を更新
    for i, host in ipairs(nearbyHosts) do
        if host.id == hostId then
            host.radius = serverRadius
            break
        end
    end
    -- 自分がホストの場合のローカル半径は NUI 側で既に反映済み
end)
RegisterNUICallback('startTimer', function(data, cb)
    markerRadius = tonumber(data.markerRadius) or 10.0
    timerDuration = tonumber(data.timerDuration) or 180
    countdownDuration = tonumber(data.countdownDuration) or countdownDuration
    -- テキストは空や未定義ならデフォルトにフォールバック
    local sendCountdownText = (type(data.countdownText) == 'string' and data.countdownText ~= '') and data.countdownText or DEFAULT_COUNTDOWN_TEXT
    local sendEndText = (type(data.endText) == 'string' and data.endText ~= '') and data.endText or DEFAULT_END_TEXT
    
    -- print("Countdown seconds: " .. countdownDuration)
    -- print("Type: " .. type(countdownDuration))
    
    -- 参加受付終了、カウントダウン開始
    TriggerServerEvent('nekot-timer:server:startCountdown', {
        timerDuration = timerDuration,
        countdownDuration = countdownDuration,
        countdownText = sendCountdownText,
        endText = sendEndText
    })
    
    SetNuiFocus(false, false)
    cb('ok')

    -- 自分のホスト設定を保存
    saveLastHostConfig({
        markerRadius = markerRadius,
        timerDuration = timerDuration,
        countdownDuration = countdownDuration,
        countdownText = sendCountdownText,
        endText = sendEndText
    })
end)

-- 参加範囲半径の即時更新
RegisterNUICallback('updateRadius', function(data, cb)
    local newRadius = tonumber(data.markerRadius)
    if newRadius ~= nil then
        markerRadius = newRadius
    end
    cb('ok')
end)

-- タイマーホストメニューを開く関数
local function openTimerHostMenu()
    -- 参加者状態や進行中のUIをクリアしてからホスト化
    resetAllTimers()
    isHost = true
    markerActive = true
    -- 前回の自分のホスト設定を読み込み（なければ現在値/デフォルト）
    local last = loadLastHostConfig()
    if last then
        markerRadius = last.markerRadius or markerRadius
        timerDuration = last.timerDuration or timerDuration
        countdownDuration = last.countdownDuration or countdownDuration
        countdownText = last.countdownText or DEFAULT_COUNTDOWN_TEXT
        endText = last.endText or DEFAULT_END_TEXT
    else
        countdownText = DEFAULT_COUNTDOWN_TEXT
        endText = DEFAULT_END_TEXT
    end
    
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
end

-- コマンド登録
RegisterCommand('timer', function(source, args)
    openTimerHostMenu()
end, false)

-- ラジアルメニュー用のイベント
RegisterNetEvent('nekot-timer:openHostMenu')
AddEventHandler('nekot-timer:openHostMenu', function()
    openTimerHostMenu()
end)

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

RegisterNetEvent('nekot-timer:client:joined')
AddEventHandler('nekot-timer:client:joined', function(hostId, hostName)
	local name = hostName or ('ID ' .. tostring(hostId))
	-- print(string.format('[nekot-timer] client: joined received host=%s name=%s', tostring(hostId), name))
	PlaySoundFrontend(-1, "Deliver_Pick_Up", "HUD_FRONTEND_MP_COLLECTABLE_SOUNDS", true)
	QBCore.Functions.Notify(('%s のタイマーに参加しました'):format(name), "success", 3000)
end)

RegisterNetEvent('nekot-timer:client:startCountdown')
AddEventHandler('nekot-timer:client:startCountdown', function(data)
    markerActive = false
    isCountdownActive = true
    countdownStartTime = GetGameTimer()
    timerDuration = tonumber(data.timerDuration) or timerDuration
    countdownDuration = tonumber(data.countdownDuration) or countdownDuration
    -- 未入力や空文字のときはデフォルトにフォールバック
    if type(data.countdownText) == 'string' and data.countdownText ~= '' then
        countdownText = data.countdownText
    else
        countdownText = DEFAULT_COUNTDOWN_TEXT
    end
    if type(data.endText) == 'string' and data.endText ~= '' then
        endText = data.endText
    else
        endText = DEFAULT_END_TEXT
    end
    -- hostIdがあり、かつ参加先と異なる場合は無視
    if data.hostId and currentHostId and data.hostId ~= currentHostId then
        return
    end
    
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
AddEventHandler('nekot-timer:client:startTimer', function(hostId)
    if hostId and currentHostId and hostId ~= currentHostId then
        return
    end
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
    PlaySoundFrontend(-1, "RACE_PLACED", "HUD_AWARDS", true)
end)

-- マーカー描画
Citizen.CreateThread(function()
    while true do
        local sleep = 500
        
        if markerActive or joinMarkerActive then
            sleep = 0
            local playerPed = PlayerPedId()
            local coords = GetEntityCoords(playerPed)
            
            -- マーカーを描画（自分がホストの場合）DrawMarker の末尾引数は nil, nilのままで。空文字だとエラー
            if isHost then
                DrawMarker(1, coords.x, coords.y, coords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 
                    markerRadius * 2.0, markerRadius * 2.0, markerHeight, 
                    0, 200, 255, 120, false, true, 2, false, nil, nil, false)
            end
            
            -- 非ホスト: 最寄りホスト検出と参加処理（位置変化/経過時間で近くのホスト一覧を更新）
            if not isHost then
                -- 2秒経過 or 5m以上移動で再取得
                local needQuery = false
                local now = GetGameTimer()
                if (not lastHostUpdateTime) or (now - lastHostUpdateTime) > 2000 then
                    needQuery = true
                end
                if lastQueryCoords == nil then
                    needQuery = true
                else
                    local moved = Vdist(coords.x, coords.y, coords.z, lastQueryCoords.x, lastQueryCoords.y, lastQueryCoords.z)
                    if moved > 5.0 then
                        needQuery = true
                    end
                end

                if needQuery then
                    UpdateNearbyHosts()
                    lastHostUpdateTime = now
                    lastQueryCoords = { x = coords.x, y = coords.y, z = coords.z }
                end

                local nearestHost = nil
                local nearestDist = 1e9

                -- 全ての近くのホストについて処理（描画と最寄り判定）
                for _, host in ipairs(nearbyHosts) do
                    if host.coords then
                        local distance = Vdist(coords.x, coords.y, coords.z, host.coords.x, host.coords.y, host.coords.z)

                        if distance <= 50.0 then
                            -- マーカーを描画
                            DrawMarker(1, host.coords.x, host.coords.y, host.coords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 
                                host.radius * 2.0, host.radius * 2.0, markerHeight, 
                                0, 200, 255, 120, false, true, 2, false, nil, nil, false)

                            -- 参加可能半径内なら最寄り候補に
                            if distance <= host.radius and distance < nearestDist then
                                nearestDist = distance
                                nearestHost = host
                            end
                        end
                    end
                end

                -- 最寄りホストに対してのみ[E]で参加を表示・処理
                if nearestHost and (not isParticipant or (currentHostId ~= nearestHost.id)) and joinMarkerActive then
                    DrawText3D(coords.x, coords.y, coords.z + 1.0, "[E]でタイマーに参加")
                    if IsControlJustReleased(0, 38) then -- E key
                        TriggerServerEvent('nekot-timer:server:joinEvent', nearestHost.id)
                        isParticipant = true
                        currentHostId = nearestHost.id
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
                PlaySoundFrontend(-1, "Beep_Red", "DLC_HEIST_HACKING_SNAKE_SOUNDS", true)
                
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
                    PlaySoundFrontend(-1, "10_SEC_WARNING", "HUD_MINI_GAME_SOUNDSET", true)
                elseif remainingTime <= 5 and remainingTime > 0 then
                    -- 残り5秒〜1秒: 1秒ごとにピッ音
                    PlaySoundFrontend(-1, "Beep_Red", "DLC_HEIST_HACKING_SNAKE_SOUNDS", true)
                elseif remainingTime <= 0 then
                    -- 0秒: 終了音
                    PlaySoundFrontend(-1, "TIMER_STOP", "HUD_MINI_GAME_SOUNDSET", true)
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
    local onScreen, screenX, screenY = World3dToScreen2d(x, y, z)
    if not onScreen then
        return
    end

    SetTextScale(0.35, 0.35)
    SetTextFont(0)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry("STRING")
    SetTextCentre(true)
    AddTextComponentString(text)
    DrawText(screenX, screenY)

    local factor = (string.len(text)) / 370
    DrawRect(screenX, screenY + 0.0125, 0.015 + factor, 0.03, 41, 11, 41, 68)
end
