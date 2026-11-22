--- Mark of Chaos (H6 Memorial Sanctum, Inferno): before a marked stack is attacked, it gets a one-time vulnerability (GENERAL_DAMAGE_REDUCTION all -100,
--- i.e. +100% damage from this hit) and the attacker gets a temporary no-Luck bonus; both are removed after the hit and the remaining charges go down by 1; when used up the mark is removed.
--- Review B9 (2026-11-08): the +100% used to sit on the attacker (GENERAL_DAMAGE_PREMY), so with breath or sweep attacks hitting several targets in one blow,
--- unmarked stacks hit by the same blow took double damage too; it now sits on the marked target itself and only affects its share. No-Luck stays on the attacker (Luck is rolled once per blow).
local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script
local TAG = "h6MmChaosCrit"

local function left(u)
	local list = u:getBonuses({ type = "H6_MM_CHAOS_H6C" }):filter(function(b) return b:getStacking() == "h6MmChaos" end)
	if list:size() == 0 then return 0, list end
	return list:getBonus(1):getVal(), list
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	if other == nil or not unit:isAlive() or not battle:isHostile(unit, other) then return end
	if left(unit) <= 0 then return end
	L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_REDUCTION", TAG)
	L.removeByStacking(server, battle, other, "NO_LUCK", TAG)
	L.addBonus(server, battle, unit, { type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll", val = -100, hidden = true,
		duration = ENUM.BonusDuration.nTurns, turns = 1, stacking = TAG, sourceType = ENUM.BonusSource.other }, false)
	L.addBonus(server, battle, other, { type = "NO_LUCK", val = 0, hidden = true, duration = ENUM.BonusDuration.nTurns, turns = 1,
		stacking = TAG, sourceType = ENUM.BonusSource.other }, false)
	L.log(server, battle, "H6_MM_STATUS_H6C", 1, { L.name(unit) }, {})
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	local had = unit:getBonuses({ type = "GENERAL_DAMAGE_REDUCTION" }):filter(function(b) return b:getStacking() == TAG end):size() > 0
	L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_REDUCTION", TAG)
	if other ~= nil then L.removeByStacking(server, battle, other, "NO_LUCK", TAG) end
	if not had or not unit:isAlive() then return end
	local n = left(unit)
	L.removeByStacking(server, battle, unit, "H6_MM_CHAOS_H6C", "h6MmChaos")
	if n - 1 > 0 then
		server:addUnitBonus(battle, unit, { type = "H6_MM_CHAOS_H6C", val = n - 1, stacking = "h6MmChaos", duration = ENUM.BonusDuration.oneBattle,
			sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(), icon = "h6/abilities/mm_MarkOfChaos" }, true)
	else
		L.removeByStacking(server, battle, unit, "COMBAT_EVENT_TRIGGER", "h6MmChaos")
	end
end

return Script
