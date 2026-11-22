local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Boss (H6 boss trait): Speed cannot be lowered and it never loses its action.
--- After every action and at the start of each round, removes NOT_ACTIVE (Blind, Petrify, Paralyze, Frozen and the like) and negative STACKS_SPEED from itself. Parameters: none

local function clean(server, battle, unit)
	if not unit:isAlive() then return end
	local list = unit:getBonuses({ type = "NOT_ACTIVE" })
	local slow = unit:getBonuses({ type = "STACKS_SPEED" }):filter(function(b) return b:getVal() < 0 end)
	if list:size() > 0 then server:removeUnitBonuses(battle, unit, list) end
	if slow:size() > 0 then server:removeUnitBonuses(battle, unit, slow) end
end

function Script:onActionFinished(server, battle, unit) clean(server, battle, unit) end
function Script:onRoundStart(server, battle, unit) clean(server, battle, unit) end
function Script:onBattleStart(server, battle, unit) clean(server, battle, unit) end

return Script
