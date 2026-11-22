local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Terrifying Presence (H6 Spectral Dragon, Shadow Dragon, Black Dragon), hidden battle-wide bonus
---
--- At the start of each round, stacks adjacent to an enemy carrying H6_TERROR_H6C: chance% (default 20) to be so scared they can only defend this round (skip their action),
--- otherwise Morale -morale (default 2), this round only. Stacks unaffected by Morale (undead, non-living, mechanical, fixed Morale) and mind-immune stacks are not affected.
--- Parameters: chance, morale, animation, sound

local function immune(u)
	-- Review B2 (2026-11-08): MECHANICAL added; the engine also treats it as unaffected by Morale
	return u:hasBonuses({ type = "UNDEAD" }) or u:hasBonuses({ type = "NON_LIVING" }) or u:hasBonuses({ type = "MECHANICAL" })
		or u:hasBonuses({ type = "NO_MORALE" })
		or u:hasBonuses({ type = "MIND_IMMUNITY" }) or u:hasBonuses({ type = "SIEGE_WEAPON" }) or u:isTurret()
end

function Script:onRoundStart(server, battle, unit)
	if not L.real(unit) or immune(unit) then return end
	local near = L.around(battle, unit, function(u) return battle:isHostile(unit, u) and u:hasBonuses({ type = "H6_TERROR_H6C" }) end)
	if #near == 0 then return end
	local src = near[1]:getCreature():getJsonKey()
	if server:rngInt(1, 100) <= L.chance(near[1], self.chance or 20) then   -- Divination (on the side causing the fear) raises the chance
		server:addUnitBonus(battle, unit, { type = "NOT_ACTIVE", val = 0, duration = ENUM.BonusDuration.stackGetsTurn + ENUM.BonusDuration.nTurns,
			turns = 1, sourceType = ENUM.BonusSource.other, sourceID = src, stacking = "h6Terror" }, true)
		server:addUnitBonus(battle, unit, { type = "H6_TERRIFIED_H6C", val = 1, duration = ENUM.BonusDuration.nTurns, turns = 1,
			sourceType = ENUM.BonusSource.other, sourceID = src, stacking = "h6Terror" }, true)
		L.log(server, battle, "H6_TERRIFIED_H6C", 1, { L.name(unit) }, {})
	else
		server:addUnitBonus(battle, unit, { type = "MORALE", val = -(self.morale or 2), duration = ENUM.BonusDuration.nTurns, turns = 1,
			sourceType = ENUM.BonusSource.other, sourceID = src, stacking = "h6Terror", hidden = true }, true)
		server:addUnitBonus(battle, unit, { type = "H6_TERRIFIED_H6C", val = 2, duration = ENUM.BonusDuration.nTurns, turns = 1,
			sourceType = ENUM.BonusSource.other, sourceID = src, stacking = "h6Terror" }, true)
	end
	L.show(server, battle, { unit }, self.animation, self.sound)
end

return Script
