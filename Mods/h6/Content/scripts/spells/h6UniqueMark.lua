local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Mind Probe (H6 Shadow Watcher), does not use its action
---
--- Cast on an enemy stack: all damage it takes afterwards +pct%, until the battle ends; a side can probe only one stack at a time,
--- and casting it on another enemy removes the effect from the previous one. Visible status H6_PROBED_H6C.
--- Parameters: pct, key, animation, sound

local TYPE = "H6_PROBED_H6C"

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	return caster ~= nil and L.real(unit) and not unit:isInvincible() and mechanics:getBattle():isHostile(caster, unit)
end

function Script:applicableTarget(mechanics, problem, target)
	for _, dest in ipairs(target) do
		if dest.unit and self:isValidTarget(mechanics, dest.unit) then return true end
	end
	problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
	return false
end

function Script:filterTarget(mechanics, target)
	local out = {}
	for _, dest in ipairs(target) do
		if dest.unit and self:isValidTarget(mechanics, dest.unit) then out[#out + 1] = dest end
	end
	return out
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	local main = target[1] and target[1].unit
	if caster == nil or main == nil then return end
	local tag = "h6Probe" .. tostring(caster:getSide())
	for _, u in ipairs(battle:getUnitsIf(function(u) return u:isAlive() end)) do
		L.removeByStacking(server, battle, u, TYPE, tag)
		L.removeByStacking(server, battle, u, "GENERAL_DAMAGE_REDUCTION", tag)
	end
	local src = caster:getCreature():getJsonKey()
	server:addUnitBonus(battle, main, { type = "GENERAL_DAMAGE_REDUCTION", val = -(self.pct or 15), duration = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.other, sourceID = src, stacking = tag, hidden = true }, true)
	server:addUnitBonus(battle, main, { type = TYPE, val = self.pct or 15, duration = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.other, sourceID = src, stacking = tag }, true)
	L.show(server, battle, { main }, self.animation, self.sound)
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

return Script
