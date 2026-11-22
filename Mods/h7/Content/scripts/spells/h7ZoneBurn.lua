local Base = require("spells/damage")
local BattleLog = require("battleLog")
local L = require("combat/h7dLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Trigger spell h7AbMagmaBurn of the H7 Magma Pool: cast by the engine when a stack walks into the pool's hexes (or acts while standing in the pool).
--- Damage = the obstacle's minimalDamage (at cast time = stack size x per), with resistance and immunity through the spell damage flow (as the engine's core damage).
--- Each stack takes it at most once per round (hidden mark H7_ZONE_HIT_H7C, stacking = mark, until the start of the next round),
--- and the round-start damage (combat/h7ZoneTick) records the same mark.
--- Parameters: mark (stacking name), enemiesOnly (true: only enemies of the casting side), logIndex (battle log index)

local HIT = "H7_ZONE_HIT_H7C"

function Script:describeTargetStep(mechanics, target)
	return nil
end

function Script:isReceptive(mechanics, unit)
	if self.enemiesOnly and unit:getSide() == mechanics:getCasterSide() then return false end
	if unit:isInvincible() then return false end
	return Base.isReceptive(self, mechanics, unit)
end

--- Round 403: resistance now applies to triggered damage. The trigger spell is cast by the engine's obstacle caster (ObstacleCasterProxy), which raises the damage after resistance
--- back to the obstacle's minimalDamage (the Fire Wall rule), so the Magma Elemental's own "Fire damage halved" and the Golem's spell reduction did not work against
--- walking into the pool (the round-start share in h7ZoneTick uses spell:adjustDamage and was always right).
--- Here the resistance factor is computed in the engine's order (school reduction, all-spell reduction, vulnerability to this spell); when the engine value has been raised back to minimalDamage
--- minimalDamage x factor is used instead; when the engine value is above minimalDamage (larger hero bonus), resistance was already applied and it is kept.
--- spell:adjustDamage is not used: the AI calls this on its imaginary battlefield when estimating obstacle damage, and queries on the enemy hero's side would fail.
local function resistFactor(mechanics, unit)
	local spell = mechanics:getSpell()
	local f = 1
	local ok = pcall(function()
		local reductions = unit:getBonuses({ type = "SPELL_DAMAGE_REDUCTION" })
		for _, school in ipairs(spell:getSchools()) do
			local matching = reductions:filter(function(b)
				local sub = b:getSubtype()
				if sub == "any" then return false end
				return LIBRARY:getSpellSchoolByName(sub) == school
			end)
			if matching:size() > 0 then
				f = f * (100 - matching:totalValue()) / 100
				break
			end
		end
		if spell:isMagical() then
			local any = reductions:filter(function(b) return b:getSubtype() == "any" end)
			if any:size() > 0 then f = f * (100 - any:totalValue()) / 100 end
		end
		local more = unit:getBonuses({ type = "MORE_DAMAGE_FROM_SPELL" }):filter(function(b)
			local sub = b:getSubtype()
			return sub == spell:getJsonKey() or sub == L.shortKey(spell:getJsonKey())
		end)
		if more:size() > 0 then f = f * (100 + more:totalValue()) / 100 end
	end)
	if not ok then return 1 end
	return math.max(0, f)
end

function Script:damageForTarget(targetIndex, mechanics, unit)
	local amount = Base.damageForTarget(self, targetIndex, mechanics, unit)
	local floor = mechanics:getEffectValue()
	if amount > floor then return amount end
	return math.min(amount, math.floor(floor * resistFactor(mechanics, unit)))
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local mark = self.mark or "h7ZoneHit"
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit and unit:isAlive() and not unit:isInvincible()
			and not (self.enemiesOnly and unit:getSide() == mechanics:getCasterSide())
			and L.findMark(unit, HIT, mark) == nil then
			local amount = self:damageForTarget(0, mechanics, unit)
			if amount > 0 then
				local dmg, killed = server:damageUnit(battle, unit, amount)
				if unit:isAlive() then L.setMark(server, battle, unit, HIT, 1, 1, mark, true) end
				if server:describeChanges() then
					BattleLog.creaturesPerish(server, battle, unit, killed)
					L.log(server, battle, self.logIndex or 8, { L.name(unit) }, { dmg })
				end
			end
		end
	end
end

return Script
