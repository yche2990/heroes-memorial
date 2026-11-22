local Base = require("combat/combatScript")
local Z = require("combat/h7dZones")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Battle-wide hidden script of H7 Living Shelter (added with addBattleBonus the first time h7LivingShelter raises a shelter; every stack inherits a copy).
---   onBeforeMove: before a friendly stack moves, the friendly Treants' shelter obstacles are removed (shelters only stop enemies; the obstacles are traps, so friendly stacks walking in would stop too).
---   onActionFinished: after each action (the actor's own copy; for hero casts every affected stack runs it, with the same re-added result),
---                    all shelter obstacles are removed and re-added by the current situation for Treants with an active shelter (stacks leaving adjacent hexes, Treant deaths etc. are updated here).
--- Parameters: none

function Script:onBeforeMove(server, battle, unit, other, payload)
	if battle:getTacticDistance() > 0 or not unit:isAlive() then return end
	Z.removeSideShelters(server, battle, unit:getSide())
end

function Script:onActionFinished(server, battle, unit, other, payload)
	if other ~= nil and other:unitID() ~= unit:unitID() then return end
	Z.refreshShelters(server, battle)
end

return Script
