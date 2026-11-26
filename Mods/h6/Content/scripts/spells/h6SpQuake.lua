--- Earthquake (H6): in a 4-column x 8-row area around the target, each wall section, the gate and the arrow towers take dmg damage (only when cast by the attacker in a siege); living stacks in the area are Dazed for 1 round.
--- Can also be cast outside sieges (Daze only). Parameters: dmg (4 numbers), status (status name), all (Doomsday: ignores the area, hits all walls, no Daze)
local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local S = require("lib/h6SpLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script
local PARTS = { ENUM.WallPart.upperTower, ENUM.WallPart.upperWall, ENUM.WallPart.overGate, ENUM.WallPart.gate,
                ENUM.WallPart.belowGate, ENUM.WallPart.bottomWall, ENUM.WallPart.bottomTower, ENUM.WallPart.keep }

local function inside(center, h)
	local dy = h:getY() - center:getY()
	local dx = h:getX() - center:getX()
	return dy >= -4 and dy <= 3 and dx >= -2 and dx <= 1
end

function Script:applicableGeneral(mechanics, problem) return true end
function Script:applicableTarget(mechanics, problem, target)
	if self.all then return true end
	local dest = target[1]
	if dest == nil or dest.hex == nil or not dest.hex:isValid() then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
		return false
	end
	return true
end

function Script:adjustAffectedHexes(mechanics, hexes, spellTarget)
	local dest = spellTarget[1]
	if dest and dest.hex and dest.hex:isValid() then
		for _, h in pairs(L.hexTable(mechanics:getBattle())) do if inside(dest.hex, h) then hexes:insert(h) end end
	end
	return hexes
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local dest = target[1]
	if not self.all and (dest == nil or dest.hex == nil) then return end
	local center = dest and dest.hex
	local dmg = S.pick(mechanics, self.dmg)
	if battle:hasFortifications() and mechanics:getCasterSide() == ENUM.BattleSide.attacker and dmg > 0 then
		for _, part in ipairs(PARTS) do
			if battle:isWallPartAttackable(part) then
				local h = battle:wallPartToBattleHex(part)
				if h and h:isValid() and (self.all or inside(center, h)) then server:catapultAttack(battle, nil, part, dmg) end
			end
		end
	end
	if not server:describeChanges() or self.all then return end
	local sp = self.status and LIBRARY:getSpellByName("kad-mechanics:" .. self.status) or nil
	if sp == nil then return end
	for _, u in ipairs(battle:getUnitsIf(function(x) return L.real(x) and L.isLiving(x) end)) do
		local hs, ok = u:getHexes(), false
		for i = 1, hs:size() do if inside(center, hs:at(i)) then ok = true; break end end
		if ok then
			local others = battle:getUnitsIf(function(x) return x:getSide() ~= u:getSide() and x:isAlive() and not x:isTurret() end)
			server:castSpell(battle, others[1] or u, sp, { u }, 0)
		end
	end
	server:refreshBattleUnits(battle)
end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
