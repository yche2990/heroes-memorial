local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local F = require("combat/h6FormSwap")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Temporary form of Dual Form (round 360b): carried by both forms of the Fate Spinner and Fate Weaver, only acts on the "temporary form"
--- (the one carrying the original stack id mark; the one in the army at battle start has no mark and nothing happens here).
---   After each action (its own or one it is caught in): health is synced to the hidden original stack; if the original is dead but the temporary form was resurrected, switch back to the original.
---   When the temporary form dies, the original stack dies with it (no second death event).

function Script:onActionFinished(server, battle, unit, other, payload)
	if unit:isGhost() then return end
	local O = F.original(battle, unit)
	if O == nil then return end
	if unit:isAlive() and not O:isAlive() then
		F.swapBack(server, battle, unit, O)
		server:refreshBattleUnits(battle)
		return
	end
	F.syncHealth(server, battle, unit, O)
end

function Script:onDeath(server, battle, unit, other, payload)
	local O = F.original(battle, unit)
	if O == nil or not O:isAlive() then return end
	F.syncHealth(server, battle, unit, O)
end

return Script
