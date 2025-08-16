local rerideEligible = {}
local conf = {}
-- サーバーの定期クリーンアップの間隔 (ミリ秒)
conf.ServerCleanupWait = 600000 -- 10分

RegisterNetEvent('reride:enable')
RegisterNetEvent('reride:request')

-- =================================================================
-- rerideの権利をサーバーに記録
-- =================================================================
AddEventHandler('reride:enable', function(vehicleNetId, wasDriver)
    local sourcePlayer = source
    rerideEligible[sourcePlayer] = {
        vehicle = vehicleNetId,
        driver = wasDriver
    }
    print(('[Reride] Player %s is now eligible for vehicle %d (Was Driver: %s)'):format(sourcePlayer, vehicleNetId, tostring(wasDriver))) -- for server log
end)

-- =================================================================
-- rerideのリクエストを処理
-- =================================================================
AddEventHandler('reride:request', function()
    local sourcePlayer = source
    local playerPed = GetPlayerPed(sourcePlayer)
    
    -- 1. 権利があるかサーバー側でチェック
    local eligibility = rerideEligible[sourcePlayer]
    if not eligibility then
        TriggerClientEvent('reride:notify', sourcePlayer, "事故死した車両が記録されていません。", 'error')
        return
    end

    -- 2. 車両がまだ存在するかチェック
    local vehicleNetId = eligibility.vehicle
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    if not (vehicle and DoesEntityExist(vehicle)) then
        TriggerClientEvent('reride:notify', sourcePlayer, "戻るべき車両が見つかりませんでした。", 'error')
        rerideEligible[sourcePlayer] = nil
        return
    end

    -- 3. 距離チェック (近すぎる場合はテレポートさせない)
    local distance = #(GetEntityCoords(vehicle) - GetEntityCoords(playerPed))
    if distance < 10.0 then
        TriggerClientEvent('reride:notify', sourcePlayer, "車両はすぐ近くにあります。", 'error')
        rerideEligible[sourcePlayer] = nil  
        return
    end

    -- クライアントに車両の座標も送信する
    local vehicleCoords = GetEntityCoords(vehicle)
    
    -- 全てのチェックをパスしたら、クライアントにテレポートを許可
    TriggerClientEvent('reride:teleport', sourcePlayer, vehicleNetId, vehicleCoords, eligibility.driver)
    
    print(('[Reride] Player %s used reride for vehicle %d'):format(sourcePlayer, vehicleNetId)) -- for server log

    -- 使用後は必ず権利を削除
    rerideEligible[sourcePlayer] = nil
end)

-- =================================================================
-- 定期的なクリーンアップ処理 (サーバーサイドで完結)
-- =================================================================
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(conf.ServerCleanupWait)

        -- 現在接続している全プレイヤーのリストを取得
        local activePlayers = {}
        for _, playerId in ipairs(GetPlayers()) do
            activePlayers[tonumber(playerId)] = true
        end

        local playersToCleanup = {}
        -- reride権利を持つプレイヤーが、実際に接続しているか確認
        for playerId, data in pairs(rerideEligible) do
            if not activePlayers[playerId] then
                table.insert(playersToCleanup, {playerId = playerId, vehicleNetId = data.vehicle})
            end
        end

        if #playersToCleanup > 0 then
            for _, data in ipairs(playersToCleanup) do
                -- 1. 権利情報を削除
                rerideEligible[data.playerId] = nil
                
                -- 2. サーバー側で接続していないプレイヤーのエンティティを削除
                local vehicle = NetworkGetEntityFromNetworkId(data.vehicleNetId)
                if vehicle and DoesEntityExist(vehicle) then
                    DeleteEntity(vehicle)
                    print(('[Reride] Deleted orphaned vehicle (NetID: %d) for disconnected player %s.'):format(data.vehicleNetId, data.playerId)) -- for server log
                else
                    print(('[Reride] Cleaned up eligibility for disconnected player %s (Vehicle already gone).'):format(data.playerId)) -- for server log
                end
            end
        end
    end
end)