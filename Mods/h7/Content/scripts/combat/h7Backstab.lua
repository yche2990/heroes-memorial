local Base = require("combat/combatScript")
local L = require("combat/h7StatusLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Backstab (Assassin, Shadow)
---
--- VCMI has no facing, so it is rewritten per the design list: when its own melee attack (counterattacks excluded) targets an enemy already attacked this round by other friendly stacks
--- (attacks and counterattacks both count), this hit deals +val% damage (default 50).
--- Who attacked whom is recorded by the single battle-wide combat/h7StatusTick; targets with H7_VIGILANCE_H7C (Vigilance) are not affected.
--- Implementation: before attacking it gets a GENERAL_DAMAGE_PREMY (removed after this hit, kept at most 1 round).

local STACK = "h7Backstab"

local function vigilant(t, attacker)
	local ok, r = pcall(function() return t:hasBonuses({ type = "H7_VIGILANCE_H7C" }) end)
	if ok and r == true then return true end
	-- H7_NO_FLANK_H7C: 1 = cannot be flanked or attacked from behind; 2 = only cannot be flanked by large creatures (Nimble)
	local ok2, v = pcall(function() return t:getBonusesValue({ type = "H7_NO_FLANK_H7C" }) end)
	if not ok2 or v == nil or v <= 0 then return false end
	if v == 1 then return true end
	local ok3, wide = pcall(function() return attacker:getCreature():isDoubleWide() end)
	return ok3 and wide == true
end

function Script:onBattleStart(server, battle, unit, other, payload)
	L.ensureTracker(server, battle, unit)
end

function Script:onBeforeAttack(server, battle, unit, other, payload)
	L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_PREMY", STACK)
	if payload.ranged or payload.isCounter or not unit:isAlive() or other == nil then return end
	if not L.canHit(battle, unit, other) or vigilant(other, unit) then return end
	local by = L.markValue(other, L.hitKey(unit))
	if by == nil or by == unit:unitID() + 1 then return end
	server:addUnitBonus(battle, unit, {
		type = "GENERAL_DAMAGE_PREMY", val = self.val or 50, hidden = true,
		duration = ENUM.BonusDuration.nTurns + ENUM.BonusDuration.untilAttack, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(), stacking = STACK
	}, false)
	L.log(server, battle, 11, { L.name(unit), L.name(other) }, { self.val or 50 })
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_PREMY", STACK)
end

return Script
