-- =================================================================
-- 通知機能
-- =================================================================
local QBCore = exports['qb-core']:GetCoreObject()
local function ShowNotification(message, type)
    QBCore.Functions.Notify(message, type or 'primary')
end

-- =================================================================
-- サーバーからの通知を受け取る
-- =================================================================
RegisterNetEvent('reride:notify')
AddEventHandler('reride:notify', function(message, type)
    ShowNotification(message, type)
end)

-- =================================================================
-- 死亡検知とサーバーへの通知
-- =================================================================
Citizen.CreateThread(function()
    local wasInVehicle = false
    local lastKnownVehicle = nil
    local isCheckingForDeath = false -- 死亡監視中かのフラグ
    local vehicleLeft = nil          -- 降りた車両
    local exitedAt = 0               -- 降りた時間

    while true do
        Citizen.Wait(250) -- ループの負荷を少し軽減
        local playerPed = PlayerPedId()

        if not DoesEntityExist(playerPed) then goto continue end

        -- 死亡監視中の処理
        if isCheckingForDeath then
            -- 監視開始から5秒経過したら監視を終了
            if GetGameTimer() - exitedAt > 5000 then
                isCheckingForDeath = false
            -- 監視中に死亡した場合
            elseif IsEntityDead(playerPed) then
                local vehicleNetId = VehToNet(vehicleLeft)
                if vehicleNetId then
                    TriggerServerEvent('reride:enable', vehicleNetId)
                end
                isCheckingForDeath = false -- 監視を終了
            end
        end

        local isInVehicle = IsPedInAnyVehicle(playerPed, false)

        -- 車両から降りた瞬間を検知
        if wasInVehicle and not isInVehicle then
            -- 最後に乗っていた車両が有効な場合、死亡監視を開始
            if lastKnownVehicle and DoesEntityExist(lastKnownVehicle) then
                isCheckingForDeath = true
                vehicleLeft = lastKnownVehicle
                exitedAt = GetGameTimer()
            end
        -- 車両に乗った瞬間を検知
        elseif not wasInVehicle and isInVehicle then
            -- 監視中だった場合はリセット
            isCheckingForDeath = false
        end

        -- 次回ループのために状態を更新
        wasInVehicle = isInVehicle
        lastKnownVehicle = isInVehicle and GetVehiclePedIsIn(playerPed, false) or nil

        ::continue::
    end
end)

-- =================================================================
-- /reride コマンド (サーバーへのリクエスト)
-- =================================================================
RegisterCommand('reride', function()
    -- コマンド実行時、サーバーにテレポートをリクエスト
    TriggerServerEvent('reride:request')
end, false)