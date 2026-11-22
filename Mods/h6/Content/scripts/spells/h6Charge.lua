local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Savage Charge (H6 Mauler, Brute)
---
--- Choose a hex (straight-line distance within its Speed, where it fits): it charges along the straight line, and every enemy it passes takes
--- pct% of a normal attack as damage (H3 formula, no counterattack), then it stops on that hex. The original "knocks small creatures aside" is not done.
--- Parameters: pct, animation, sound

local function pathUnits(battle, caster, dest)
	local start = caster:getPosition()
	local hexes = L.hexTable(battle)
	local n = L.hexDistance(start, dest)
	local seen, out = {}, {}
	for k = 1, n do
		local idx = L.lineIndex(start, dest, k)
		local h = idx and hexes[idx]
		if h then
			local list = battle:getUnitsIf(function(u) return L.real(u) and u:coversPos(h) end)
			for _, u in ipairs(list) do
				if not seen[u:unitID()] and battle:isHostile(caster, u) then seen[u:unitID()] = true; out[#out + 1] = u end
			end
		end
	end
	return out
end

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:applicableTarget(mechanics, problem, target)
	local caster = mechanics:getUnitCaster()
	local dest = target[1] and target[1].hex
	local battle = mechanics:getBattle()
	if caster == nil or dest == nil or not dest:isValid() or not dest:isAvailable() then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
		return false
	end
	local d = L.hexDistance(caster:getPosition(), dest)
	if d < 1 or d > caster:getBonusesValue({ type = "STACKS_SPEED" }) then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
		return false
	end
	if not battle:isAccessibleForUnit(caster, dest) then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
		return false
	end
	return true
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	local dest = target[1] and target[1].hex
	if caster == nil or not caster:isAlive() or dest == nil then return end
	local victims = pathUnits(battle, caster, dest)
	server:moveUnit(battle, caster, dest, true)
	local total = 0
	for _, u in ipairs(victims) do
		if u:isAlive() then
			total = total + (L.hit(server, battle, u, L.attackDamage(server, caster, u, self.pct or 100, false), self.animation, self.sound) or 0)
		end
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.log(server, battle, "H6_CHARGE_H6C", 1, { L.name(caster) }, { #victims, total })
end

return Script
