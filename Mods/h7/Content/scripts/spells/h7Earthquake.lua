--- Earthquake (H7): all non-flying stacks on the battlefield (friend or foe, arrow towers excluded) take base + perPower x Spell Power Earth damage (h5Damage formula and damage adjustment);
--- enemyFactor[mastery]: multiplied again by this factor for the casting side's enemies (Expert = Earth Understanding III: double for enemies).
--- In sieges each wall section, arrow tower, gate and keep that can still be attacked also takes wallDamage damage, doubled for already damaged ones (below the highest remaining durability).
local Base = require("spells/h5Damage")
local Lib = require("spells/h5SpellLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local WALL_PARTS = { 0, 1, 2, 3, 4, 5, 6, 7 }

function Script:isValidTarget(mechanics, unit)
	if not Base.isValidTarget(self, mechanics, unit) then return false end
	if unit:isTurret() then return false end
	if Lib.has(unit, "FLYING") then return false end
	return true
end

function Script:damageForTarget(targetIndex, mechanics, unit)
	local dmg = Base.damageForTarget(self, targetIndex, mechanics, unit)
	if self.enemyFactor and unit:getSide() ~= mechanics:getCasterSide() then
		local f = self.enemyFactor[Lib.level(mechanics) + 1] or 1
		dmg = math.floor(dmg * f)
	end
	return dmg
end

function Script:shakeWalls(mechanics, server)
	local battle = mechanics:getBattle()
	if not battle:hasFortifications() then return end
	local parts, top = {}, 0
	for _, p in ipairs(WALL_PARTS) do
		local ok, attackable = pcall(function() return battle:isWallPartAttackable(p) end)
		if ok and attackable then
			local hp = battle:getWallState(p)
			if hp and hp > 0 then
				parts[#parts + 1] = { part = p, hp = hp }
				if hp > top then top = hp end
			end
		end
	end
	local dmg = self.wallDamage or 1
	for _, w in ipairs(parts) do
		local d = (w.hp < top) and dmg * 2 or dmg
		server:catapultAttack(battle, nil, w.part, d)
	end
end

function Script:apply(mechanics, server, target)
	Base.apply(self, mechanics, server, target)
	if server:describeChanges() then
		self:shakeWalls(mechanics, server)
	end
end

function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
