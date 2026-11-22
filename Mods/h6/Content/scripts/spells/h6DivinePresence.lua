local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Divine Presence (H6 Uriel): a friendly stack (alive or dead) is restored to full battle-start health (can resurrect, permanent), all negative spells are dispelled,
--- and it is immune to negative spells for the rest of the battle (cannot be dispelled). Parameters: key, animation, sound

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	if caster == nil or unit == nil or unit:isGhost() or mechanics:getBattle():isHostile(caster, unit) then return false end
	if unit:isTurret() or unit:hasBonuses({ type = "SIEGE_WEAPON" }) then return false end
	return unit:getAvailableHealth() < L.initialHealth(unit) or not unit:hasBonuses({ type = "H6_DIVINE_H6C" })
end
function Script:applicableGeneral(mechanics, problem)
	if #mechanics:getBattle():getUnitsIf(function(u) return self:isValidTarget(mechanics, u) end) == 0 then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget); return false
	end
	return true
end
function Script:applicableTarget(mechanics, problem, target)
	for _, dest in ipairs(target) do if dest.unit and self:isValidTarget(mechanics, dest.unit) then return true end end
	problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget); return false
end
function Script:filterTarget(mechanics, target)
	local out = {}
	for _, dest in ipairs(target) do if dest.unit and self:isValidTarget(mechanics, dest.unit) then out[#out + 1] = dest end end
	return out
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	local main = target[1] and target[1].unit
	if caster == nil or main == nil then return end
	local amt, lvl = L.reviveHeal(main, L.initialHealth(main))   -- Ring of Oblivion
	server:healUnit(battle, main, amt, lvl, ENUM.HealPower.permanent)
	local neg = main:getBonuses({ sourceType = ENUM.BonusSource.spellEffect }):filter(function(b)
		local sp = LIBRARY:getSpellByName(b:getSourceID())
		return sp ~= nil and sp:isNegative()
	end)
	if neg:size() > 0 then server:removeUnitBonuses(battle, main, neg) end
	if not main:hasBonuses({ type = "H6_DIVINE_H6C" }) then
		local src = caster:getCreature():getJsonKey()
		server:addUnitBonus(battle, main, { type = "NEGATIVE_EFFECTS_IMMUNITY", subtype = "spellSchool.any", val = 0, duration = ENUM.BonusDuration.oneBattle,
			sourceType = ENUM.BonusSource.other, sourceID = src, stacking = "h6Divine" }, true)
		server:addUnitBonus(battle, main, { type = "H6_DIVINE_H6C", val = 1, duration = ENUM.BonusDuration.oneBattle,
			sourceType = ENUM.BonusSource.other, sourceID = src, stacking = "h6Divine" }, true)
	end
	L.show(server, battle, { main }, self.animation, self.sound)
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

--- 2026-11-07: the engine only gives spell effect scripts hexes as targets, so the stack on the hex is attached (see h6Lib.unitTarget)
function Script:transformTarget(mechanics, aimPoint, spellTarget) return L.unitTarget(mechanics, spellTarget) end

return Script
