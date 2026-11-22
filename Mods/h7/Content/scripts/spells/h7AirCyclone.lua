--- Cyclone (H7): all stacks in the area take Air damage (as h5Damage of heroes-memorial.h5: base + perPower x SP),
--- and survivors are swept to a random free hex within radius hexes of the casting center (H7 8x8 area; they stay where they are if there is no free hex).
--- Expert (H7 Understanding III): single-hex (small) stacks take double damage.
--- War machines and arrow towers are not moved.
--- Parameters:
---   base, perPower        4 numbers, by none/basic/advanced/expert
---   radius                range of relocation (at most this many hexes from the center)
---   smallDoubleFromLevel  mastery level from which single-hex stacks take double damage (3 = Expert)
local Base = require("heroes-memorial:spells/h5Damage")
local Lib = require("heroes-memorial:spells/h5SpellLib")
local Air = require("heroes-memorial.h7:spells/h7AirLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:damageForTarget(targetIndex, mechanics, unit)
	local dmg = Base.damageForTarget(self, targetIndex, mechanics, unit)
	local from = self.smallDoubleFromLevel or 99
	if Lib.level(mechanics) >= from and unit:getHexes():size() == 1 then
		dmg = dmg * 2
	end
	return dmg
end

local function freeHexes(battle, unit, center, radius)
	local out = {}
	local own = unit:getPosition()
	for _, h in ipairs(Air.hexesAround(center, radius)) do
		if h:isAvailable() and Air.key(h) ~= Air.key(own)
			and battle:getUnitByPos(h, true) == nil
			and battle:isAccessibleForUnit(unit, h) then
			out[#out + 1] = h
		end
	end
	return out
end

function Script:apply(mechanics, server, target)
	Base.apply(self, mechanics, server, target)

	local battle = mechanics:getBattle()
	local center = nil
	for _, dest in ipairs(target) do
		if dest.hex and dest.hex:isValid() then center = dest.hex break end
	end
	if center == nil then return end

	local moved = false
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit and unit:isAlive() and not unit:isGhost() and not Air.immovable(unit) then
			local free = freeHexes(battle, unit, center, self.radius or 4)
			if #free > 0 then
				local h = free[server:rngInt(1, #free)]
				server:moveUnit(battle, unit, h, true)
				moved = true
			end
		end
	end
	if moved then server:refreshBattleUnits(battle) end
end

function Script:describeTargetStep()
	return nil
end

return Script
