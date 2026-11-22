local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Piercing Bolt (H6 Arbalester): cast on an enemy stack. The bolt flies from the shooter through the target all the way to the edge of the battlefield,
--- and every stack on the line (friend or foe, the shooter excepted) takes one normal shot's damage x pct%, with no counterattack.
--- status / statusTurns (round 352, Breeder Mother "Impale"): status spell and rounds applied to enemies hit.
--- logType / logIndex: which battle log line to use (default: Piercing Bolt's).
--- Parameters: pct (default 100), status, statusTurns, logType, logIndex, uses, key, animation, sound

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	if caster == nil then return false end
	return unit:isAlive() and not unit:isGhost() and not unit:isTurret() and mechanics:getBattle():isHostile(caster, unit)
end

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isShooter() then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
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

--- Stacks on the line (nearest first, once each)
function Script:victims(battle, caster, unit)
	local from, to = caster:getPosition(), unit:getPosition()
	local hexes = L.hexTable(battle)
	local seen, list = { [caster:unitID()] = true }, {}
	for k = 1, 40 do
		local idx = L.lineIndex(from, to, k)
		if idx == nil then break end
		local h = hexes[idx]
		local u = h and battle:getUnitByPos(h, true)
		if u ~= nil and not seen[u:unitID()] and u:isAlive() and not u:isGhost() and not u:isTurret() then
			seen[u:unitID()] = true
			list[#list + 1] = u
		end
	end
	if not seen[unit:unitID()] then table.insert(list, 1, unit) end
	return list
end

function Script:adjustAffectedHexes(mechanics, hexes, spellTarget)
	local caster = mechanics:getUnitCaster()
	local dest = spellTarget and spellTarget[1]
	if caster == nil or dest == nil or dest.unit == nil then return hexes end
	for _, u in ipairs(self:victims(mechanics:getBattle(), caster, dest.unit)) do
		local hs = u:getHexes()
		for i = 1, hs:size() do hexes:insert(hs:at(i)) end
	end
	return hexes
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then return end
	local dest = target[1]
	if dest == nil or dest.unit == nil then return end
	local total, count = 0, 0
	for _, u in ipairs(self:victims(battle, caster, dest.unit)) do
		if u:isAlive() and not u:isInvincible() then
			local dmg = L.attackDamage(server, caster, u, self.pct or 100, true)
			local dealt = L.hit(server, battle, u, dmg, self.animation, self.sound)
			total = total + dealt
			count = count + 1
			if self.status and u:isAlive() and battle:isHostile(caster, u) then
				local sp = L.spell(self.status)
				if sp then server:applySpellEffects(battle, caster, sp, { u }, 3, self.statusTurns or 1, false) end
			end
		end
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.log(server, battle, self.logType or "H6_PIERCING_BOLT_H6C", self.logIndex or 1, { L.name(caster) }, { count, total })
	L.useCast(server, battle, caster, self.key or "h6PiercingBolt", self.uses)
end

return Script
