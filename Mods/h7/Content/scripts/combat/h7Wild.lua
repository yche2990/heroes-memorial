local Base = require("combat/combatScript")
local L = require("combat/h7AttackLib")
local S = require("combat/h7StatusLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Wild (War Bear, Black Bear)
---
--- After being attacked in melee by an enemy (counterattacks do not count) and taking damage, it goes wild until the end of this stack's next action (waiting does not count):
---   · each attack strikes twice (ADDITIONAL_ATTACK +1; the target counterattacks after the first strike as usual);
---   · on a critical hit (H7 critical hit = lucky strike; chance see combat/h7StatusLib.crit) the target cannot act until the end of its next action
---     and cannot counterattack (h7StatusLib.incapacitate of batch B, same rules as Bash).
--- Display: H7_WILD_H7C (with icon and description).

local KEY = "h7Wild"
local WAIT = "h7WildWait"
local TYPES = { "ADDITIONAL_ATTACK", "H7_WILD_H7C" }

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if payload.ranged or payload.isCounter then return end
	if not unit:isAlive() or other == nil or not battle:isHostile(other, unit) then return end
	local entry = self:ownEntry(unit, payload)
	if entry == nil or (entry.damage or 0) <= 0 then return end
	local fresh = not L.hasTurnBuff(unit, KEY, "H7_WILD_H7C")
	L.addTurnBuff(server, battle, unit, KEY, {
		{ type = "ADDITIONAL_ATTACK", val = 1, hidden = true },
		{ type = "H7_WILD_H7C", val = 1, icon = "h7/abilities/h7Wild" }
	})
	if fresh then
		server:showBattleAnimation(battle, { { unit = unit } }, "h7/fx/h7BearWild", "", 1.0, true)
		server:refreshBattleUnits(battle)
		L.log(server, battle, 9, { L.name(unit) }, {})
	end
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.ranged or not unit:isAlive() then return end
	if not L.hasTurnBuff(unit, KEY, "H7_WILD_H7C") then return end
	local main = payload.targets and payload.targets[1]
	local t = (main and main.unit) or other
	if t == nil or (main ~= nil and (main.damage or 0) <= 0) then return end
	if not S.canHit(battle, unit, t) then return end
	if not S.crit(server, battle, unit) then return end
	S.ensureTracker(server, battle, unit)
	S.incapacitate(server, battle, unit, t, { acting = payload.isCounter })
end

function Script:onWait(server, battle, unit, other, payload)
	L.setMark(server, battle, unit, WAIT, 1, 1)
end

-- Casts that do not use the turn (preparation / charge abilities) count like waiting: this action does not end the stack's turn
function Script:onUnitSpellcast(server, battle, unit, other, payload)
	L.noteNoSkipCast(server, battle, unit, WAIT)
end

function Script:onActionFinished(server, battle, unit, other, payload)
	if not L.ownTurnEnded(server, battle, unit, other, WAIT) then return end
	L.clearTurnBuff(server, battle, unit, KEY, TYPES)
end

return Script
