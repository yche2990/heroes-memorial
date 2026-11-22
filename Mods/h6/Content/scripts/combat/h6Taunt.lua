local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Taunting Stance (H6 Brute)
---
--- Hidden battle-wide bonus (BATTLE_WIDE): when any stack attacks while an enemy with Taunt (H6_TAUNT_H6C) is within 2 hexes
--- and the attack is not aimed at one of these taunters, its damage is -val% (the engine cannot force a target, so damage reduction is used instead). Counterattacks do not count. Parameter: val

local TAG = "h6Taunted"

function Script:onBeforeAttack(server, battle, unit, other, payload)
	L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_PREMY", TAG)
	if other == nil or payload.isCounter or not unit:isAlive() then return end
	if other:hasBonuses({ type = "H6_TAUNT_H6C" }) and battle:isHostile(unit, other) then return end
	local taunters = battle:getUnitsIf(function(u)
		return u:isAlive() and not u:isGhost() and battle:isHostile(unit, u) and u:hasBonuses({ type = "H6_TAUNT_H6C" }) and L.unitDistance(unit, u) <= 2
	end)
	if #taunters == 0 then return end
	L.addBonus(server, battle, unit, { type = "GENERAL_DAMAGE_PREMY", val = -(self.val or 50), hidden = true,
		duration = ENUM.BonusDuration.nTurns, turns = 1, stacking = TAG }, false)
	L.log(server, battle, "H6_TAUNT_H6C", 1, { L.name(taunters[1]), L.name(unit) }, { self.val or 50 })
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_PREMY", TAG)
end

return Script
