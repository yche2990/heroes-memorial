local Base = require("combat/combatScript")
local Proxy = require("lib/kadAiProxy")   -- Round 344: precise bonus removal (mark-fix)
local A = require("heroes-memorial.h5:combat/h5Area")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- War Dance combo (H5 War Dancer)
--- This stack attacks all surrounding enemies (ATTACKS_ALL_ADJACENT); the main target takes normal damage, the others only val% (default 50%).
--- How: before attacking the secondary targets get a temporary (100 - val)% damage reduction, removed after the attack.
--- Parameter: val

local TMP = "h5WarDanceTmp"

-- Round 375: other full damage reductions on the target from non-spell sources (the engine adds such reductions before settling) are deducted when working out the temporary reduction, as in h5Taunt
local function otherReduction(unit, tag)
	local v = unit:getBonuses({ type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll" }):filter(function(b)
		return b:getSource() ~= ENUM.BonusSource.spellEffect and b:getStacking() ~= tag
	end):totalValue()
	return math.max(0, math.min(99, v))
end

local function clearAll(server, battle, payload)
	for _, t in ipairs(payload.targets or {}) do
		local u = t.unit
		if u ~= nil then
			local list = u:getBonuses({ type = "GENERAL_DAMAGE_REDUCTION" }):filter(function(b) return b:getStacking() == TMP end)
			-- Round 344: precise removal (the engine ignores the stacking group when removing and would also remove other bonuses of the same type, source and value)
			if list:size() > 0 then Proxy.removeExact(server, battle, u, list) end
		end
	end
end

function Script:onBeforeAttack(server, battle, unit, other, payload)
	if payload.ranged then return end
	local reduce = 100 - (self.val or 50)
	if reduce <= 0 then return end
	for i, t in ipairs(payload.targets or {}) do
		local u = t.unit
		if i > 1 and u ~= nil and u:isAlive() then
			server:addUnitBonus(battle, u, {
				type       = "GENERAL_DAMAGE_REDUCTION",
				subtype    = "damageTypeAll",
				val        = math.floor((100 - otherReduction(u, TMP)) * reduce / 100),   -- Round 375: was reduce (the target's existing reduction was not deducted)
				duration   = ENUM.BonusDuration.nTurns,
				turns      = 1,
				sourceType = ENUM.BonusSource.other,
				sourceID   = unit:getCreature():getJsonKey(),
				stacking   = TMP,
				hidden     = true
			}, true)
		end
	end
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	clearAll(server, battle, payload)
end

return Script
