-- This client's guess of the server's game timer, which every lift's carriages travel by, see
-- shared/lift.lua. It counts on the network time, since the game timer stands still while the
-- game hitches and would fall behind the server by every hitch. The server is asked the first time the
-- guess is wanted, again every few seconds while its answers come back slowly, as they can while this
-- client loads in or the server hitches, and once a minute after that. What the server sent here was
-- stamped on its timer before it left, so the guess never stays behind those stamps
ServerClock = {}

-- Milliseconds a question may take for its answer to be kept until the next minute's
local quickAnswer = 500
local askAgainMs = 5000
local recheckMs = 60000
-- Milliseconds the network time may run apart from the game timer between two looks before the guess
-- is asked for again, as the network time can be set again while this client joins
local driftMs = 1000

---@type number? @ Milliseconds the server's game timer is ahead of this client's network time
local ahead
---@type number? @ Milliseconds it is ahead by at least, from the answers and stamps that got here
local least
---@type number? @ Milliseconds the question behind the guess took, huge once the guess may be off
local aheadTook
---@type integer? @ Network time the last answer came in at
local answeredAt
---@type integer?
local lookedNetwork
---@type integer?
local lookedGame
local asking = false

local function ask()
    if (asking) then return end

    asking = true

    CreateThread(function()
        local sent, sentGame = GetNetworkTimeAccurate(), GetGameTimer()
        local now = Z.callback.await("zyke_vehiclelifts:GetTimer")
        local answered = GetNetworkTimeAccurate()
        -- The game timer still counts a question asked before the network time ran
        local took = math.max(answered - sent, GetGameTimer() - sentGame)

        asking, answeredAt = false, answered

        if (type(now) ~= "number") then return end

        -- The server read its timer between the question and the answer, so a floor above that is from
        -- before the network time was set again
        if (least and least > now - sent) then least = nil end

        ServerClock.atLeast(now)

        -- The answer is taken to have been under way for half of the time the question took, so the
        -- quickest is the closest. A quick one replaces a slower one, which may have gone stale
        if (not aheadTook or took <= math.max(quickAnswer, aheadTook)) then ahead, aheadTook = now - (sent + answered) / 2.0, took end
    end)
end

---@return integer? now @ Milliseconds on the server's game timer, nil until the server has answered
function ServerClock.timer()
    local network, game = GetNetworkTimeAccurate(), GetGameTimer()

    -- The network time may have been set again since the last look, or the game hitched for a while
    if (aheadTook and lookedNetwork and math.abs(network - lookedNetwork - (game - lookedGame)) > driftMs) then aheadTook = math.huge end

    lookedNetwork, lookedGame = network, game

    local askEvery = (not aheadTook or aheadTook > quickAnswer) and askAgainMs or recheckMs
    if (not answeredAt or network - answeredAt >= askEvery) then ask() end
    if (not ahead) then return nil end

    return math.floor(math.max(ahead, least or ahead) + network)
end

-- The server stamped a value it sent here on its game timer, which has come at least that far since
---@param stamp? integer @ Milliseconds on the server's game timer
function ServerClock.atLeast(stamp)
    if (type(stamp) ~= "number") then return end

    least = math.max(least or -math.huge, stamp - GetNetworkTimeAccurate())
end