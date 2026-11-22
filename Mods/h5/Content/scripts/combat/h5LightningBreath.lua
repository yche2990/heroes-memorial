local Base = require("combat/combatScript")
local Proxy = require("lib/kadAiProxy")   -- Round 344: precise bonus removal (mark-fix)
local A = require("heroes-memorial.h5:combat/h5Area")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Lightning Breath (H5 Lightning Wyvern)
--- On an active melee attack (not retaliation), the target and all enemies adjacent to it share the damage of this hit equally.
--- How: before attacking count N = (target + adjacent enemies) and give the target a temporary (1-1/N) damage reduction;
--- after attacking, deal the damage the target actually took to each adjacent enemy as well, then remove the reduction.

local TMP = "h5LightningBreathTmp"

-- Round 375: other full damage reductions on the target from non-spell sources (the engine adds such reductions before settling) are deducted when working out the temporary reduction, as in h5Taunt
local function otherReduction(unit, tag)
	local v = unit:getBonuses({ type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll" }):filter(function(b)
		return b:getSource() ~= ENUM.BonusSource.spellEffect and b:getStacking() ~= tag
	end):totalValue()
	return math.max(0, math.min(99, v))
end

local function others(battle, unit, target)
	local side = unit:getSide()
	return battle:getUnitsIf(function(u)
		return u:unitID() ~= target:unitID() and A.hostile(battle, unit, u) and A.damageable(u)
			and A.unitDistance(u, target) == 1
	end)
end

local function clearTmp(server, battle, target)
	local list = target:getBonuses({ type = "GENERAL_DAMAGE_REDUCTION" }):filter(function(b) return b:getStacking() == TMP end)
	-- Round 344: precise removal (the engine ignores the stacking group when removing and would also remove other bonuses of the same type, source and value)
	if list:size() > 0 then Proxy.removeExact(server, battle, target, list) end
end

function Script:onBeforeAttack(server, battle, unit, other, payload)
	if payload.ranged or payload.isCounter or (payload.attackIndex or 0) ~= 0 then return end
	local target = A.primary(payload, other)
	if target == nil or not target:isAlive() then return end
	local n = 1 + #others(battle, unit, target)
	if n <= 1 then return end
	clearTmp(server, battle, target)
	server:addUnitBonus(battle, target, {
		type       = "GENERAL_DAMAGE_REDUCTION",
		subtype    = "damageTypeAll",
		val        = math.floor((100 - otherReduction(target, TMP)) * (1 - 1 / n)),   -- Round 375: was 100 - 100 / n (the target's existing reduction was not deducted)
		duration   = ENUM.BonusDuration.nTurns,
		turns      = 1,
		sourceType = ENUM.BonusSource.other,
		sourceID   = unit:getCreature():getJsonKey(),
		stacking   = TMP,
		hidden     = true
	}, true)
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.ranged or payload.isCounter or (payload.attackIndex or 0) ~= 0 then return end
	local target, entry = A.primary(payload, other)
	if target == nil then return end
	clearTmp(server, battle, target)
	local damage = entry and entry.damage or 0
	if damage <= 0 then return end
	local list = others(battle, unit, target)
	table.sort(list, function(a, b) return a:unitID() < b:unitID() end)
	for _, v in ipairs(list) do
		if v:isAlive() then A.hit(server, battle, v, damage, "h5/fx/Spells_ChainLightningHit", "LIGHTBLT") end
	end
end

return Script
