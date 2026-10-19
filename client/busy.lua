-- What other resources tell the lifts about the player: busy with something of their own, so the
-- power unit and the arms are not offered. A check lives in another resource, which can error or stop
-- at any time, so it is called guarded, and it goes when that resource stops
---@type table<string, LiftBusyEntry>
local checks = {}

-- Functions crossing an export arrive as callable funcref tables
---@param value function | table
---@return boolean callable
local function isCallable(value)
    if (type(value) == "function") then return true end

    local mt = type(value) == "table" and getmetatable(value)

    return type(mt) == "table" and mt.__call ~= nil
end

---@param vehicle? integer @ The car the arms would be set under, nil for the power unit
---@return boolean busy
function IsPlayerBusy(vehicle)
    for _, entry in pairs(checks) do
        local ok, busy = pcall(entry.isBusy, vehicle)

        if (not ok) then
            Z.debug("Lift busy check failed", entry.resource, entry.name, busy)
        elseif (busy == true) then
            return true
        end
    end

    return false
end

-- Registering again under the same name replaces the earlier check
---@param name string @ Unique within the registering resource
---@param isBusy fun(vehicle?: integer): boolean
---@return boolean registered
exports("RegisterBusyCheck", function(name, isBusy)
    if (type(name) ~= "string" or name == "" or not isCallable(isBusy)) then return false end

    local resource = GetInvokingResource() or ResName
    checks[resource .. ":" .. name] = {resource = resource, name = name, isBusy = isBusy}

    return true
end)

---@param name string
---@return boolean removed
exports("RemoveBusyCheck", function(name)
    local key = (GetInvokingResource() or ResName) .. ":" .. tostring(name)
    if (not checks[key]) then return false end

    checks[key] = nil

    return true
end)

-- A stopped resource's function references can no longer be called
---@param resource string
AddEventHandler("onResourceStop", function(resource)
    for key, entry in pairs(checks) do
        if (entry.resource == resource) then checks[key] = nil end
    end
end)