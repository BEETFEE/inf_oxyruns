---@diagnostic disable: undefined-global
-- Decorators ensure peds persist across reloads without duplication
DecorRegister("inf_oxy_startped", 2)
DecorRegister("inf_oxy_droppped", 2)

local prog_Dee = exports.prog_Dee

local inRun = false
local currentDrop = nil
local deliveryZone = nil
local boxProp = nil
local oxyPed = nil
local deliveriesLeft = 0
local activeDropPed = nil
local deliveryBlip = nil

-- FACE COORD
local function lookEnt(coords)
    TaskTurnPedToFaceCoord(PlayerPedId(), coords.x, coords.y, coords.z, 1500)
end

-- CARRY ANIMIMATION
local function playCarryAnim()
    local ped = PlayerPedId()
    local dict = "anim@heists@box_carry@"
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do Wait(0) end
    TaskPlayAnim(ped, dict, "idle", 8.0, -8.0, -1, 49, 0, false, false, false)
end

local function stopCarryAnim()
    ClearPedTasks(PlayerPedId())
end

-- BOX PROP
local function attachBoxProp()
    if boxProp and DoesEntityExist(boxProp) then return end

    local ped = PlayerPedId()
    local model = "prop_cs_cardbox_01"

    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end

    boxProp = CreateObject(model, 0.0, 0.0, 0.0, true, true, false)

    AttachEntityToEntity(
        boxProp,
        ped,
        GetPedBoneIndex(ped, 60309),
        0.025, 0.08, 0.255,
        -145.0, 290.0, 0.0,
        true, true, false, true, 1, true
    )
end

local function removeBoxProp()
    if boxProp and DoesEntityExist(boxProp) then
        DeleteEntity(boxProp)
        boxProp = nil
    end
end

-- FORCE CARRY
local function forceCarryState()
    SetTimeout(250, function()
        local ped = PlayerPedId()
        local count = exports.ox_inventory:GetItemCount(Config.PackageItem)
        if count < 1 then return end

        playCarryAnim()

        if not boxProp or not DoesEntityExist(boxProp) then
            attachBoxProp()
        end
    end)
end

-- ANIMATION WATCHDOG
CreateThread(function()
    while true do
        Wait(300)

        if not inRun then goto continue end

        local ped = PlayerPedId()
        local count = exports.ox_inventory:GetItemCount(Config.PackageItem)

        if count > 0 then
            if not IsEntityPlayingAnim(ped, "anim@heists@box_carry@", "idle", 3) then
                forceCarryState()
            end
        end

        ::continue::
    end
end)

-- INVENTORY SYNC
AddEventHandler("ox_inventory:updateInventory", function()
    if not inRun then return end

    local count = exports.ox_inventory:GetItemCount(Config.PackageItem)

    if count > 0 then
        forceCarryState()
    else
        removeBoxProp()
        stopCarryAnim()
    end
end)

-- DELIVERY BLIP
local function createDeliveryBlip(coords)
    if deliveryBlip then
        RemoveBlip(deliveryBlip)
        deliveryBlip = nil
    end

    deliveryBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(deliveryBlip, 514)
    SetBlipColour(deliveryBlip, 5)
    SetBlipScale(deliveryBlip, 0.9)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Oxy Delivery")
    EndTextCommandSetBlipName(deliveryBlip)
end

local function removeDeliveryBlip()
    if deliveryBlip then
        RemoveBlip(deliveryBlip)
        deliveryBlip = nil
    end
end

-- DELIVERY ZONE
local function createDeliveryZone(drop)
    if deliveryZone then
        exports.ox_target:removeZone(deliveryZone)
        deliveryZone = nil
    end

    deliveryZone = exports.ox_target:addSphereZone({
        coords = drop,
        radius = 1.5,
        drawSprite = true, 
        options = {
            {
                name = 'inf_oxy_dummy',
                label = '',
                icon = '',
                canInteract = function() return false end,
                onSelect = function() end
            }
        }
    })
end

local function removeDeliveryZone()
    if deliveryZone then
        exports.ox_target:removeZone(deliveryZone)
        deliveryZone = nil
    end
end


--  DROP OFF PED SPAWN SYSTEM

local randomModels = Config.DropoffPedModels

local function spawnDropPed(coords)
    local dropPos = vector3(coords.x, coords.y, coords.z)
    local model = joaat(randomModels[math.random(#randomModels)])

    -- Load model
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end

    -- Load collision at location BEFORE spawning ped
    RequestCollisionAtCoord(dropPos.x, dropPos.y, dropPos.z)
    local timeout = GetGameTimer() + 2000
    while not HasCollisionLoadedAroundEntity(PlayerPedId()) do
        if GetGameTimer() > timeout then break end
        Wait(10)
    end

    -- EXACT SAME SPAWN LOGIC AS START PED
    activeDropPed = CreatePed(
        4,
        model,
        dropPos.x,
        dropPos.y,
        dropPos.z,
        coords.w,
        false,
        false
    )

    DecorSetBool(activeDropPed, "inf_oxy_droppped", true)

    FreezeEntityPosition(activeDropPed, true)
    SetEntityInvincible(activeDropPed, true)
    SetBlockingOfNonTemporaryEvents(activeDropPed, true)

    -- IF PED IS BELOW GROUND, SNAP TO SURFACE
    Wait(250)

    local pedZ = GetEntityCoords(activeDropPed).z
    if pedZ < dropPos.z - 1.0 then
        local success, groundZ = GetGroundZFor_3dCoord(dropPos.x, dropPos.y, dropPos.z + 10.0)
        if success then
            SetEntityCoords(activeDropPed, dropPos.x, dropPos.y, groundZ + 1.0, false, false, false, false)
        end
    end

    -- OX TARGET
    exports.ox_target:addLocalEntity(activeDropPed, {
        {
            name = 'inf_oxy_deliver',
            icon = 'fa-solid fa-handshake',
            label = 'Deliver Package',
            canInteract = function()
                return inRun and currentDrop and currentDrop == coords
            end,
            onSelect = function()
                TriggerEvent('inf_oxyruns:client:deliverPackage')
            end
        }
    })
end

local function removeDropPed()
    if activeDropPed and DoesEntityExist(activeDropPed) then
        DeleteEntity(activeDropPed)
        activeDropPed = nil
    end
end

-- RUN EVENTS
RegisterNetEvent('inf_oxyruns:client:startRun', function()
    TriggerServerEvent('inf_oxyruns:server:startRun')
end)

RegisterNetEvent('inf_oxyruns:client:beginRun', function(drop, remaining)
    inRun = true
    deliveriesLeft = remaining
    currentDrop = drop

    SetNewWaypoint(drop.x, drop.y)
    createDeliveryBlip(drop)

    forceCarryState()
    createDeliveryZone(drop)
    spawnDropPed(drop)
end)

RegisterNetEvent('inf_oxyruns:client:deliverPackage', function()
    if not inRun or not currentDrop then return end

    lookEnt(currentDrop)

    prog_Dee:Start(2500, "Delivering Package", function(success)
        removeBoxProp()
        stopCarryAnim()
        removeDropPed()
        removeDeliveryBlip()

        if not success then return end

        TriggerServerEvent('inf_oxyruns:server:deliverPackage')
    end)
end)

RegisterNetEvent('inf_oxyruns:client:newDrop', function(drop, remaining)
    deliveriesLeft = remaining
    currentDrop = drop

    SetNewWaypoint(drop.x, drop.y)
    createDeliveryBlip(drop)

    forceCarryState()
    createDeliveryZone(drop)
    spawnDropPed(drop)
end)

RegisterNetEvent('inf_oxyruns:client:finishRun', function()
    inRun = false
    deliveriesLeft = 0
    currentDrop = nil

    removeDeliveryZone()
    removeDropPed()
    removeDeliveryBlip()
    removeBoxProp()
    stopCarryAnim()
end)

-- DEATH DETECTION
CreateThread(function()
    local wasDead = false

    while true do
        Wait(500)

        local ped = PlayerPedId()
        local isDead = IsEntityDead(ped)

        if isDead and not wasDead then
            wasDead = true

            if inRun then
                removeDropPed()
                removeDeliveryZone()
                removeDeliveryBlip()
                removeBoxProp()
                stopCarryAnim()

                TriggerServerEvent('inf_oxyruns:server:playerDied')
            end
        elseif not isDead and wasDead then
            wasDead = false
        end
    end
end)

-- RESOURCE STOP CLEANUP
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    for _, ped in ipairs(GetGamePool('CPed')) do
        if DecorExistOn(ped, "inf_oxy_startped") or DecorExistOn(ped, "inf_oxy_droppped") then
            DeleteEntity(ped)
        end
    end

    if boxProp and DoesEntityExist(boxProp) then DeleteEntity(boxProp) end
    if deliveryZone then exports.ox_target:removeZone(deliveryZone) end
    if deliveryBlip then RemoveBlip(deliveryBlip) end

    ClearPedTasks(PlayerPedId())
end)

-- START PED SYSTEM
local function spawnStartPed()
    local cfg = Config.StartPed
    local model = joaat(cfg.model)

    -- Reuse existing decorated ped
    for _, ped in ipairs(GetGamePool('CPed')) do
        if DecorExistOn(ped, "inf_oxy_startped") then
            oxyPed = ped
            FreezeEntityPosition(oxyPed, true)
            SetEntityInvincible(oxyPed, true)
            SetBlockingOfNonTemporaryEvents(oxyPed, true)
            SetEntityHeading(oxyPed, cfg.heading)
            return
        end
    end

    -- Spawn new ped
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end

    oxyPed = CreatePed(
        4,
        model,
        cfg.coords.x,
        cfg.coords.y,
        cfg.coords.z,
        cfg.heading,
        false,
        false
    )

    DecorSetBool(oxyPed, "inf_oxy_startped", true)

    FreezeEntityPosition(oxyPed, true)
    SetEntityInvincible(oxyPed, true)
    SetBlockingOfNonTemporaryEvents(oxyPed, true)
end

RegisterNetEvent('inf_oxyruns:client:spawnStartPed', function()
    spawnStartPed()

    exports.ox_target:addLocalEntity(oxyPed, {
        {
            name = 'inf_oxy_start',
            icon = 'fa-solid fa-box',
            label = 'Start Oxy Run',
            canInteract = function()
                return not inRun
            end,
            onSelect = function()
                TriggerEvent('inf_oxyruns:client:startRun')
            end
        }
    })
end)

--AUTO-SPAWN START PED

-- Spawn when resource starts
CreateThread(function()
    TriggerEvent('inf_oxyruns:client:spawnStartPed')
end)

-- Spawn when player loads (ox_core)
AddEventHandler('ox:playerLoaded', function()
    TriggerEvent('inf_oxyruns:client:spawnStartPed')
end)
