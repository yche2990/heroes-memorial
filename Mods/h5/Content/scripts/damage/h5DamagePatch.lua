local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Damage rules of H5 Creatures and Magic (heroes-memorial.h5), appended to the patch of the engine's damage calculation:
---
---   H5_BLESS_H5C  Divine Strength: damage between "min + (max - min) x val%" and max (val = 50/65/80/100, 100 = always max)
---   H5_CURSE_H5C  Weakness: damage between min and "max - (max - min) x val%" (val = 50/65/80/100, 100 = always min)
---                 When both are present they cancel out and the full range applies. The engine's own ALWAYS_MAXIMUM/MINIMUM_DAMAGE still apply.
---   H5_PRECISE_SHOT_H5C  Precise Shot: shots at targets fewer than val hexes away ignore the target's Defense
---   H5_PIERCING_H5C      Force Arrow: shots ignore val% of the target's Defense (no effect on targets with Unbreakable Armor)
---   H5_ARMORED_H5C       Unbreakable Armor: the attacker's "ignore Defense" (ENEMY_DEFENCE_REDUCTION) has no effect on it
---   H5_SLEEP_H5C         Sleep: the stack that put it to sleep deals maximum damage to it (by the one in stacking group h5Sleep, val = stack id + 1)
---   H5_LEAP_H5C          Leap (Horned Grunt, put on it by spells/h5AbMove until the end of this round's exchange):
---                        stacking group h5LeapTarget = id of the enemy leapt at + 1; the grunt's melee hits on it deal +h5LeapBoost% damage,
---                        its hits on the grunt (i.e. retaliation) deal +h5LeapBack% damage (triple retaliation = +200%). Hits on other stacks do not count

local BLESS = "H5_BLESS_H5C"
local CURSE = "H5_CURSE_H5C"
local PRECISE = "H5_PRECISE_SHOT_H5C"
local PIERCING = "H5_PIERCING_H5C"
local ARMORED = "H5_ARMORED_H5C"
local SLEEP = "H5_SLEEP_H5C"
local LEAP = "H5_LEAP_H5C"

local function hexDistance(a, b)
	local y1, y2 = a:getY(), b:getY()
	local x1 = a:getX() + math.floor(y1 / 2)
	local x2 = b:getX() + math.floor(y2 / 2)
	local dx, dy = x2 - x1, y2 - y1
	if (dx >= 0 and dy >= 0) or (dx < 0 and dy < 0) then
		return math.max(math.abs(dx), math.abs(dy))
	end
	return math.abs(dx) + math.abs(dy)
end

function Script:getBaseDamageBlessCurse(info)
	local minDamage, maxDamage = Base.getBaseDamageBlessCurse(self, info)

	if self:hasBonusOfType(info.defenderBonuses, SLEEP) then
		local want = info.attacker:unitID() + 1
		local marks = info.defender:getBonuses({ type = SLEEP })
		for i = 1, marks:size() do
			local b = marks:getBonus(i)
			if b:getStacking() == "h5Sleep" and b:getVal() == want then
				return maxDamage, maxDamage
			end
		end
	end

	local blessed = self:hasBonusOfType(info.attackerBonuses, BLESS)
	local cursed = self:hasBonusOfType(info.attackerBonuses, CURSE)
	if blessed == cursed then return minDamage, maxDamage end

	local span = maxDamage - minDamage
	if blessed then
		local t = math.max(0, math.min(100, info.attacker:getBonusesValue({ type = BLESS })))
		return minDamage + math.floor(span * t / 100 + 0.5), maxDamage
	end

	local t = math.max(0, math.min(100, info.attacker:getBonusesValue({ type = CURSE })))
	return minDamage, maxDamage - math.floor(span * t / 100 + 0.5)
end

function Script:getDefenseIgnored(info, reducer, present, defense)
	if present == info.attackerBonuses and self:hasBonusOfType(info.defenderBonuses, ARMORED) then
		return 0
	end
	return Base.getDefenseIgnored(self, info, reducer, present, defense)
end

function Script:getDefense(info)
	local defense = Base.getDefense(self, info)
	if not info.shooting or defense <= 0 then return defense end

	if self:hasBonusOfType(info.attackerBonuses, PRECISE) then
		local range = info.attacker:getBonusesValue({ type = PRECISE })
		local a = info.attackerHex or info.attacker:getPosition()
		local d = info.defenderHex or info.defender:getPosition()
		if a and d and hexDistance(a, d) < range then return 0 end   -- Original "fewer than 3 hexes" (audit A-12)
	end

	if self:hasBonusOfType(info.attackerBonuses, PIERCING) and not self:hasBonusOfType(info.defenderBonuses, ARMORED) then
		local pct = math.max(0, math.min(100, info.attacker:getBonusesValue({ type = PIERCING })))
		defense = defense - math.floor(defense * pct / 100)
	end

	return defense
end

--- Leap mark: returns id of the enemy leapt at + 1, bonus % for hitting it, bonus % for its retaliation
local function leapMarks(unit)
	local target, boost, back = 0, 0, 0
	local marks = unit:getBonuses({ type = LEAP })
	for i = 1, marks:size() do
		local b = marks:getBonus(i)
		local s = b:getStacking()
		if s == "h5LeapTarget" then target = b:getVal()
		elseif s == "h5LeapBoost" then boost = b:getVal()
		elseif s == "h5LeapBack" then back = b:getVal() end
	end
	return target, boost, back
end

function Script:getH5LeapFactor(info)
	if info.shooting then return 0 end
	if self:hasBonusOfType(info.attackerBonuses, LEAP) then
		local target, boost = leapMarks(info.attacker)
		if target == info.defender:unitID() + 1 then return boost / 100 end
	end
	if self:hasBonusOfType(info.defenderBonuses, LEAP) then
		local target, _, back = leapMarks(info.defender)
		if target == info.attacker:unitID() + 1 then return back / 100 end
	end
	return 0
end

Script:declareBonus(BLESS)
Script:declareBonus(CURSE)
Script:declareBonus(PRECISE)
Script:declareBonus(PIERCING)
Script:declareBonus(ARMORED)
Script:declareBonus(SLEEP)
Script:declareBonus(LEAP)
Script:addDamageFactor("getH5LeapFactor")

return Script
