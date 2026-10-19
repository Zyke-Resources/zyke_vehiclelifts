-- Editable action gates; return false plus a locale key to deny with a notification. Other resources
-- refuse work on a lift through RegisterLiftRules instead, see README.md

---@param plyId PlayerId
---@param liftId integer
---@param action LiftAction
---@return boolean allowed
---@return string? reason
function CanWorkLift(plyId, liftId, action)
    return true
end