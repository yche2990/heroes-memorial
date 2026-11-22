local Base = require("combat/combatScript")
local BattleLog = require("battleLog")
local C = require("combat/h5Common")
local A = require("combat/h5Area")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Pack Dive - landing (attached to the battlefield by spells/h5AbPackDive at takeoff). At the start of the next round (the stack with the lowest id handles all departed griffins):
--- all enemies in the landing row and the row below take pct% of a normal attack's damage (no retaliation), then the griffin is put back where it took off (nearest free hex if occupied).
--- Landing uses up this round's action (when other stacks can still act).
--- Parameters: mark, pct

function Script:onRoundStart(server, battle, unit, other)
	local airborne = battle:getUnitsIf(function(u)
		return u:isGhost() and u:isAlive() and u:hasBonuses({ type = self.mark })
	end)
	if #airborne == 0 then return end
	local hexes = C.hexTable(battle)

	for _, griffin in ipairs(airborne) do
		local marks = griffin:getBonuses({ type = self.mark })
		local v = marks:getBonus(1):getVal()
		server:removeUnitBonuses(battle, griffin, marks)
		local hex = hexes[v % 1000 - 1]
		local home = hexes[math.floor(v / 1000) - 1]
		local side = griffin:getSide()
		local name = griffin:getCreature():getNameTextID(griffin:getCount())

		if hex ~= nil then
			local y = hex:getY()
			local victims = battle:getUnitsIf(function(u)
				if not battle:isHostile(griffin, u) or not A.damageable(u) then return false end
				local hs = u:getHexes()
				for i = 1, hs:size() do
					local hy = hs:at(i):getY()
					if hy == y or hy == y + 1 then return true end
				end
				return false
			end)
			for _, victim in ipairs(victims) do
				local dmg = A.attackDamage(server, griffin, victim, self.pct or 75, false)
				server:showBattleAnimation(battle, { { unit = victim } }, "h5/fx/fx_diveStrike", "ERTHQUAK", 1.0, true)
				local dealt, killed = server:damageUnit(battle, victim, dmg)
				server:appendLog(battle, {
					append         = { "core.bonus." .. self.mark .. ".description.2" },
					replaceStrings = { name, victim:getCreature():getNameTextID(victim:getCount()) },
					replaceNumbers = { dealt }
				})
				BattleLog.creaturesPerish(server, battle, victim, killed)
			end
		end

		-- Original: returns to the takeoff spot after attacking (nearest free hex if occupied)
		local origin = home or hex
		local dest = nil
		if origin ~= nil then
			if battle:isAccessibleForUnit(griffin, origin) and battle:getUnitByPos(origin, true) == nil then
				dest = origin
			else
				local best, bestD = nil, 1000
				for _, h in pairs(hexes) do
					if h:isAvailable() and battle:getUnitByPos(h, true) == nil and battle:isAccessibleForUnit(griffin, h) then
						local d = C.hexDistance(h, origin)
						if d < bestD then best, bestD = h, d end
					end
				end
				dest = best
			end
		end
		if dest == nil then dest = battle:getAvailableHex(griffin:getCreature(), side, nil) end

		local state = griffin:copy()
		state:setGhost(false)
		state:setPosition(dest)
		local enemies = battle:getUnitsIf(function(u) return battle:isHostile(griffin, u) and u:isAlive() and not u:isGhost() and not u:isTurret() end)
		local others = battle:getUnitsIf(function(u)
			return u:unitID() ~= griffin:unitID() and u:isAlive() and not u:isGhost() and not u:hasBonuses({ type = "NOT_ACTIVE" })
		end)
		if #enemies > 0 and #others > 0 then state:setFear(true) end -- No more action this round (newer engines removed setMoved)
		server:changeUnit(battle, state)
		server:refreshBattleUnits(battle)
		server:showBattleAnimation(battle, { { unit = griffin } }, "h5/fx/fx_diveTakeoff", "TELPTIN", 1.0, true)
		server:refreshBattleUnits(battle)
	end
end

return Script
