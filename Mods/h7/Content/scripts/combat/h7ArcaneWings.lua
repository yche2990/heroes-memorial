local Base = require("combat/combatScript")
local L = require("combat/h7AttackLib")
local S = require("combat/h7StatusLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Arcane Wings (Arcane Eagle, Simurgh)
---
--- At the end of this stack's own turn (end of its action; waiting does not count), each adjacent enemy creature (war machines and arrow towers excluded) gets a random negative spell.
--- The random table and rules are those of batch B's h7StatusLib.randomDebuff (as Magic Touch, Shield of Chaos): H7's 7 negative statuses
--- (Dazzled, Burning, Deep Freeze, Entangled, Electrified, Time Control Slow, Weakness) are replaced by original negative spells, and immune stacks are not affected;
--- A new negative status first removes the one this table added before (H7 mRemoveCurrentDebuffs).

local WAIT = "h7ArcaneWingsWait"

function Script:onWait(server, battle, unit, other, payload)
	L.setMark(server, battle, unit, WAIT, 1, 1)
end

-- Casts that do not use the turn (preparation / charge abilities) count like waiting: this action does not end the stack's turn
function Script:onUnitSpellcast(server, battle, unit, other, payload)
	L.noteNoSkipCast(server, battle, unit, WAIT)
end

function Script:onActionFinished(server, battle, unit, other, payload)
	if not L.ownTurnEnded(server, battle, unit, other, WAIT) then return end
	if not unit:isAlive() or unit:isClone() then return end
	local foes = L.adjacentUnits(battle, unit, function(o)
		return S.canHit(battle, unit, o)
	end)
	for _, t in ipairs(foes) do
		if t:isAlive() then S.randomDebuff(server, battle, unit, t) end
	end
end

return Script
