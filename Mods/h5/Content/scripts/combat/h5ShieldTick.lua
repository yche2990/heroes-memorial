local Base = require("combat/combatScript")
local Proxy = require("lib/kadAiProxy")   -- Round 344: precise bonus removal (mark-fix)
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Celestial Shield (put on by the spell h5CelestialShield): damage from attacks is reduced by reduce%,
--- the shield vanishes once the damage blocked adds up to val (shield capacity).
--- Parameters: reduce (percent); val = capacity (computed from SP at cast time).
--- The amount used is kept on the hidden bonus H5_SHIELD_USED_H5C (this battle).

local USED = "H5_SHIELD_USED_H5C"
local TAG = "h5CelestialShieldCut"

-- Round 375: other full damage reductions on the target from non-spell sources (the engine adds such reductions before settling) are deducted when working out the temporary reduction, as in h5Taunt
local function otherReduction(unit, tag)
	local v = unit:getBonuses({ type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll" }):filter(function(b)
		return b:getSource() ~= ENUM.BonusSource.spellEffect and b:getStacking() ~= tag
	end):totalValue()
	return math.max(0, math.min(99, v))
end

local function ownCuts(unit)
	return unit:getBonuses({ type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll", sourceType = ENUM.BonusSource.other }):filter(function(b)
		return b:getStacking() == TAG
	end)
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local old = ownCuts(unit)
	-- Round 344: precise removal (the engine ignores the stacking group when removing and would also remove other bonuses of the same type, source and value)
	if old:size() > 0 then Proxy.removeExact(server, battle, unit, old) end
	server:addUnitBonus(battle, unit, {
		type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll", val = self.reduce or 25,
		duration = ENUM.BonusDuration.nTurns, turns = 1, sourceType = ENUM.BonusSource.other,
		sourceID = unit:getCreature():getJsonKey(), stacking = TAG, hidden = true
	}, true)
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	local cuts = ownCuts(unit)
	if cuts:size() == 0 then return end
	-- Round 344: precise removal (the engine ignores the stacking group when removing and would also remove other bonuses of the same type, source and value)
	Proxy.removeExact(server, battle, unit, cuts)
	if not unit:isAlive() then return end
	local entry = self:ownEntry(unit, payload)
	local dealt = entry and entry.damage or 0
	local r = self.reduce or 25
	if r >= 100 then return end
	local denom = 100 - otherReduction(unit, TAG) - r   -- Round 375: was 100 - r (the target's existing reduction was not deducted, so the shield was used up too slowly)
	if denom <= 0 then denom = 1 end
	local absorbed = math.floor(dealt * r / denom)
	if absorbed <= 0 then return end
	local used = unit:getBonusesValue({ type = USED }) + absorbed
	server:removeUnitBonuses(battle, unit, unit:getBonuses({ type = USED }))
	if used >= (self.val or 0) then
		-- Capacity used up: remove the shield (combat event bonus with spell source)
		local shield = unit:getBonuses({ type = "COMBAT_EVENT_TRIGGER", sourceType = ENUM.BonusSource.spellEffect }):filter(function(b)
			return b:getSourceID() == "heroes-memorial.h5:h5CelestialShield" or b:getSourceID() == "h5CelestialShield"
		end)
		if shield:size() > 0 then server:removeUnitBonuses(battle, unit, shield) end
		return
	end
	server:addUnitBonus(battle, unit, {
		type = USED, val = used, duration = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(), hidden = true
	}, false)
end

return Script
