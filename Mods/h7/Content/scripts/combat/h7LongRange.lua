local Proxy = require("lib/kadAiProxy")   -- Round 352: precise bonus removal (removal ignores the stacking group, see removeExact)
local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Long Range (Lizard Lancer)
---
--- When it attacks a single-hex creature on its own (counterattacks do not count), the target cannot counterattack this attack.
--- How it works: before the attack the target gets NO_RETALIATION (stacking h7LongRange, until the end of the round as a fallback), removed when this stack's action ends.
--- If the target has FIRST_STRIKE, the first-strike counterattack happens before this script and cannot be blocked (same as the engine's first-strike order).

local KEY = "h7LongRange"

function Script:onBeforeAttack(server, battle, unit, other, payload)
	if payload.isCounter or not unit:isAlive() then return end
	local main = payload.targets and payload.targets[1]
	local t = (main and main.unit) or other
	if t == nil or not t:isAlive() or not battle:isHostile(unit, t) then return end
	if t:getHexes():size() ~= 1 then return end
	local mine = t:getBonuses({ type = "NO_RETALIATION" }):filter(function(b) return b:getStacking() == KEY end)
	if mine:size() > 0 then return end
	server:addUnitBonus(battle, t, {
		type = "NO_RETALIATION", val = 0, hidden = true,
		duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(), stacking = KEY
	}, false)
end

function Script:onActionFinished(server, battle, unit, other, payload)
	if other == nil or other:unitID() ~= unit:unitID() then return end
	local marked = battle:getUnitsIf(function(u)
		return u:getBonuses({ type = "NO_RETALIATION" }):filter(function(b) return b:getStacking() == KEY end):size() > 0
	end)
	for _, u in ipairs(marked) do
		local list = u:getBonuses({ type = "NO_RETALIATION" }):filter(function(b) return b:getStacking() == KEY end)
		if list:size() > 0 then Proxy.removeExact(server, battle, u, list) end
	end
end

return Script
