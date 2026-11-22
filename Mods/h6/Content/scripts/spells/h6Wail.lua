local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Wail of the Netherworld (H6 Spectre)
---
--- On a friendly undead stack (can be itself): every living enemy adjacent to it loses per x number of Spectres health,
--- and the target regains per x number of Spectres plus all the drained health (can resurrect, permanent).
--- Parameters: per, uses, key, animation (heal), drainAnimation (drained), sound, drainSound

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	if caster == nil or not unit:isAlive() or unit:isGhost() or unit:isTurret() then return false end
	if mechanics:getBattle():isHostile(caster, unit) then return false end
	return L.isUndead(unit)
end

function Script:applicableTarget(mechanics, problem, target)
	for _, dest in ipairs(target) do
		if dest.unit and self:isValidTarget(mechanics, dest.unit) then return true end
	end
	problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
	return false
end

function Script:applicableGeneral(mechanics, problem)
	local found = mechanics:getBattle():getUnitsIf(function(u) return self:isValidTarget(mechanics, u) end)
	if #found == 0 then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:filterTarget(mechanics, target)
	local out = {}
	for _, dest in ipairs(target) do
		if dest.unit and self:isValidTarget(mechanics, dest.unit) then out[#out + 1] = dest end
	end
	return out
end

function Script:getHealthChange(mechanics, spellTarget)
	local caster = mechanics:getUnitCaster()
	if caster == nil then return { hpDelta = 0, unitsDelta = 0 } end
	return { hpDelta = (self.per or 6) * caster:getCount(), unitsDelta = 0 }
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then return end
	local unit = target[1] and target[1].unit
	if unit == nil or not unit:isAlive() then return end
	local amount = (self.per or 6) * caster:getCount()
	local drained, n = 0, 0
	local victims = L.around(battle, unit, function(u) return battle:isHostile(caster, u) and L.isLiving(u) and not u:isInvincible() end)
	for _, v in ipairs(victims) do
		local d = L.hit(server, battle, v, math.min(amount, v:getAvailableHealth()), self.drainAnimation, self.drainSound)
		drained = drained + (d or 0); n = n + 1
	end
	if self.animation and server:describeChanges() then
		server:showBattleAnimation(battle, { { unit = unit } }, self.animation, self.sound or "", 1.0, true)
	end
	local amt, lvl = L.reviveHeal(unit, amount + drained)   -- Ring of Oblivion
	local healed, raised = server:healUnit(battle, unit, amt, lvl, ENUM.HealPower.permanent)
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.log(server, battle, "H6_WAIL_H6C", 1, { L.name(caster), L.name(unit) }, { n, drained, healed or 0, raised or 0 })
	L.useCast(server, battle, caster, self.key or "h6Wail", self.uses)
end

return Script
