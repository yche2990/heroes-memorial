local Base = require("combat/combatScript")
local R = require("heroes-memorial.h7:combat/h7RuneLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Aura upkeep of the H7 memorial runes (battle-wide hidden combat event, added with addBattleBonus when the first Rune Stone is summoned; every stack inherits a copy).
--- After each action, each move and at the start of each round, all rune auras are recalculated from the current situation (h7RuneLib.refresh: only changed bonuses are touched).
--- When the Rune of Radiance expires (the N-round bonus on the stone disappears at round start), the aura goes back to its original value at round start.
--- Parameters: none

local function run(server, battle)
	R.refresh(server, battle)
end

function Script:onActionFinished(server, battle, unit, other, payload)
	-- Each action calls this once for "the actor + every affected stack": it is only computed on the actor (or the first stack to receive it for hero casts),
	-- and refresh only touches what changed, so repeated calls have no side effects
	if other ~= nil and other:unitID() ~= unit:unitID() then return end
	run(server, battle)
end

function Script:onAfterMove(server, battle, unit, other, payload)
	run(server, battle)
end

function Script:onRoundStart(server, battle, unit, other, payload)
	if not R.isStone(unit) then return end
	run(server, battle)
end

return Script
