local Base = require("combat/combatScript")
local L = require("heroes-memorial.h7:combat/h7AttackLib")
local M = require("heroes-memorial.h7:combat/h7SanctumLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Memorial Sanctum, Victorious Streak (approximation of the Haven ultimate Victorious Streak; a permanent bonus on the hero, passed to the whole army).
--- Original: high morale grants a full second turn (H7 normally gives only half a turn). VCMI morale already grants a full turn, so Yu changed it to:
--- in the extra action from high morale, the stack deals +val% damage (default 50).
---
--- The engine does not tell Lua "this is a morale action", so it is recognized by actions per round: the stack has already completed a full action of its own this round (waiting does not count)
--- and attacks again in the same round, which must be the extra action from morale. In VCMI morale does not trigger after waiting,
--- so "acting after waiting" is not mistaken for it. Casting abilities that do not use the turn (preparation / charge, mark h7NoSkipCast) counts like waiting, not as an action. The bonus is attached to this action and removed when it ends (the second strike of a double attack gets it too).

local ACTS  = 1     -- Mark id: actions completed this round (1-round mark)
local WAIT  = 2     -- Mark id: this action is a wait
local STACK = "h7VictoriousStreak"

local function clear(server, battle, unit)
	L.removeByStacking(server, battle, unit, "PERCENTAGE_DAMAGE_BOOST", STACK)
end

function Script:onWait(server, battle, unit, other, payload)
	M.set(server, battle, unit, WAIT, 1, 1)
end

-- Casts that do not use the turn (preparation / charge abilities) count like waiting: not a full action, so the following attack is not an extra action from morale (review R1)
function Script:onUnitSpellcast(server, battle, unit, other, payload)
	if L.noSkipCast(unit) then M.set(server, battle, unit, WAIT, 1, 1) end
end

function Script:onBeforeAttack(server, battle, unit, other, payload)
	if payload.isCounter or not unit:isAlive() then return end
	if (M.get(unit, ACTS) or 0) < 1 then return end
	if L.byStacking(unit, "PERCENTAGE_DAMAGE_BOOST", STACK):size() > 0 then return end
	local pct = self.val or 50
	if pct <= 0 then return end
	for _, sub in ipairs({ "damageTypeMelee", "damageTypeRanged" }) do
		server:addUnitBonus(battle, unit, {
			type = "PERCENTAGE_DAMAGE_BOOST", subtype = sub, val = pct,
			duration = ENUM.BonusDuration.nTurns, turns = 1,
			sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(),
			stacking = STACK, hidden = true
		}, true)
	end
	server:appendLog(battle, {
		append = { "core.bonus.H7_SANCTUM_H7C.description.1" },
		replaceStrings = { L.name(unit) },
		replaceNumbers = { pct }
	})
end

function Script:onActionFinished(server, battle, unit, other, payload)
	if other == nil or other:unitID() ~= unit:unitID() then return end
	clear(server, battle, unit)
	L.clearNoSkipCast(server, battle, unit)
	if M.get(unit, WAIT) ~= nil then
		M.clear(server, battle, unit, WAIT)
		return
	end
	M.set(server, battle, unit, ACTS, (M.get(unit, ACTS) or 0) + 1, 1)
end

return Script
