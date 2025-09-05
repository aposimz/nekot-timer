local QBCore = exports['qb-core']:GetCoreObject()
local participants = {}
local hostId = nil
local hostCoords = nil
local currentMarkerRadius = 10.0
local joinOpen = false
local lastBroadcastCoords = nil

-- 参加者リストリセット
RegisterNetEvent('nekot-timer:server:resetParticipants')
AddEventHandler('nekot-timer:server:resetParticipants', function()
    local src = source
    -- 以前の参加者に強制停止を通知
    if participants and #participants > 0 then
        for _, participant in ipairs(participants) do
            TriggerClientEvent('nekot-timer:client:forceStop', participant.id)
        end
    end
    -- 新しいホストに切り替え
    participants = {}
    hostId = src
    
    -- ホストの座標を記録
    local ped = GetPlayerPed(src)
    hostCoords = GetEntityCoords(ped)
    
    -- ホスト自身も参加者リストに追加
    local Player = QBCore.Functions.GetPlayer(src)
    if Player then
        local playerName = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
        table.insert(participants, {
            id = src,
            name = playerName
        })
    end
    
    -- 参加者リスト更新をホストに通知
    TriggerClientEvent('nekot-timer:client:updateParticipants', hostId, participants)

    -- 近隣プレイヤーに参加受付開始（マーカー表示）を通知
    local players = QBCore.Functions.GetPlayers()
    for _, pid in ipairs(players) do
        if pid ~= hostId then
            TriggerClientEvent('nekot-timer:client:enableJoinMarker', pid, hostCoords, currentMarkerRadius)
        end
    end
    joinOpen = true
    lastBroadcastCoords = hostCoords
end)

-- イベント参加
RegisterNetEvent('nekot-timer:server:joinEvent')
AddEventHandler('nekot-timer:server:joinEvent', function()
    local src = source
    
    -- 既に参加しているか確認
    for _, participant in ipairs(participants) do
        if participant.id == src then
            return
        end
    end
    
    -- 参加者リストに追加
    local Player = QBCore.Functions.GetPlayer(src)
    if Player then
        local playerName = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
        table.insert(participants, {
            id = src,
            name = playerName
        })
        
        -- 参加者リスト更新をホストに通知
        if hostId then
            TriggerClientEvent('nekot-timer:client:updateParticipants', hostId, participants)
        end
    end
end)

-- マーカー半径の更新（ホストのみ）
RegisterNetEvent('nekot-timer:server:updateMarkerRadius')
AddEventHandler('nekot-timer:server:updateMarkerRadius', function(radius)
    local src = source
    if src ~= hostId then
        return
    end
    if type(radius) ~= 'number' then
        return
    end
    currentMarkerRadius = radius
    local players = QBCore.Functions.GetPlayers()
    for _, pid in ipairs(players) do
        if pid ~= hostId then
            TriggerClientEvent('nekot-timer:client:setMarkerRadius', pid, currentMarkerRadius)
        end
    end
end)

-- ホストがUIを閉じた場合の受付終了
RegisterNetEvent('nekot-timer:server:closeHostMenu')
AddEventHandler('nekot-timer:server:closeHostMenu', function()
    local src = source
    if src ~= hostId then
        return
    end
    local players = QBCore.Functions.GetPlayers()
    for _, pid in ipairs(players) do
        TriggerClientEvent('nekot-timer:client:disableJoinMarker', pid)
    end
    -- 受付状態をクリア
    joinOpen = false
end)

-- カウントダウン開始
RegisterNetEvent('nekot-timer:server:startCountdown')
AddEventHandler('nekot-timer:server:startCountdown', function(data)
    local src = source
    
    -- ホストからの要求か確認
    if src ~= hostId then
        return
    end
    
    joinOpen = false
    
    -- 全参加者にカウントダウン開始を通知（終了表示用テキストも含む）
    for _, participant in ipairs(participants) do
        TriggerClientEvent('nekot-timer:client:startCountdown', participant.id, data)
    end
    
    -- カウントダウン終了後にタイマー開始
    Citizen.SetTimeout(data.countdownDuration * 1000, function()
        for _, participant in ipairs(participants) do
            TriggerClientEvent('nekot-timer:client:startTimer', participant.id)
        end
    end)

    -- 参加受付終了（全員のマーカーを非表示）
    local players = QBCore.Functions.GetPlayers()
    for _, pid in ipairs(players) do
        TriggerClientEvent('nekot-timer:client:disableJoinMarker', pid)
    end
end)

-- タイマー終了通知
RegisterNetEvent('nekot-timer:server:timerEnded')
AddEventHandler('nekot-timer:server:timerEnded', function()
    local src = source
    
    -- ホストからの通知のみ処理
    if src == hostId then
        
        -- 全参加者にタイマー終了を通知
        for _, participant in ipairs(participants) do
            TriggerClientEvent('nekot-timer:client:timerEnded', participant.id)
        end
    end
end)

-- ホスト座標の定期的な更新（オプション）UI表示中ホストは自分では動けない
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000) -- 1秒ごとに更新
        if hostId then
            local ped = GetPlayerPed(hostId)
            if DoesEntityExist(ped) then
                hostCoords = GetEntityCoords(ped)
                if joinOpen then
                    -- ホストが動いた時のみ近傍へ配信
                    local shouldBroadcast = false
                    if lastBroadcastCoords == nil then
                        shouldBroadcast = true
                    else
                        local dx = hostCoords.x - lastBroadcastCoords.x
                        local dy = hostCoords.y - lastBroadcastCoords.y
                        local dz = hostCoords.z - lastBroadcastCoords.z
                        local distSq = dx*dx + dy*dy + dz*dz
                        if distSq > 0.25 then -- 約0.5m超移動
                            shouldBroadcast = true
                        end
                    end
                    if shouldBroadcast then
                        local players = QBCore.Functions.GetPlayers()
                        for _, pid in ipairs(players) do
                            if pid ~= hostId then
                                TriggerClientEvent('nekot-timer:client:updateHostCoords', pid, hostCoords)
                            end
                        end
                        lastBroadcastCoords = hostCoords
                    end
                end
            end
        end
    end
end)

-- プレイヤー切断時の処理
AddEventHandler('playerDropped', function()
    local src = source
    
    -- ホストが切断した場合
    if src == hostId then
        hostId = nil
        
        -- 全参加者にイベント終了を通知
        for _, participant in ipairs(participants) do
            if participant.id ~= src then
                TriggerClientEvent('nekot-timer:client:eventCancelled', participant.id)
            end
        end
        
        participants = {}
    else
        -- 参加者が切断した場合、リストから削除
        for i, participant in ipairs(participants) do
            if participant.id == src then
                table.remove(participants, i)
                break
            end
        end
        
        -- ホストに参加者リスト更新を通知
        if hostId then
            TriggerClientEvent('nekot-timer:client:updateParticipants', hostId, participants)
        end
    end
end)

-- ホスト座標取得API（クライアントから呼び出し可能）
QBCore.Functions.CreateCallback('nekot-timer:server:getHostCoords', function(source, cb)
    if hostId and hostCoords then
        cb(hostCoords)
    else
        cb(nil)
    end
end)
