local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Close heavy-strike active abilities (H6 Panther Warrior "Claw Frenzy", Cyclops "Smash", Wrathful Cyclops "Mighty Smash")
---
--- Cast on an adjacent enemy stack: it takes pct% of a normal attack as damage (H3 formula, no counterattack).
---   splash = "all": other stacks adjacent to the target (friend or foe, the caster excepted) take the same damage;
---   splash = "enemy": only enemies adjacent to the target count.
---   knockback: single-hex stacks hit are knocked back one hex along the direction from the caster to them (only if that hex is free).
---   knockDist: how many hexes to knock back (default 1); status / statusTurns: status spell (level 3) and rounds applied after a hit (round 351, Dungeon).
--- Parameters: pct, splash, knockback, knockDist, status, statusTurns, key, animation, sound

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	if caster == nil or not L.real(unit) or unit:isInvincible() then return false end
	return mechanics:getBattle():isHostile(caster, unit) and L.adjacent(caster, unit)
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

local function knock(server, battle, caster, u, dist)
	if not u:isAlive() or u:getHexes():size() ~= 1 then return end
	local a, b = caster:getPosition(), u:getPosition()
	local bd = 1000
	local ch = caster:getHexes()
	for i = 1, ch:size() do
		local d = L.hexDistance(ch:at(i), b)
		if d < bd then a, bd = ch:at(i), d end
	end
	-- Pushed back at most dist hexes along the direction from the caster to the target, stopping at the previous hex if one does not fit
	local dest = nil
	for k = 1, (dist or 1) do
		local idx = L.lineIndex(a, b, bd + k)
		local h = idx and L.hexTable(battle)[idx]
		if h and h:isAvailable() and battle:isAccessibleForUnit(u, h) then dest = h else break end
	end
	if dest then server:moveUnit(battle, u, dest, true) end
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	local main = target[1] and target[1].unit
	if caster == nil or not caster:isAlive() or main == nil then return end
	local list = { main }
	if self.splash then
		for _, u in ipairs(L.around(battle, main, function(u)
			if u:unitID() == caster:unitID() then return false end
			return self.splash == "all" or battle:isHostile(caster, u)
		end)) do list[#list + 1] = u end
	end
	local total = 0
	for _, u in ipairs(list) do
		if u:isAlive() then
			total = total + (L.hit(server, battle, u, L.attackDamage(server, caster, u, self.pct or 100, false), self.animation, self.sound) or 0)
			if self.knockback then knock(server, battle, caster, u, self.knockDist) end
			if self.status and u:isAlive() then
				local sp = L.spell(self.status)
				if sp then server:applySpellEffects(battle, caster, sp, { u }, 3, self.statusTurns or 2, false) end
			end
		end
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.log(server, battle, "H6_AREA_H6C", 5, { L.name(caster) }, { #list, total })
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

return Script
