local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Death Spin (H6 Blade Dancer)
---
--- Cast on an enemy stack: the blade ring flies along the line from the caster to the target, and every stack on the way and on the target hex (friend or foe, the caster excepted)
--- takes one shot's damage (pct%, H3 formula, no counterattack; no extra scaling by the shooter's distance or wall rules).
--- Parameters: pct, key, animation, sound

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	if caster == nil or not L.real(unit) or unit:isInvincible() then return false end
	return mechanics:getBattle():isHostile(caster, unit)
end

function Script:applicableTarget(mechanics, problem, target)
	for _, dest in ipairs(target) do
		if dest.unit and self:isValidTarget(mechanics, dest.unit) then return true end
	end
	problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
	return false
end

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
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

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	local main = target[1] and target[1].unit
	if caster == nil or not caster:isAlive() or main == nil then return end
	local a, b = caster:getPosition(), main:getPosition()
	local n = L.hexDistance(a, b)
	local seen, list = {}, {}
	local hexes = L.hexTable(battle)
	for k = 1, n do
		local idx = L.lineIndex(a, b, k)
		local h = idx and hexes[idx]
		if h then
			for _, u in ipairs(battle:getUnitsIf(function(u) return L.real(u) and u:coversPos(h) end)) do
				if u:unitID() ~= caster:unitID() and not seen[u:unitID()] and not u:isInvincible() then
					seen[u:unitID()] = true; list[#list + 1] = u
				end
			end
		end
	end
	if not seen[main:unitID()] then list[#list + 1] = main end
	local total = 0
	for _, u in ipairs(list) do
		if u:isAlive() then
			total = total + (L.hit(server, battle, u, L.attackDamage(server, caster, u, self.pct or 100, true), self.animation, self.sound) or 0)
		end
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.log(server, battle, "H6_AREA_H6C", 5, { L.name(caster) }, { #list, total })
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

return Script
