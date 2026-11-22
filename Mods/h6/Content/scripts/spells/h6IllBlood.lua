local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Ill Blood (H6 Azkaal, Arebon): cast on an enemy stack. It immediately strikes an adjacent stack for pct% of its normal attack
--- (its own allies first, no counterattack) and loses its action this round. Parameters: pct, key, animation, sound

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	if caster == nil or not L.real(unit) or unit:isInvincible() then return false end
	if not mechanics:getBattle():isHostile(caster, unit) then return false end
	return #L.around(mechanics:getBattle(), unit, function(u) return u:unitID() ~= caster:unitID() end) > 0
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
	if caster == nil or main == nil or not main:isAlive() then return end
	local near = L.around(battle, main, function(u) return u:unitID() ~= caster:unitID() end)
	local victim = nil
	for _, u in ipairs(near) do if not battle:isHostile(main, u) then victim = u; break end end
	victim = victim or near[1]
	if victim then
		local dealt = L.hit(server, battle, victim, L.attackDamage(server, main, victim, self.pct or 105, false), self.animation, self.sound) or 0
		L.log(server, battle, "H6_ILLBLOOD_H6C", 1, { L.name(main), L.name(victim) }, { dealt })
	end
	if main:isAlive() then
		server:addUnitBonus(battle, main, { type = "NOT_ACTIVE", val = 0, duration = ENUM.BonusDuration.nTurns, turns = 1,
			sourceType = ENUM.BonusSource.other, sourceID = caster:getCreature():getJsonKey(), stacking = "h6IllBlood" }, true)
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

--- 2026-11-07: the engine only gives spell effect scripts hexes as targets, so the stack on the hex is attached (see h6Lib.unitTarget)
function Script:transformTarget(mechanics, aimPoint, spellTarget) return L.unitTarget(mechanics, spellTarget) end

return Script
