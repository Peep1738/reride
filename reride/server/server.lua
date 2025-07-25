local rerideEligible = {}
RegisterNetEvent('reride:enable')
RegisterNetEvent('reride:request')
RegisterNetEvent('reride:notify')

-- =================================================================
-- rerideの権利をサーバーに記録
-- =================================================================
AddEventHandler('reride:enable', function(vehicleNetId)
    local sourcePlayer = source
    -- 念のため、車両のネットワークIDが存在するか確認
    local vehicle = vehicleNetId and NetworkGetEntityFromNetworkId(vehicleNetId)
    if vehicle and DoesEntityExist(vehicle) then
        print(('[Reride] Player %s is now eligible for vehicle %d'):format(sourcePlayer, vehicleNetId))  --for server log
        rerideEligible[sourcePlayer] = vehicleNetId
    end
end)

-- =================================================================
-- rerideのリクエストを処理
-- =================================================================
AddEventHandler('reride:request', function()
    local sourcePlayer = source
    local playerPed = GetPlayerPed(sourcePlayer)
    
    -- 1. 権利があるかサーバー側でチェック
    local vehicleNetId = rerideEligible[sourcePlayer]
    if not vehicleNetId then
        TriggerClientEvent('reride:notify', sourcePlayer, "事故死した車両が記録されていません。", 'error')
        return
    end

    -- 2. 車両がまだ存在するかチェック
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

    -- 全てのチェックをパスしたら、サーバーがテレポートを実行
    SetPedIntoVehicle(playerPed, vehicle, -1)
    
    TriggerClientEvent('reride:notify', sourcePlayer, "最後に事故死した車両に戻りました。", 'success')
    print(('[Reride] Player %s used reride for vehicle %d'):format(sourcePlayer, vehicleNetId))  --for server log

    -- 使用後は必ず権利を削除
    rerideEligible[sourcePlayer] = nil
end)

-- =================================================================
-- プレイヤー切断時の処理
-- =================================================================
AddEventHandler('playerDropped', function(reason)
    local sourcePlayer = source
    -- プレイヤーが切断したら、rerideの権利情報を削除する
    if rerideEligible[sourcePlayer] then
        print(('[Reride] Player %s disconnected, removing reride eligibility.'):format(sourcePlayer)) --for server log
        rerideEligible[sourcePlayer] = nil
    end
end)