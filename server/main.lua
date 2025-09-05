local QBCore = exports['qb-core']:GetCoreObject()

-- 複数のホストをサポートするためのテーブル
local hosts = {}
-- hosts[hostId] = {
--     participants = {}, -- 参加者リスト
--     coords = vector3(0,0,0), -- ホスト座標
--     markerRadius = 10.0, -- 参加範囲
--     joinOpen = false, -- 参加受付中かどうか
--     lastBroadcastCoords = nil -- 最後に配信した座標
-- }

-- 参加者リストリセット
RegisterNetEvent('nekot-timer:server:resetParticipants')
AddEventHandler('nekot-timer:server:resetParticipants', function()
    local src = source
    
    -- 既にホストの場合は、以前の参加者に強制停止を通知
    if hosts[src] then
        for _, participant in ipairs(hosts[src].participants) do
            TriggerClientEvent('nekot-timer:client:forceStop', participant.id)
        end
    end
    
    -- 新しいホストデータを初期化
    hosts[src] = {
        participants = {},
        coords = GetEntityCoords(GetPlayerPed(src)),
        markerRadius = 10.0,
        joinOpen = true,
        lastBroadcastCoords = nil
    }
    
    -- ホスト自身も参加者リストに追加
    local Player = QBCore.Functions.GetPlayer(src)
    if Player then
        local playerName = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
        table.insert(hosts[src].participants, {
            id = src,
            name = playerName
        })
    end
    
    -- 参加者リスト更新をホストに通知
    TriggerClientEvent('nekot-timer:client:updateParticipants', src, hosts[src].participants)

    -- 近隣プレイヤーに参加受付開始（マーカー表示）を通知
    local players = QBCore.Functions.GetPlayers()
    for _, pid in ipairs(players) do
        if pid ~= src then
            TriggerClientEvent('nekot-timer:client:enableJoinMarker', pid, hosts[src].coords, hosts[src].markerRadius, src)
        end
    end
    
    hosts[src].lastBroadcastCoords = hosts[src].coords
end)

-- イベント参加
RegisterNetEvent('nekot-timer:server:joinEvent')
AddEventHandler('nekot-timer:server:joinEvent', function(hostId)
    local src = source
    
    -- ホストが存在しない場合は終了
    if not hosts[hostId] then
        return
    end
    
    -- 既に参加しているか確認
    for _, participant in ipairs(hosts[hostId].participants) do
        if participant.id == src then
            return
        end
    end
    
    -- 参加者リストに追加
    local Player = QBCore.Functions.GetPlayer(src)
    if Player then
        local playerName = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
        table.insert(hosts[hostId].participants, {
            id = src,
            name = playerName
        })
        
        -- 参加者リスト更新をホストに通知
        TriggerClientEvent('nekot-timer:client:updateParticipants', hostId, hosts[hostId].participants)
    end
end)

-- マーカー半径の更新（ホストのみ）
RegisterNetEvent('nekot-timer:server:updateMarkerRadius')
AddEventHandler('nekot-timer:server:updateMarkerRadius', function(radius)
    local src = source
    
    -- ホストでない場合は終了
    if not hosts[src] then
        return
    end
    
    if type(radius) ~= 'number' then
        return
    end
    
    hosts[src].markerRadius = radius
    
    -- 近隣プレイヤーにマーカー半径を通知
    local players = QBCore.Functions.GetPlayers()
    for _, pid in ipairs(players) do
        if pid ~= src then
            TriggerClientEvent('nekot-timer:client:setMarkerRadius', pid, hosts[src].markerRadius, src)
        end
    end
end)

-- ホストがUIを閉じた場合の受付終了
RegisterNetEvent('nekot-timer:server:closeHostMenu')
AddEventHandler('nekot-timer:server:closeHostMenu', function()
    local src = source
    
    -- ホストでない場合は終了
    if not hosts[src] then
        return
    end
    
    -- このホストの参加受付を終了
    hosts[src].joinOpen = false
    
    -- このホストの参加受付マーカーを非表示にする
    local players = QBCore.Functions.GetPlayers()
    for _, pid in ipairs(players) do
        if pid ~= src then
            TriggerClientEvent('nekot-timer:client:disableJoinMarker', pid, src)
        end
    end
end)

-- カウントダウン開始
RegisterNetEvent('nekot-timer:server:startCountdown')
AddEventHandler('nekot-timer:server:startCountdown', function(data)
    local src = source
    
    -- ホストでない場合は終了
    if not hosts[src] then
        return
    end
    
    -- 参加受付を終了
    hosts[src].joinOpen = false
    
    -- このホストの参加者全員にカウントダウン開始を通知
    for _, participant in ipairs(hosts[src].participants) do
        TriggerClientEvent('nekot-timer:client:startCountdown', participant.id, data)
    end
    
    -- カウントダウン終了後にタイマー開始
    Citizen.SetTimeout(data.countdownDuration * 1000, function()
        -- ホストが存在する場合のみ処理（途中で切断された場合の対策）
        if hosts[src] then
            for _, participant in ipairs(hosts[src].participants) do
                TriggerClientEvent('nekot-timer:client:startTimer', participant.id)
            end
        end
    end)

    -- このホストの参加受付マーカーを非表示にする
    local players = QBCore.Functions.GetPlayers()
    for _, pid in ipairs(players) do
        if pid ~= src then
            TriggerClientEvent('nekot-timer:client:disableJoinMarker', pid, src)
        end
    end
end)

-- タイマー終了通知
RegisterNetEvent('nekot-timer:server:timerEnded')
AddEventHandler('nekot-timer:server:timerEnded', function()
    local src = source
    
    -- ホストでない場合は終了
    if not hosts[src] then
        return
    end
    
    -- このホストの参加者全員にタイマー終了を通知
    for _, participant in ipairs(hosts[src].participants) do
        TriggerClientEvent('nekot-timer:client:timerEnded', participant.id)
    end
    
    -- タイマー終了後、ホストデータをクリーンアップ
    hosts[src] = nil
end)

-- ホスト座標の定期的な更新
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000) -- 1秒ごとに更新
        
        -- すべてのホストについて処理
        for hostId, hostData in pairs(hosts) do
            if hostData.joinOpen then
                local ped = GetPlayerPed(hostId)
                if DoesEntityExist(ped) then
                    local currentCoords = GetEntityCoords(ped)
                    hostData.coords = currentCoords
                    
                    -- ホストが動いた時のみ近傍へ配信
                    local shouldBroadcast = false
                    if hostData.lastBroadcastCoords == nil then
                        shouldBroadcast = true
                    else
                        local dx = currentCoords.x - hostData.lastBroadcastCoords.x
                        local dy = currentCoords.y - hostData.lastBroadcastCoords.y
                        local dz = currentCoords.z - hostData.lastBroadcastCoords.z
                        local distSq = dx*dx + dy*dy + dz*dz
                        if distSq > 0.25 then -- 約0.5m超移動
                            shouldBroadcast = true
                        end
                    end
                    
                    if shouldBroadcast then
                        local players = QBCore.Functions.GetPlayers()
                        for _, pid in ipairs(players) do
                            if pid ~= hostId then
                                TriggerClientEvent('nekot-timer:client:updateHostCoords', pid, currentCoords, hostId)
                            end
                        end
                        hostData.lastBroadcastCoords = currentCoords
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
    if hosts[src] then
        -- このホストの参加者全員にイベント終了を通知
        for _, participant in ipairs(hosts[src].participants) do
            if participant.id ~= src then
                TriggerClientEvent('nekot-timer:client:eventCancelled', participant.id)
            end
        end
        
        -- ホストデータを削除
        hosts[src] = nil
    else
        -- 参加者が切断した場合、該当するホストの参加者リストから削除
        for hostId, hostData in pairs(hosts) do
            for i, participant in ipairs(hostData.participants) do
                if participant.id == src then
                    table.remove(hostData.participants, i)
                    
                    -- ホストに参加者リスト更新を通知
                    TriggerClientEvent('nekot-timer:client:updateParticipants', hostId, hostData.participants)
                    break
                end
            end
        end
    end
end)

-- ホスト座標取得API（クライアントから呼び出し可能）
QBCore.Functions.CreateCallback('nekot-timer:server:getHostCoords', function(source, cb, targetHostId)
    if hosts[targetHostId] then
        cb(hosts[targetHostId].coords)
    else
        cb(nil)
    end
end)

-- 近くのホスト一覧を取得するAPI
QBCore.Functions.CreateCallback('nekot-timer:server:getNearbyHosts', function(source, cb)
    local nearbyHosts = {}
    local playerCoords = GetEntityCoords(GetPlayerPed(source))
    
    for hostId, hostData in pairs(hosts) do
        if hostData.joinOpen then
            local dx = playerCoords.x - hostData.coords.x
            local dy = playerCoords.y - hostData.coords.y
            local dz = playerCoords.z - hostData.coords.z
            local distSq = dx*dx + dy*dy + dz*dz
            
            if distSq <= 2500 then -- 50m以内のホスト
                table.insert(nearbyHosts, {
                    id = hostId,
                    coords = hostData.coords,
                    radius = hostData.markerRadius
                })
            end
        end
    end
    
    cb(nearbyHosts)
end)
