local Base = require("heroes-memorial:spells/h5Damage")
local Lib = require("heroes-memorial:spells/h5SpellLib")
local L = require("combat/h7SfLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Soul Fire (H7): each enemy stack in the target area takes X x (1 + Y x number of friendly stacks in the area) damage (H7 template:
--- H7EffectSpecialDamageMultiplierPerTarget, "Y times extra for each ally"); the allies themselves take no damage.
--- X = base[mastery] + perPower[mastery] x Magic (as h5Damage, then the engine's Fire damage adjustments), Y = perAlly[mastery].
--- Formerly Prime: stacks with the H7 "Prime immunity" mark (H7_PRIMEIMMUNE_H7C) take only half damage.
--- The spell has smart:false so allies in the area also enter the target list (for counting); damage goes only to enemies.
--- Parameters: as h5Damage, plus perAlly (4 numbers)

function Script:isValidTarget(mechanics, unit)
	if not unit:isValidTarget(false) then return false end
	if unit:getSide() == mechanics:getCasterSide() then return true end
	return Base.isValidTarget(self, mechanics, unit)
end

function Script:isReceptive(mechanics, unit)
	if unit:getSide() == mechanics:getCasterSide() then return true end
	return Base.isReceptive(self, mechanics, unit)
end

local function split(mechanics, target)
	local allies, enemies = 0, {}
	for _, dest in ipairs(target) do
		local u = dest.unit
		if u and u:isAlive() then
			if u:getSide() == mechanics:getCasterSide() then
				if not u:isTurret() then allies = allies + 1 end
			else
				enemies[#enemies + 1] = u
			end
		end
	end
	return allies, enemies
end

function Script:factor(mechanics, allies)
	local lvl = Lib.level(mechanics)
	local y = self.perAlly and (self.perAlly[lvl + 1] or self.perAlly[#self.perAlly]) or 0
	return 1 + y * allies
end

function Script:amount(mechanics, unit, mult)
	local dmg = math.floor(Base.damageForTarget(self, 0, mechanics, unit) * mult)
	-- The 50% reduction of Prime immunity is applied once in the base damage by the MORE_DAMAGE_FROM_SPELL -50 that comes with H7_PRIME_IMMUNITY_H7C (review R2: the mark name checked here did not exist, so it was removed to avoid halving twice later)
	return math.max(dmg, 0)
end

function Script:getHealthChange(mechanics, spellTarget)
	local result = { hpDelta = 0, unitsDelta = 0 }
	local allies, enemies = split(mechanics, spellTarget)
	local mult = self:factor(mechanics, allies)
	for _, unit in ipairs(enemies) do
		local copy = unit:copy()
		local hp, cnt = copy:getAvailableHealth(), copy:getCount()
		copy:damage(self:amount(mechanics, unit, mult))
		result.hpDelta = result.hpDelta - (hp - copy:getAvailableHealth())
		result.unitsDelta = result.unitsDelta - (cnt - copy:getCount())
	end
	return result
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local allies, enemies = split(mechanics, target)
	local mult = self:factor(mechanics, allies)
	local describe = server:describeChanges()
	local first, total, kills, multiple = nil, 0, 0, false
	for _, unit in ipairs(enemies) do
		if unit:isAlive() then
			local amount = self:amount(mechanics, unit, mult)
			if amount > 0 then
				local dmg, killed = server:damageUnit(battle, unit, amount)
				if describe then
					if first then multiple = true else first = unit end
					total = total + dmg
					kills = kills + killed
				end
			end
		end
	end
	if describe and first and total > 0 then
		self:describeEffect(server, battle, mechanics, first, kills, total, multiple)
	end
end

--- Round 301: newer engines call this every time a target is chosen; returning nil uses the engine's default hint
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
