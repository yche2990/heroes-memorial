--- Extra hit of Air Reflexes (H7): the spell separately grants ADDITIONAL_ATTACK (melee only), and this script makes that extra hit
--- (melee attacks with attackIndex >= 1 within the same attack) use "Attack + val", removed afterwards (val can be negative).
--- val is computed by the spell with the H7 formula: none M x 1.0 - 30, Basic M x 1.5 - 30, Advanced M x 1.5 - 30, Expert (Understanding III) fixed +10.
--- The engine's extra attack always comes after the counterattack; H7 Expert's "strikes before the counterattack" cannot be done.
local Proxy = require("lib/kadAiProxy")   -- Round 352: precise bonus removal (removal ignores the stacking group, see removeExact)
local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local TAG = "h7AirReflexesHit"

local function clear(server, battle, unit)
	local list = unit:getBonuses({ type = "PRIMARY_SKILL" }):filter(function(b)
		return b:getStacking() == TAG
	end)
	if list:size() > 0 then Proxy.removeExact(server, battle, unit, list) end
end

local function extraMelee(payload)
	if payload == nil or payload.isCounter or payload.ranged then return false end
	return (payload.attackIndex or 0) >= 1
end

function Script:onBeforeAttack(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	if not extraMelee(payload) then return end
	local delta = self.val or 0
	if delta == 0 then return end
	clear(server, battle, unit)
	server:addUnitBonus(battle, unit, {
		type       = "PRIMARY_SKILL",
		subtype    = "primarySkill.attack",
		val        = delta,
		duration   = "N_TURNS",
		turns      = 1,
		sourceType = "OTHER",
		sourceID   = TAG,
		stacking   = TAG,
		hidden     = true
	}, false)
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not extraMelee(payload) then return end
	clear(server, battle, unit)
end

function Script:onActionFinished(server, battle, unit, other, payload)
	clear(server, battle, unit)
end

return Script
