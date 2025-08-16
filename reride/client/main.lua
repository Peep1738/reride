local QBCore = exports['qb-core']:GetCoreObject()
local rerideVehicle = nil -- クライアントが保護している車両

local conf = {}
-- クライアントの監視ループの間隔 (ミリ秒)
conf.ClientLoopWait = 500
-- 遠くの車両を待つ際のループ間隔 (ミリ秒)
conf.GetVehicleNetIdLoopWait = 200

-- =================================================================
-- 通知機能
-- =================================================================
local function ShowNotification(message, type)
    QBCore.Functions.Notify(message, type or 'primary')
end

-- =================================================================
-- サーバーからの通知を受け取る
-- =================================================================
RegisterNetEvent('reride:notify', ShowNotification)

-- =================================================================
-- 死亡検知と車両の保護
-- =================================================================
Citizen.CreateThread(function()
    local lastKnownVehicle = nil
    local wasDriver = false
    local hasSentRerideEvent = false

    while true do
        Citizen.Wait(conf.ClientLoopWait)
        
        local playerPed = PlayerPedId()

        if not DoesEntityExist(playerPed) then goto continue end

        local isInVehicle = IsPedInAnyVehicle(playerPed, false)

        -- プレイヤーが車両に乗っている場合、車両と運転手情報を常に更新
        if isInVehicle then
            local vehicle = GetVehiclePedIsIn(playerPed, false)
            if vehicle then
                local driverPed = GetPedInVehicleSeat(vehicle, -1)
                lastKnownVehicle = vehicle
                wasDriver = (playerPed == driverPed)
            end
        end

        -- プレイヤーが死亡した場合
        if IsEntityDead(playerPed) then
            -- 既にイベントを送信済みでなく、最後に乗っていた車両が有効な場合
            if not hasSentRerideEvent and lastKnownVehicle and DoesEntityExist(lastKnownVehicle) then
                local vehicleNetId = VehToNet(lastKnownVehicle)
                if vehicleNetId then
                    -- 車両を保護し、サーバーに判定を送信
                    rerideVehicle = lastKnownVehicle
                    SetEntityAsMissionEntity(rerideVehicle, true, true)
                    TriggerServerEvent('reride:enable', vehicleNetId, wasDriver)
                    hasSentRerideEvent = true
                end
            end
        else
            -- 生きている場合はフラグをリセットし、次の死亡検知に備える
            hasSentRerideEvent = false
        end

        ::continue::
    end
end)

-- =================================================================
-- /reride コマンド (サーバーへのリクエスト)
-- =================================================================
RegisterCommand('reride', function()
    TriggerServerEvent('reride:request')
end, false)

-- =================================================================
-- サーバーからテレポートの許可を受け、クライアント側で実行する
-- =================================================================
RegisterNetEvent('reride:teleport', function(vehicleNetId, vehicleCoords, wasDriver)
    Citizen.CreateThread(function()
        local playerPed = PlayerPedId()
        local vehicle = NetToVeh(vehicleNetId)
        local playerWasMoved = false

        -- 車両が遠くにある場合の処理
        if not (vehicle and DoesEntityExist(vehicle)) then
            ShowNotification("遠くの車両へ移動します...", "primary")

            FreezeEntityPosition(playerPed, true)
            SetEntityVisible(playerPed, false, false)

            local foundGround, groundZ = GetGroundZFor_3dCoord(vehicleCoords.x, vehicleCoords.y, vehicleCoords.z, false) -- 遠くの車両へ飛んだ際に高所死亡リスクを減らすための安全な地面座標取得用
            local safeCoords = vector3(vehicleCoords.x, vehicleCoords.y, foundGround and groundZ or vehicleCoords.z)
            SetEntityCoords(playerPed, safeCoords.x, safeCoords.y, safeCoords.z, false, false, false, true)
            playerWasMoved = true

            local timeout = 5000
            local startTime = GetGameTimer()
            while not DoesEntityExist(NetToVeh(vehicleNetId)) do
                Citizen.Wait(conf.GetVehicleNetIdLoopWait)
                if GetGameTimer() - startTime > timeout then
                    FreezeEntityPosition(playerPed, false)
                    SetEntityVisible(playerPed, true, false)
                    ShowNotification("車両の取得に失敗しました。", 'error')
                    return
                end
            end
            vehicle = NetToVeh(vehicleNetId)
        end
        
        -- プレイヤーの状態を元に戻す（遠くに移動した場合のみ）
        if playerWasMoved then
            FreezeEntityPosition(playerPed, false)
            SetEntityVisible(playerPed, true, false)
        end

        local maxSeats = GetVehicleMaxNumberOfPassengers(vehicle) -- テレポ先の車両の座席数取得
        local foundSeat = false

         -- wasDriverに基づいて座席を探す
        if wasDriver then
            -- 運転手だった場合、運転席が空いているかチェック
            if IsVehicleSeatFree(vehicle, -1) then
                SetPedIntoVehicle(playerPed, vehicle, -1)
                ShowNotification("最後に事故死した車両に戻りました。", 'success')
                foundSeat = true
            end
        else
            -- 運転手でなかった場合、助手席以降の空いている席を探す
            for i = 0, maxSeats, 1 do
                if IsVehicleSeatFree(vehicle, i) then
                    SetPedIntoVehicle(playerPed, vehicle, i)
                    ShowNotification("最後に事故死した車両に戻りました。", 'success')
                    foundSeat = true
                    break
                end
            end
        end

        -- テレポート処理が成功した場合、車両の保護を解除
        if foundSeat then
            SetEntityAsMissionEntity(vehicle, false, false)
            rerideVehicle = nil
        end

        -- 座席が見つからなかった場合の処理はそのまま
        if not foundSeat then
            ShowNotification("車両に戻れませんでした。空いている座席がありません。", 'error')
        end

    end)
end)

-- =================================================================
-- 停止時に保護を解除する念のための処理
-- =================================================================
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end

    -- このクライアントが車両を保護していた場合、切断時に保護を解除する
    if rerideVehicle and DoesEntityExist(rerideVehicle) then
        SetEntityAsMissionEntity(rerideVehicle, false, false)
    end
end)