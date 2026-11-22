local Base = require("combat/combatScript")
local L = require("combat/h7StatusLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Corroding Venom (Manticore)
---
--- The main target hit by its own attack (counterattacks excluded) gets Defense -val until the end of its next action. Repeated hits only refresh, no stacking.
--- Parameter: val (Defense reduction, already scaled to the Manticore's level)

function Script:onBattleStart(server, battle, unit, other, payload)
	L.ensureTracker(server, battle, unit)
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.isCounter or not unit:isAlive() or other == nil then return end
	local entry = self:ownEntry(other, payload)
	if entry == nil or (entry.damage or 0) <= 0 or not L.canHit(battle, unit, other) then return end
	local t = other
	local v = self.val or 15
	local turns = L.turnsFor(t, 1, false)
	local src = unit:getCreature():getJsonKey()
	L.removeByStacking(server, battle, t, "PRIMARY_SKILL", "h7CorrodingVenom")
	server:addUnitBonus(battle, t, {
		type = "PRIMARY_SKILL", subtype = "primarySkill.defence", val = -v, hidden = true,
		duration = ENUM.BonusDuration.nTurns, turns = turns,
		sourceType = ENUM.BonusSource.other, sourceID = src, stacking = "h7CorrodingVenom"
	}, false)
	L.setShow(server, battle, t, "H7_CORRODE_H7C", v, turns, "h7CorrodingVenom", src)
	server:showBattleAnimation(battle, { { unit = t } }, "h7/fx/h7Corroding", "", 1.0, true)
	server:refreshBattleUnits(battle)
end

return Script
