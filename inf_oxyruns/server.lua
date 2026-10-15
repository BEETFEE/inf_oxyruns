---@diagnostic disable: undefined-global
local ox = exports.ox_inventory

local PlayerDeliveries = {}
local RunCooldown = {}

-- COOLDOWN CHECK
local function isOnCooldown(src)
    local expires = RunCooldown[src]
    if not expires then return false end
    return os.time() < expires
end

local function getCooldownRemaining(src)
    local expires = RunCooldown[src]
    if not expires then return 0 end
    return math.max(0, expires - os.time())
end


-- START RUN
RegisterNetEvent('inf_oxyruns:server:startRun', function()
    local src = source

    -- Cooldown enforcement
    if isOnCooldown(src) then
        local remaining = getCooldownRemaining(src)

        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Oxy Run',
            description = ('You must wait %s seconds before starting another run.'):format(remaining),
            type = 'error'
        })
        return
    end

    -- Require black money
    local dirtyCount = ox:GetItemCount(src, 'black_money') or 0
    local startCost = Config.RunCost or 250

    if dirtyCount < startCost then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Oxy Run',
            description = ('You need at least %s black money to start an oxy run.'):format(startCost),
            type = 'error'
        })
        return
    end

    -- Remove start cost
    ox:RemoveItem(src, 'black_money', startCost)

    -- Give packages
    local packageCount = Config.PackageCount or 20
    ox:AddItem(src, Config.PackageItem, packageCount)
    PlayerDeliveries[src] = packageCount

    -- First dropoff
    local drop = Config.Dropoffs[math.random(#Config.Dropoffs)]
    TriggerClientEvent('inf_oxyruns:client:beginRun', src, drop, PlayerDeliveries[src])
end)

-- DELIVER PACKAGE
RegisterNetEvent('inf_oxyruns:server:deliverPackage', function()
    local src = source

    -- Must have a package
    if not ox:RemoveItem(src, Config.PackageItem, 1) then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Oxy Run',
            description = 'You don’t have a package.',
            type = 'error'
        })
        return
    end

    -- CLEAN BLACK MONEY
    local dirtyCount = ox:GetItemCount(src, 'black_money') or 0

    if dirtyCount > 0 then
        local chance = math.random(1, 100)

        if chance <= (Config.CCleanRefuseChance or 25) then
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Oxy Run',
                description = 'The buyer refused to clean your money this time.',
                type = 'error'
            })
        else
            local minClean = Config.CleanMin or 150
            local maxClean = Config.CleanMax or 550
            local cleanAmount = math.random(minClean, maxClean)

            if dirtyCount >= cleanAmount then
                ox:RemoveItem(src, 'black_money', cleanAmount)
                ox:AddItem(src, 'money', cleanAmount)
            else
                ox:RemoveItem(src, 'black_money', dirtyCount)
                ox:AddItem(src, 'money', dirtyCount)
            end
        end
    end

    -- OXY REWARD
    local oxyChance = math.random(1, 100)
    if oxyChance > (Config.OxyChance or 65) then
        local oxyAmount = math.random(Config.OxyMin or 1, Config.OxyMax or 2)
        ox:AddItem(src, Config.RewardItem, oxyAmount)
    end

    
    -- XTC REWARD
    local xtcChance = math.random(1, 100)
    if xtcChance > (Config.XtcChance or 70) then
        local xtcAmount = math.random(Config.XtcMin or 1, Config.XtcMax or 2)
        ox:AddItem(src, 'xtcbaggy', xtcAmount)
    end

    -- UPDATE REMAINING DELIVERIES
    PlayerDeliveries[src] = (PlayerDeliveries[src] or 0) - 1

    -- Run finished
    if PlayerDeliveries[src] <= 0 then
        PlayerDeliveries[src] = nil

        RunCooldown[src] = os.time() + (Config.RunCooldown or 1200)

        TriggerClientEvent('inf_oxyruns:client:finishRun', src)
        return
    end

    -- New dropoff
    local drop = Config.Dropoffs[math.random(#Config.Dropoffs)]
    TriggerClientEvent('inf_oxyruns:client:newDrop', src, drop, PlayerDeliveries[src])
end)

-- PLAYER DIED
RegisterNetEvent('inf_oxyruns:server:playerDied', function()
    local src = source

    PlayerDeliveries[src] = nil
    RunCooldown[src] = os.time() + (Config.DeathCooldown or 300)

    TriggerClientEvent('inf_oxyruns:client:finishRun', src)
end)

-- DISCONNECT CLEANUP
AddEventHandler('playerDropped', function()
    local src = source
    PlayerDeliveries[src] = nil
    RunCooldown[src] = nil
end)
