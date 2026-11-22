local Base = require("combat/combatScript")
local L = require("combat/h5B3Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Pristine Unicorn: Follower of Light
---
--- The unicorn (mark H5_BOND_OF_LIGHT_H5C) passes this script to all allies (BATTLE_WIDE + own side only, one per stacking group).
--- When the own hero or a stack casts Light magic on an ally (school name ending in lightSchool; damage magic and Teleport excepted),
--- every Pristine Unicorn on the field gets the same effect, at mastery level (original BondOfLight_MinDuplicatedEffectMastery = 3, Expert),
--- for the rounds this spell has left on the original target. Not duplicated if the unicorn was already a target of this cast.
--- Each cast is settled only once, by the first target.
---
--- Parameter: mastery


local function isLight(spell)
	for _, school in ipairs(spell:getSchools() or {}) do
		local k = school:getJsonKey()
		if string.sub(k, -11) == "lightSchool" then return true end
	end
	return false
end

local function remainingTurns(unit, spell)
	local k = spell:getJsonKey()
	local short = string.match(k, ":(.+)$") or k
	local best = 0
	local list = unit:getBonuses({ sourceType = ENUM.BonusSource.spellEffect })
	for i = 1, list:size() do
		local b = list:getBonus(i)
		local sid = tostring(b:getSourceID())
		if sid == k or (string.match(sid, ":(.+)$") or sid) == short then
			best = math.max(best, b:getTurnsRemain())
		end
	end
	return best
end

function Script:onSpellHit(server, battle, unit, other, payload)
	local spell = payload.spell
	if spell == nil or not spell:isPositive() or spell:isDamage() or not isLight(spell) then return end
	if string.find(string.lower(spell:getJsonKey()), "teleport", 1, true) then return end
	local targets = payload.targets or {}
	if targets[1] == nil or targets[1].unit == nil or targets[1].unit:unitID() ~= unit:unitID() then return end
	local side = unit:getSide()
	if other ~= nil and battle:isHostile(other, unit) then return end

	local inTargets = {}
	for _, e in ipairs(targets) do
		if e.unit then inTargets[e.unit:unitID()] = true end
	end
	local unicorns = battle:getUnitsIf(function(u)
		return u:isAlive() and not battle:isHostile(u, unit) and not inTargets[u:unitID()] and u:hasBonuses({ type = "H5_BOND_OF_LIGHT_H5C" })
	end)
	if #unicorns == 0 then return end

	local turns = remainingTurns(unit, spell)
	if turns <= 0 then turns = 3 end
	for _, u in ipairs(unicorns) do
		local caster = other or u
		server:applySpellEffects(battle, caster, spell, { u }, self.mastery or 3, turns, false)
		server:appendLog(battle, {
			append = { "core.bonus.H5_BOND_OF_LIGHT_H5C.description.900001" },
			replaceStrings = { u:getCreature():getNameTextID(u:getCount()), spell:getNameTextID() }
		})
	end
	server:refreshBattleUnits(battle)
end

return Script
