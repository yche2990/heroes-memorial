local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Evil Eye (H6 Fate Spinner, Fate Weaver)
---
--- The first stack to attack it this battle (melee or ranged; counterattacks do not count) takes per x number of Spinners Dark damage before striking
--- (scaled by Dark and all-spell reduction). So that the engine does not lose the attacker before the attack, it leaves at least 1 health.
--- Parameters: per, animation, sound

local USED = "h6GazeUsed"

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	if payload.isCounter or other == nil or not other:isAlive() or not unit:isAlive() then return end
	if not battle:isHostile(unit, other) or L.markValue(unit, USED) then return end
	L.setMark(server, battle, unit, USED, 1)
	local amount = math.floor((self.per or 20) * unit:getCount() * (100 - L.schoolReduction(other, "02darkSchool")) / 100)
	amount = math.min(amount, other:getAvailableHealth() - 1)
	if amount <= 0 then return end
	local dealt = L.hit(server, battle, other, amount, self.animation, self.sound)
	L.log(server, battle, "H6_GAZE_H6C", 1, { L.name(unit), L.name(other) }, { dealt or 0 })
end

return Script
