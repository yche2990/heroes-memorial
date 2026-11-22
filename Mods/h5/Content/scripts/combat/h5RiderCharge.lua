local Base = require("combat/combatScript")
local Proxy = require("lib/kadAiProxy")   -- Round 344: precise bonus removal (mark-fix)
local A = require("heroes-memorial.h5:combat/h5Area")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Cavalry Charge (H5 Dark Raider, Grim Raider)
--- On melee attack, the target's Defense counts val% less (default 20%) for each hex the charge travels, at most 100%. No effect on targets with Unbreakable Armor (H5_ARMORED_H5C).
--- How: before attacking it gets "ignore x% of enemy Defense" (ENEMY_DEFENCE_REDUCTION), removed after this hit.
--- Parameter: val

local TMP = "h5RiderChargeTmp"

local function clearTmp(server, battle, unit)
	local list = unit:getBonuses({ type = "ENEMY_DEFENCE_REDUCTION" }):filter(function(b) return b:getStacking() == TMP end)
	-- Round 344: precise removal (the engine ignores the stacking group when removing and would also remove other bonuses of the same type, source and value)
	if list:size() > 0 then Proxy.removeExact(server, battle, unit, list) end
end

function Script:onBeforeMove(server, battle, unit) A.beforeMove(server, battle, unit) end
function Script:onAfterMove(server, battle, unit) A.afterMove(server, battle, unit) end

function Script:onActionFinished(server, battle, unit, other)
	if other ~= nil and other:unitID() == unit:unitID() then
		A.clearMove(server, battle, unit)
		clearTmp(server, battle, unit)
	end
end

function Script:onBeforeAttack(server, battle, unit, other, payload)
	clearTmp(server, battle, unit)
	if payload.ranged or payload.isCounter or (payload.attackIndex or 0) ~= 0 then return end
	local target = A.primary(payload, other)
	if target == nil or A.has(target, "H5_ARMORED_H5C") then return end
	local pct = math.min(100, A.moved(unit) * (self.val or 20))
	if pct <= 0 then return end
	server:addUnitBonus(battle, unit, {
		type       = "ENEMY_DEFENCE_REDUCTION",
		val        = pct,
		duration   = ENUM.BonusDuration.nTurns,
		turns      = 1,
		sourceType = ENUM.BonusSource.other,
		sourceID   = unit:getCreature():getJsonKey(),
		stacking   = TMP,
		hidden     = true
	}, true)
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	clearTmp(server, battle, unit)
end

return Script
