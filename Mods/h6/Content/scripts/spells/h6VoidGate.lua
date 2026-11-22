local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Void Gate (H6 Void Avatar): opens a gate under an enemy stack for turns rounds, erasing 3% of its count at the start of each round (settled by combat/h6BossAvatar).
--- Parameters: turns, gate (only for the AI simulation estimate; added to the spell config and schema in review B11, 2026-11-08; must match gate of the boss creature h6BossAvatar,
--- the share actually erased each round is settled by combat/h6BossAvatar with its own parameters), key, animation, sound

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	return caster ~= nil and L.real(unit) and not unit:isInvincible() and mechanics:getBattle():isHostile(caster, unit)
		and not unit:hasBonuses({ type = "H6_VOIDGATE_H6C" })
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
	-- Round 419: reports proxy damage in the AI simulation (gate% of the count erased per round, for turns rounds)
	if Proxy.trial(server) then
		Proxy.damage(server, battle, main, main:getAvailableHealth() * (self.gate or 3) * (self.turns or 2) / 100)
		L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
		return
	end
	server:addUnitBonus(battle, main, { type = "H6_VOIDGATE_H6C", val = caster:unitID() + 1, duration = ENUM.BonusDuration.nTurns,
		turns = (self.turns or 2) + 1, sourceType = ENUM.BonusSource.other, sourceID = caster:getCreature():getJsonKey(), stacking = "h6VoidGate" }, true)
	L.show(server, battle, { main }, self.animation, self.sound)
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

--- 2026-11-07: the engine only gives spell effect scripts hexes as targets, so the stack on the hex is attached (see h6Lib.unitTarget)
function Script:transformTarget(mechanics, aimPoint, spellTarget) return L.unitTarget(mechanics, spellTarget) end

return Script
