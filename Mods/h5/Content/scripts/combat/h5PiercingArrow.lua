local Base = require("combat/combatScript")
local H5 = require("combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Force Arrow (Arcane Archer)
---
--- Shots ignore ignore% of the target's Defense (damage rule see damage/h5DamagePatch, reading the hidden bonus H5_PIERCING_H5C on this stack);
--- after a shot hits, a chance is rolled with trigger factor pf; on success the target is knocked back one hex away from the shooter (pushed after the action; stacks holding ground or unable to move stay).
--- Parameters: ignore (percent of Defense ignored), pf (trigger factor of the knockback)

local function ensureMark(self, server, battle, unit)
	local want = self.ignore or 50
	if unit:getBonusesValue({ type = "H5_PIERCING_H5C" }) == want then return end
	H5.removeByStacking(server, battle, unit, "H5_PIERCING_H5C", "h5Piercing")
	server:addUnitBonus(battle, unit, {
		type = "H5_PIERCING_H5C", val = want,
		duration = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(),
		stacking = "h5Piercing", hidden = true
	}, false)
end

function Script:onBattleStart(server, battle, unit, other)
	ensureMark(self, server, battle, unit)
end

function Script:onBeforeAttack(server, battle, unit, other, payload)
	if payload.ranged then ensureMark(self, server, battle, unit) end
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() or not payload.ranged or payload.isCounter then return end
	local entry = H5.firstTarget(payload)
	if entry == nil or entry.unit == nil then return end
	local target = entry.unit
	if not target:isAlive() or target:isInvincible() or not battle:isHostile(unit, target) then return end
	if target:hasBonuses({ type = "SIEGE_WEAPON" }) or target:isTurret() then return end
	if (entry.damage or 0) <= 0 then return end
	local chance = H5.procChance(unit, target, self.pf or 2, entry.healthBeforeAttack)
	if not H5.roll(server, battle, unit, chance) then return end
	H5.setMark(server, battle, target, "h5PiercingPush", unit:unitID() + 1, 1)
end

function Script:onActionFinished(server, battle, unit, other, payload)
	if other == nil or other:unitID() ~= unit:unitID() then return end
	local victims = battle:getUnitsIf(function(o)
		return H5.markValue(o, "h5PiercingPush") == unit:unitID() + 1
	end)
	for _, v in ipairs(victims) do
		H5.clearMark(server, battle, v, "h5PiercingPush")
		if v:isAlive() and not v:isGhost() and not v:hasBonuses({ type = "H5_HOLD_GROUND_H5C" }) then
			local dest = H5.pushHex(battle, unit:getPosition(), v, 1)
			if dest ~= nil then
				server:moveUnit(battle, v, dest, true)
				server:refreshBattleUnits(battle)
				H5.log(server, battle, "core.bonus.H5_MARK_H5C.description.5", { H5.name(v) }, {})
			end
		end
	end
end

return Script
