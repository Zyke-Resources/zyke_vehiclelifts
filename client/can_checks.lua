-- Editable local gates; the server re-validates every mutation

---@param liftId integer
---@param action LiftAction
---@return boolean allowed
---@return string? reason
function CanWorkLift(liftId, action)
    return true
end