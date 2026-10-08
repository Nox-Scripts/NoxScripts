-- Standalone replacement for the parts of prp-bridge that prp-dartboard uses.
-- Framework: qb-core. Nothing here needs prp-bridge to be installed or started.
--
-- Provides (same names/signatures the rest of the script already calls):
--   bridge.fw.notify(type, message, title, duration)
--   bridge.fw.showTextUI / hideTextUI
--   bridge.fw.confirmDialog / inputDialog
--   bridge.fw.contextMenu / showContext
--   bridge.target.addModel / removeModel   (qb-target or ox_target)

local resourceName = GetCurrentResourceName()

local fw = {}
local target = {}

-- Notifications -------------------------------------------------------------

local QB_NOTIFY_TYPES = {
    inform = "primary",
    warning = "primary",
    error = "error",
    success = "success",
}

---@param type 'inform' | 'error' | 'success' | 'warning'
---@param message string
---@param title? string
---@param duration? number
function fw.notify(type, message, title, duration)
    type = type or "inform"
    duration = duration or 3000

    if CompatConfig and CompatConfig.Notify == "qb" then
        local QBCore = exports["qb-core"]:GetCoreObject()
        QBCore.Functions.Notify(message or "", QB_NOTIFY_TYPES[type] or "primary", duration)
        return
    end

    lib.notify({
        type = type,
        title = title,
        description = message or "",
        duration = duration,
    })
end

-- Server -> client notifications (bridge.fw.notify on the server side).
RegisterNetEvent("prp-dartboard:client:notify", function(type, message, title, duration)
    fw.notify(type, message, title, duration)
end)

-- Text UI -------------------------------------------------------------------

---@param text string
---@param options table
function fw.showTextUI(text, options)
    lib.showTextUI(text, options)
end

function fw.hideTextUI()
    lib.hideTextUI()
end

-- Dialogs / menus (all ox_lib) ----------------------------------------------

---@param header string
---@param content string
---@param labels? { cancel?: string, confirm?: string }
---@param timeout? number
---@return 'cancel' | 'confirm' | nil
function fw.confirmDialog(header, content, labels, timeout)
    return lib.alertDialog({
        header = header,
        content = content,
        centered = true,
        cancel = true,
        labels = labels, -- nil -> ox_lib's own translated Cancel/Confirm
    }, timeout)
end

---@param heading string
---@param rows table
---@param options table?
function fw.inputDialog(heading, rows, options)
    return lib.inputDialog(heading, rows, options)
end

---@param payload table
function fw.contextMenu(payload)
    lib.registerContext(payload)
end

---@param contextId string
function fw.showContext(contextId)
    lib.showContext(contextId)
end

-- Target (qb-target / ox_target) --------------------------------------------

local DEFAULT_TARGET_DISTANCE = 2.5
local TARGET_WAIT_MS = 30000

local activeTarget = nil ---@type string?
local warned = false

local function warnNoTarget()
    if warned then return end
    warned = true
    print(("^1[%s] No target resource found (qb-target / ox_target). The dartboard cannot be interacted with. " ..
        "Start one of them before this resource or set CompatConfig.Target in editable/sh_compat.lua.^0"):format(resourceName))
end

-- Resolves (and waits for) the target resource so start order does not matter.
---@return string?
local function resolveTarget()
    if activeTarget then
        return activeTarget
    end

    local wanted = CompatConfig and CompatConfig.Target or "auto"
    local deadline = GetGameTimer() + TARGET_WAIT_MS

    repeat
        if wanted == "qb-target" or wanted == "ox_target" then
            if GetResourceState(wanted) == "started" then
                activeTarget = wanted
                return activeTarget
            end
        else
            if GetResourceState("qb-target") == "started" then
                activeTarget = "qb-target"
                return activeTarget
            end
            if GetResourceState("ox_target") == "started" then
                activeTarget = "ox_target"
                return activeTarget
            end
        end
        Wait(250)
    until GetGameTimer() > deadline

    warnNoTarget()
    return nil
end

-- qb-target keys everything by option label, so remember label <-> name.
local qbLabelByName = {}
local qbRegistered = {}

-- Converts an ox_target style option (what the dartboard defines) to qb-target.
local function toQbOption(option, distance)
    local qbOption = {
        type = "client",
        icon = option.icon,
        label = option.label,
        distance = distance,
        canInteract = option.canInteract,
    }

    if option.onSelect then
        qbOption.action = function(entity)
            local ped = cache.ped or PlayerPedId()
            local coords = (entity and DoesEntityExist(entity)) and GetEntityCoords(entity) or GetEntityCoords(ped)

            option.onSelect({
                entity = entity,
                coords = coords,
                distance = #(GetEntityCoords(ped) - coords),
                name = option.name,
            })
        end
    end

    return qbOption
end

---@param models number | string | (number | string)[]
---@param options table[]
function target.addModel(models, options)
    local name = resolveTarget()
    if not name then return end

    if name == "ox_target" then
        exports.ox_target:addModel(models, options)
        return
    end

    local qbOptions, labels = {}, {}
    local maxDistance = DEFAULT_TARGET_DISTANCE

    for i = 1, #options do
        local option = options[i]
        local distance = tonumber(option.distance) or DEFAULT_TARGET_DISTANCE

        if distance > maxDistance then
            maxDistance = distance
        end

        qbLabelByName[option.name] = option.label
        labels[#labels + 1] = option.label
        qbOptions[#qbOptions + 1] = toQbOption(option, distance)
    end

    -- qb-target clamps each option's distance to the group distance, so the
    -- group distance has to be the largest one.
    exports["qb-target"]:AddTargetModel(models, {
        options = qbOptions,
        distance = maxDistance,
    })

    qbRegistered[#qbRegistered + 1] = { models = models, labels = labels }
end

---@param models number | string | (number | string)[]
---@param optionNames string | string[]
function target.removeModel(models, optionNames)
    local name = resolveTarget()
    if not name then return end

    if name == "ox_target" then
        exports.ox_target:removeModel(models, optionNames)
        return
    end

    if type(optionNames) == "string" then
        optionNames = { optionNames }
    end

    local labels = {}
    for i = 1, #optionNames do
        local label = qbLabelByName[optionNames[i]]
        if label then
            labels[#labels + 1] = label
        end
    end

    if #labels == 0 then return end

    exports["qb-target"]:RemoveTargetModel(models, labels)
end

-- ox_target drops a stopped resource's options on its own; qb-target does not,
-- so clean up here to avoid duplicated options after `restart NOX-Darts`.
AddEventHandler("onResourceStop", function(stoppedResource)
    if stoppedResource ~= resourceName then return end
    if activeTarget ~= "qb-target" or GetResourceState("qb-target") ~= "started" then return end

    for i = 1, #qbRegistered do
        local entry = qbRegistered[i]
        pcall(function()
            exports["qb-target"]:RemoveTargetModel(entry.models, entry.labels)
        end)
    end
end)

bridge = {
    fw = fw,
    target = target,
}
