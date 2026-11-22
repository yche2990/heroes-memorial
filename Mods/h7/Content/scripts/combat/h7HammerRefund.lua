local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Ammunition rule of H7 Hammer Throw (Fire Titan) (Yu's decision 2026-11-01): the Fire Titan has only 1 shot (the hammer);
--- if an actively thrown hammer kills no enemy, the shot is returned (a SHOTS +1 for this battle, without a stacking group, so it can accumulate).
--- Before each shot (active, not a counterattack) H7_HAMMER_ARMED_H7C is added (until the end of this attack): the creature's Attack +7, no range penalty
--- and hit effect (h7AbStrike fx) limited by this mark then only apply to the hammer throw, not to melee. The "prepare Hammer Throw" active ability is no longer needed.

local ARMED = "H7_HAMMER_ARMED_H7C"

function Script:onBeforeAttack(server, battle, unit, other, payload)
	if not payload.ranged or payload.isCounter or (payload.attackIndex or 0) ~= 0 then return end
	if not unit:isAlive() or unit:hasBonuses({ type = ARMED }) then return end
	server:addUnitBonus(battle, unit, {
		type = ARMED, val = 1, hidden = true, stacking = "h7HammerArmed",
		duration = ENUM.BonusDuration.untilAfterAttackSequence,
		sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey()
	}, false)
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not payload.ranged or payload.isCounter or (payload.attackIndex or 0) ~= 0 then return end
	if not unit:isAlive() then return end
	local killed = 0
	for _, t in ipairs(payload.targets or {}) do killed = killed + (t.killed or 0) end
	if killed > 0 then return end
	server:addUnitBonus(battle, unit, {
		type = "SHOTS", val = 1, hidden = true,
		duration = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey()
	}, false)
end

return Script
