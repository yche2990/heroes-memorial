local Base = require("spells/unitEffect")
local Lib = require("heroes-memorial:spells/h5SpellLib")
local C = require("heroes-memorial:combat/h5Common")
local BattleLog = require("battleLog")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Heal (H7): allies (the caster's stacks) are healed and resurrected (permanently), enemy undead take Light damage; no effect on constructs (non-living, mechanical, undead excepted).
--- Advanced (with Light Understanding I) 4x4 area (range in the spell json), friend and foe: allies in the area are healed, enemy undead damaged, the rest unaffected.
--- The spell json has smart = false; friend and foe are told apart here.
---
--- Parameters:
---   heal, healPer    healing = heal[mastery] + healPer[mastery] x Spell Power, plus the hero's spell bonus
---   dmg, dmgPer      damage to undead = dmg[mastery] + dmgPer[mastery] x Spell Power (average of the H7 random range), then the engine's spell damage adjustments
---   exclude          bonus types not affected (undead excepted)

local function has(u, t) return Lib.has(u, t) end

function Script:isFriend(mechanics, unit)
	return unit:getSide() == mechanics:getCasterSide()
end

function Script:construct(unit)
	if has(unit, "UNDEAD") then return false end
	for _, t in ipairs(self.exclude or { "NON_LIVING", "MECHANICAL", "SIEGE_WEAPON" }) do
		if has(unit, t) then return true end
	end
	return false
end

function Script:isValidTarget(mechanics, unit)
	if self:construct(unit) then return false end
	if self:isFriend(mechanics, unit) then
		if not unit:isValidTarget(true) then return false end
		if unit:getTotalHealth() <= unit:getAvailableHealth() then return false end
		if unit:isDead() then
			-- Cannot resurrect if another stack or an obstacle lies on the corpse
			local hexes = unit:getHexes()
			for i = 1, hexes:size() do
				local hex = hexes:at(i)
				local blockers = mechanics:getBattle():getUnitsIf(function(o)
					return o:unitID() ~= unit:unitID() and o:isValidTarget(false) and o:coversPos(hex)
				end)
				if #blockers > 0 then return false end
				if #mechanics:getBattle():getObstaclesOnPos(hex, true) > 0 then return false end
			end
		end
		return true
	end
	return unit:isValidTarget(false) and has(unit, "UNDEAD")
end

function Script:isReceptive(mechanics, unit)
	if self:isFriend(mechanics, unit) then
		return not unit:hasAbsoluteImmunity(mechanics:getSpell())
	end
	if unit:isInvincible() then return false end
	return mechanics:isReceptive(unit)
end

function Script:healAmount(mechanics, unit)
	local raw = Lib.value(self.heal, self.healPer, Lib.level(mechanics), Lib.power(mechanics))
	return mechanics:applySpellBonus(math.floor(raw), unit)
end

function Script:damageAmount(mechanics, unit)
	local raw = Lib.value(self.dmg, self.dmgPer, Lib.level(mechanics), Lib.power(mechanics)) * Lib.casterDamageFactor(mechanics)
	return Lib.adjust(mechanics, unit, raw)
end

function Script:getHealthChange(mechanics, spellTarget)
	local result = { hpDelta = 0, unitsDelta = 0 }
	for _, dest in ipairs(spellTarget) do
		local unit = dest.unit
		if unit and not self:isFriend(mechanics, unit) and unit:isAlive() then
			local copy = unit:copy()
			local hp, n = copy:getAvailableHealth(), copy:getCount()
			copy:damage(self:damageAmount(mechanics, unit))
			result.hpDelta = result.hpDelta - (hp - copy:getAvailableHealth())
			result.unitsDelta = result.unitsDelta - (n - copy:getCount())
		end
	end
	return result
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local describe = server:describeChanges()
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit then
			if self:isFriend(mechanics, unit) then
				local amount, level = C.reviveHeal(unit, self:healAmount(mechanics, unit))
				if amount > 0 then
					local _, raised = server:healUnit(battle, unit, amount, level, ENUM.HealPower.permanent)
					if raised and raised > 0 and describe then
						server:appendLog(battle, {
							append         = { raised == 1 and "core.genrltxt.117" or "core.genrltxt.116" },
							replaceStrings = { unit:getCreature():getNameTextID(raised) },
							replaceNumbers = { raised }
						})
					end
				end
			elseif unit:isAlive() then
				local dmg, killed = server:damageUnit(battle, unit, self:damageAmount(mechanics, unit))
				if describe and dmg > 0 then
					BattleLog.spellDamage(server, battle, mechanics:getSpell(), unit, dmg, killed)
				end
			end
		end
	end
end

--- Newer engines call this every time a target is chosen (logging an error if missing); returning nil uses the engine's default hint
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
