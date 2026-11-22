--- End of Feign Death (H6 Memorial Sanctum, Dungeon) (added to the battlefield by combat/h6MmFeignHit): at the start of each round, the fallen stack (ghost state, mark h6MmFeignDown)
--- is put back on its old hex (nearest free hex if blocked) and gets Speed +N until it acts (mark h6MmFeignSpeed). Written like the end of H7 Time Stasis.
---
--- Review C2 (2026-11-08): if all other stacks on its side die while it is down (only the feigning stack, off the field, is left), it gets up at once instead of waiting for the next round.
--- Otherwise its side has no stack that can act, while the engine still counts the ghost-state stack as alive and does not declare a loss, so the other side acts in vain until the round ends.
--- Trigger: "after each action" (onActionFinished): this bonus sits on the battlefield and every stack inherits it, so after any action (attacks, casts, counterattacks,
--- and script damage all happen within actions) the stacks involved check once; companions dying during the action (including those killed by Lua script damage) are caught.
--- Not onDeath: the engine only sends that event for deaths recorded by attacks and spells, not necessarily for kills by script damageUnit, and the attack is not finished when deaths are settled.
--- Companions killed by damage over time at round start are already put back by onRoundStart.
local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:landingHex(battle, unit, hexes, home)
	if home ~= nil and battle:isAccessibleForUnit(unit, home) and battle:getUnitByPos(home, true) == nil then return home end
	local best, bestD = nil, 1000
	for _, hex in pairs(hexes) do
		if hex:isAvailable() and battle:isAccessibleForUnit(unit, hex) and battle:getUnitByPos(hex, true) == nil then
			local d = home and L.hexDistance(hex, home) or 0
			if d < bestD then best, bestD = hex, d end
		end
	end
	return best
end

local function downUnits(battle)
	return battle:getUnitsIf(function(u) return u:isGhost() and u:isAlive() and L.markValue(u, "h6MmFeignDown") ~= nil end)
end

--- Number of stacks on unit's side still on the battlefield besides unit (same method as h6MmFeignHit: alive, not a ghost, not an arrow tower, not a war machine)
local function others(battle, unit)
	local side, id = unit:getSide(), unit:unitID()
	return #battle:getUnitsIf(function(u)
		return u:unitID() ~= id and u:getSide() == side and u:isAlive() and not u:isGhost() and not u:isTurret()
			and not u:hasBonuses({ type = "SIEGE_WEAPON" })
	end)
end

function Script:onRoundStart(server, battle, unit, other, payload)
	local down = downUnits(battle)
	if #down == 0 then return end
	self:standUp(server, battle, down)
end

--- Review C2: after each action, if the fallen stack's side has no other stack on the field, it gets up at once
function Script:onActionFinished(server, battle, unit, other, payload)
	local lonely = {}
	for _, u in ipairs(downUnits(battle)) do
		if others(battle, u) == 0 then lonely[#lonely + 1] = u end
	end
	if #lonely == 0 then return end
	self:standUp(server, battle, lonely)
end

function Script:standUp(server, battle, down)
	local hexes = L.hexTable(battle)
	for _, u in ipairs(down) do
		local idx = (L.markValue(u, "h6MmFeignDown") or 0) - 1
		local dest = self:landingHex(battle, u, hexes, hexes[idx])
		if dest == nil then dest = battle:getAvailableHex(u:getCreature(), u:getSide(), hexes[idx]) end
		if dest ~= nil and dest:isValid() then
			L.clearMark(server, battle, u, "h6MmFeignDown")
			L.removeByStacking(server, battle, u, "NO_RETALIATION", "h6MmFeignNoRet")
			local state = u:copy()
			state:setGhost(false)
			state:setPosition(dest)
			server:changeUnit(battle, state)
			if hexes[idx] == nil or L.hexIndex(dest) ~= idx then pcall(function() server:moveUnit(battle, u, dest, true) end) end
			local sp = L.markValue(u, "h6MmFeignSpeed") or 4
			L.clearMark(server, battle, u, "h6MmFeignSpeed")
			server:addUnitBonus(battle, u, { type = "STACKS_SPEED", val = sp, duration = ENUM.BonusDuration.stackGetsTurn, sourceType = ENUM.BonusSource.other,
				sourceID = u:getCreature():getJsonKey(), stacking = "h6MmFeignUp", hidden = true }, false)
			server:addUnitBonus(battle, u, { type = "H6_MM_FEIGNUP_H6C", val = sp, duration = ENUM.BonusDuration.stackGetsTurn, sourceType = ENUM.BonusSource.other,
				sourceID = u:getCreature():getJsonKey(), stacking = "h6MmFeignUp", icon = "h6/abilities/mm_FeignDeath" }, false)
			L.log(server, battle, "H6_MM_STATUS_H6C", 4, { L.name(u) }, {})
		end
	end
	server:refreshBattleUnits(battle)
end

return Script
