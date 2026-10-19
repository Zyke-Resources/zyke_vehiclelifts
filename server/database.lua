-- The lifts placed with the admin tool, kept in the database so they stand again after a server restart.
-- The table is made as the resource starts, so there is nothing to import. Each placed lift knows its
-- row, and taking it away with the tool deletes the row. Lifts of shared/lifts.lua and of other
-- resources are never saved here
LiftDatabase = {}

local createTable = [[
CREATE TABLE IF NOT EXISTS `zyke_vehiclelifts` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `kind` varchar(50) NOT NULL DEFAULT 'twopost',
  `x` double NOT NULL,
  `y` double NOT NULL,
  `z` double NOT NULL,
  `heading` double NOT NULL,
  `creator` varchar(100) DEFAULT NULL,
  `created` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]]

---@type table<integer, integer> @ The row of each placed lift, by lift
local rows = {}
-- The saved lifts stand, so a lift placed or taken away from now on is matched to its row
local ready = false

---@param lift ZykeVehicleLift
---@param creator? string @ The character identifier of the admin who placed it
local function insert(lift, creator)
    local rowId = MySQL.insert.await("INSERT INTO `zyke_vehiclelifts` (`kind`, `x`, `y`, `z`, `heading`, `creator`) VALUES (?, ?, ?, ?, ?, ?)", {lift.kind, lift.coords.x, lift.coords.y, lift.coords.z, lift.heading, creator})
    if (rowId) then rows[lift.id] = rowId end
end

---@param rowId integer
local function delete(rowId)
    MySQL.update.await("DELETE FROM `zyke_vehiclelifts` WHERE `id` = ?", {rowId})
end

-- Saves a lift placed with the admin tool
---@param liftId integer
---@param plyId PlayerId
function LiftDatabase.save(liftId, plyId)
    while (not ready) do Wait(100) end

    -- Placing on the spot of a lift of shared/lifts.lua gives that lift back, which is not saved
    local lift = GetLifts()[liftId]
    if (not lift or not lift.placed or rows[liftId]) then return end

    insert(lift, Z.getIdentifier(plyId))
end

-- Deletes the row of a placed lift that was taken away
---@param liftId integer
function LiftDatabase.remove(liftId)
    while (not ready) do Wait(100) end

    local rowId = rows[liftId]
    if (not rowId) then return end

    rows[liftId] = nil

    delete(rowId)
end

CreateThread(function()
    MySQL.query.await(createTable)

    local saved = MySQL.query.await("SELECT `id`, `kind`, `x`, `y`, `z`, `heading` FROM `zyke_vehiclelifts`") or {}

    for _, row in ipairs(saved) do
        -- A lift kept over a restart of this resource stands already, and is given back
        local liftId = CreateLift({coords = vec3(row.x, row.y, row.z), heading = row.heading, kind = row.kind}, ResName, true)

        if (not liftId) then
            Z.debug("Saved lift could not be stood", row.id, row.kind)
        elseif (rows[liftId]) then
            -- Two rows for one spot would bring the lift back after it was taken away
            delete(row.id)
        else
            rows[liftId] = row.id
        end
    end

    -- Lifts placed before they were saved stand again from before a restart of this resource, and are saved now
    for liftId, lift in pairs(GetLifts()) do
        if (lift.placed and not rows[liftId]) then insert(lift) end
    end

    ready = true
end)