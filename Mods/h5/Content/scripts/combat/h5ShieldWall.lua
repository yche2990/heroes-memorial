local Base = require("combat/combatScript")
local Proxy = require("lib/kadAiProxy")   -- Round 344: precise bonus removal (mark-fix)
local A = require("heroes-memorial.h5:combat/h5Area")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Shield Wall (H5 Shieldguard)
--- When an enemy attacks this stack in melee, the damage it takes is reduced by val% (default 10%) per hex the enemy moved this time, at most max% (default 90%).
--- No effect against fliers. The hexes walked by the attacker are recorded by the hidden area script h5AreaZone on all stacks.
--- Parameters: val, max

local TMP = "h5ShieldWallTmp"

local function clearTmp(server, battle, unit)
	local list = unit:getBonuses({ type = "GENERAL_DAMAGE_REDUCTION" }):filter(function(b) return b:getStacking() == TMP end)
	-- Round 344: precise removal (the engine ignores the stacking group when removing and would also remove other bonuses of the same type, source and value)
	if list:size() > 0 then Proxy.removeExact(server, battle, unit, list) end
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	clearTmp(server, battle, unit)
	if payload.ranged or payload.isCounter or other == nil then return end
	if other:hasBonuses({ type = "FLYING" }) then return end
	-- Only when it is the main target of this hit
	local first = A.primary(payload, nil)
	if first ~= nil and first:unitID() ~= unit:unitID() then return end
	local pct = math.min(self.max or 90, A.moved(other) * (self.val or 10))
	if pct <= 0 then return end
	server:addUnitBonus(battle, unit, {
		type       = "GENERAL_DAMAGE_REDUCTION",
		subtype    = "damageTypeMelee",
		val        = pct,
		duration   = ENUM.BonusDuration.nTurns,
		turns      = 1,
		sourceType = ENUM.BonusSource.other,
		sourceID   = unit:getCreature():getJsonKey(),
		stacking   = TMP,
		hidden     = true
	}, true)
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	clearTmp(server, battle, unit)
end

return Script
