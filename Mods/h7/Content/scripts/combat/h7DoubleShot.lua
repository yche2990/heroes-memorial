local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Double Shot (Master Hunter)
---
--- If the first arrow of its own shot kills at least 1 creature of the target, it shoots a second arrow (the target may counterattack after the first one as usual).
--- How it works: when the first arrow finishes it gets ADDITIONAL_ATTACK +1 (until the end of this attack). The engine counts shots only after the first arrow and the counterattack,
--- so this applies to this shot and is removed by the engine afterwards; the second arrow uses ammunition and plays the animation as usual.
--- If the target has a ranged first strike, the first arrow comes after it, when the shots have already been counted, so no extra shot happens (rare, not handled).

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not payload.ranged or payload.isCounter or (payload.attackIndex or 0) ~= 0 then return end
	if not unit:isAlive() then return end
	local main = payload.targets and payload.targets[1]
	if main == nil or main.unit == nil or (main.killed or 0) < 1 then return end
	if not main.unit:isAlive() then return end
	server:addUnitBonus(battle, unit, {
		type = "ADDITIONAL_ATTACK", val = 1, hidden = true,
		duration = ENUM.BonusDuration.untilAfterAttackSequence,
		sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(),
		stacking = "h7DoubleShot"
	}, false)
end

return Script
