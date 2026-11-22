local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Riptide (H6 Enraged Kirin): marks ripples under an enemy stack; at the start of the next round a water column erupts on that hex (settled by combat/h6BossKirin).
--- The target can dodge by moving away. Parameters: key, damage (only for the AI simulation estimate; added to the spell config and schema in review B11, 2026-11-08;
--- must match per of the boss creature h6BossKirin, the actual water column damage is settled by combat/h6BossKirin with its own parameters), animation, sound

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	return caster ~= nil and L.real(unit) and not unit:isInvincible() and mechanics:getBattle():isHostile(caster, unit)
end
function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	if caster == nil or L.markValue(caster, "h6Riptide") or #mechanics:getBattle():getUnitsIf(function(u) return self:isValidTarget(mechanics, u) end) == 0 then
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
	-- Round 419: reports proxy damage in the AI simulation (water column next round, the target may move away, counted at 70%)
	if Proxy.trial(server) then
		Proxy.damage(server, battle, main, (self.damage or 350) * (100 - L.schoolReduction(main, "water")) / 100 * 0.7, { school = "water" })
		L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
		return
	end
	L.setMark(server, battle, caster, "h6Riptide", L.hexIndex(main:getPosition()) + 1, 2)
	L.show(server, battle, { main }, self.animation, self.sound)
	L.log(server, battle, "H6_RIPTIDE_H6C", 2, { L.name(main) }, {})
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

--- 2026-11-07: the engine only gives spell effect scripts hexes as targets, so the stack on the hex is attached (see h6Lib.unitTarget)
function Script:transformTarget(mechanics, aimPoint, spellTarget) return L.unitTarget(mechanics, spellTarget) end

return Script
