--- Gust (H7): pushes the target away from the casting side (right when cast by the attacker, left when cast by the defender).
--- First a straight line (directly left/right) of at most straight[mastery] hexes is tried; if it cannot move even one hex straight, or a diagonal (up-right/down-right or up-left/down-left) gets further,
--- it goes diagonally instead, at most diagonal[mastery] hexes. It stops at stacks, obstacles, walls or the edge behind it. War machines and arrow towers cannot be pushed.
--- The extra damage at Expert is another h5Damage effect in the same spell.
--- Parameters:
---   straight, diagonal   4 numbers, by none/basic/advanced/expert
---   animRight, animLeft  animations played when pushing right / left
---   sound                sound
local Base = require("spells/unitEffect")
local Lib = require("heroes-memorial:spells/h5SpellLib")
local Air = require("heroes-memorial.h7:spells/h7AirLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local function pick(arr, lvl)
	if not arr then return 0 end
	return arr[lvl + 1] or arr[#arr] or 0
end

function Script:isValidTarget(mechanics, unit)
	if not Base.isValidTarget(self, mechanics, unit) then return false end
	return not Air.immovable(unit)
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local lvl = Lib.level(mechanics)
	local right = Air.sideNum(mechanics:getCasterSide()) == 0
	local straightDir = right and "copyToEast" or "copyToWest"
	local diag = right and { "copyToNorthEast", "copyToSouthEast" } or { "copyToNorthWest", "copyToSouthWest" }
	local nStraight, nDiag = pick(self.straight, lvl), pick(self.diagonal, lvl)
	local describe = server:describeChanges()
	local moved = false

	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit and unit:isAlive() and not Air.immovable(unit) then
			local bestPos, bestN = nil, 0
			if nStraight > 0 then
				local p, n = Air.slide(battle, unit, straightDir, nStraight)
				if n > 0 then bestPos, bestN = p, n end
			end
			if nDiag > 0 then
				for _, dir in ipairs(diag) do
					local p, n = Air.slide(battle, unit, dir, nDiag)
					if n > bestN then bestPos, bestN = p, n end
				end
			end
			if bestPos ~= nil then
				if describe then
					server:showBattleAnimation(battle, { { unit = unit } }, right and self.animRight or self.animLeft, self.sound or "", 1.0, true)
				end
				server:moveUnit(battle, unit, bestPos, true)
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
