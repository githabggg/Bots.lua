-- Initializing global variables to store the latest game state and game host process.
local CurrentGameState = CurrentGameState or nil
local ActionInProgress = ActionInProgress or false -- Prevents the agent from taking multiple actions at once.
local Logs = Logs or {}

-- Define colors for console output
local colors = {
    red = "\27[31m",
    green = "\27[32m",
    blue = "\27[34m",
    yellow = "\27[33m",
    reset = "\27[0m",
    gray = "\27[90m"
}

-- Function to add logs
function addLog(msg, text)
    Logs[msg] = Logs[msg] or {}
    table.insert(Logs[msg], text)
end

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Custom function to find the opponent with the highest energy
function findStrongestOpponent()
    local strongestOpponent = nil
    local highestEnergy = -math.huge

    for target, state in pairs(CurrentGameState.Players) do
        if target == ao.id then
            goto continue
        end

        local opponent = state

        if opponent.energy > highestEnergy then
            strongestOpponent = opponent
            highestEnergy = opponent.energy
        end

        ::continue::
    end

    return strongestOpponent
end

function isOpponentInAttackRange(player)
    local me = CurrentGameState.Players[ao.id]

    if inRange(me.x, me.y, player.x, player.y, 1) then
        return true
    end

    return false
end

function attackStrongestOpponent()
    local strongestOpponent = findStrongestOpponent()

    if strongestOpponent then
        local attackEnergy = CurrentGameState.Players[ao.id].energy * 0.5
        print(colors.red .. "Attacking strongest opponent with energy: " .. attackEnergy .. colors.reset)
        ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(attackEnergy) }) -- Attack with half of current energy
        ActionInProgress = false -- Reset ActionInProgress after attacking
        return true
    end

    return false
end

-- Decides the next action based on player proximity and energy.
-- If any player is within range, it initiates an attack; otherwise, moves towards the strongest opponent.
function decideNextAction()
    local me = CurrentGameState.Players[ao.id]

    if not attackStrongestOpponent() then
        print("No strong opponents found. Continuing to search.")
    end
end

-- Custom function to heal if health is critically low
function heal()
    local me = CurrentGameState.Players[ao.id]
    if me.health < 0.2 then
        print(colors.blue .. "Health critically low, healing..." .. colors.reset)
        ao.send({ Target = Game, Action = "Heal", Player = ao.id })
    end
end

-- Custom function to retreat if energy is low
function retreat()
    local me = CurrentGameState.Players[ao.id]
    if me.energy < 0.2 then
        local direction = get_random_direction()
        print(colors.yellow .. "Energy low, retreating..." .. colors.reset)
        ao.send({ Target = Game, Action = "Move", Direction = direction })
    end
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
    "PrintAnnouncements",
    Handlers.utils.hasMatchingTag("Action", "Announcement"),
    function(msg)
        if msg.Event == "Started-Waiting-Period" then
            ao.send({ Target = ao.id, Action = "AutoPay" })
        elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not ActionInProgress then
            ActionInProgress = true  -- ActionInProgress logic added
            ao.send({ Target = Game, Action = "GetGameState" })
        elseif ActionInProgress then -- ActionInProgress logic added
            print("Previous action still in progress. Skipping.")
        end

        print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
    end
)

-- Handler to trigger game state updates.
Handlers.add(
    "GetGameStateOnTick",
    Handlers.utils.hasMatchingTag("Action", "Tick"),
    function()
        if not ActionInProgress then -- ActionInProgress logic added
            ActionInProgress = true  -- ActionInProgress logic added
            print(colors.gray .. "Getting game state..." .. colors.reset)
            ao.send({ Target = Game, Action = "GetGameState" })
        else
            print("Previous action still in progress. Skipping.")
        end
    end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
    "AutoPay",
    Handlers.utils.hasMatchingTag("Action", "AutoPay"),
    function(msg)
        print("Auto-paying confirmation fees.")
        ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000" })
    end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
    "UpdateGameState",
    Handlers.utils.hasMatchingTag("Action", "GameState"),
    function(msg)
        local json = require("json")
        CurrentGameState = json.decode(msg.Data)
        ao.send({ Target = ao.id, Action = "UpdatedGameState" })
        print("Game state updated. Print 'CurrentGameState' for detailed view.")
        print("energy:" .. CurrentGameState.Players[ao.id].energy)
    end
)

-- Handler to decide the next best action.
Handlers.add(
    "DecideNextAction",
    Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
    function()
        if CurrentGameState.GameMode ~= "Playing" then
            print("game not start")
            ActionInProgress = false -- ActionInProgress logic added
            return
        end
        print("Deciding next action.")
        heal() -- Call custom heal function
        retreat() -- Call custom retreat function
        decideNextAction()
        ao.send({ Target = ao.id, Action = "Tick" })
    end
)

-- Handler to automatically attack when hit by another player.
Handlers.add(
    "ReturnAttack",
    Handlers.utils.hasMatchingTag("Action", "Hit"),
    function(msg)
        if not ActionInProgress then -- ActionInProgress logic added
            ActionInProgress = true  -- ActionInProgress logic added
            local playerEnergy = CurrentGameState.Players[ao.id].energy
            if playerEnergy == nil then
                print(colors.red .. "Unable to read energy." .. colors.reset)
                ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy." })
            elseif playerEnergy == 0 then
                print(colors.red .. "Player has insufficient energy." .. colors.reset)
                ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Player has no energy." })
            else
                print(colors.red .. "Returning attack." .. colors.reset)
                ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy) }) -- Attack with full energy
            end
            ActionInProgress = false -- ActionInProgress logic added
            ao.send({ Target = ao.id, Action = "Tick" })
        else
            print("Previous action still in progress. Skipping.")
        end
    end
)
