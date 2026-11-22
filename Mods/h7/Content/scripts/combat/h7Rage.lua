local Base = require("combat/combatScript")
local L = require("combat/h7AttackLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Rage (Black Bear)
---
--- After being hit by an enemy ranged attack and taking damage: damage +damage (minimum and maximum), Speed +speed, immune to mind spells,
--- until the end of this stack's next action (waiting does not count). Being shot again only refreshes, no stacking.
--- Approximation: H7's "immune to negative mind effects (morale reduction, Mesmerize, Face of Fear)" uses MIND_IMMUNITY (which also blocks positive mind spells); morale reduction is not blocked.
--- Display: H7_RAGE_H7C (with icon and description).
---
--- Parameters: damage (default 3), speed (default 2)

local KEY = "h7Rage"
local WAIT = "h7RageWait"
local TYPES = { "CREATURE_DAMAGE", "STACKS_SPEED", "MIND_IMMUNITY", "H7_RAGE_H7C" }

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if not payload.ranged or payload.isCounter then return end
	if not unit:isAlive() or other == nil or not battle:isHostile(other, unit) then return end
	local entry = self:ownEntry(unit, payload)
	if entry == nil or (entry.damage or 0) <= 0 then return end
	local fresh = not L.hasTurnBuff(unit, KEY, "H7_RAGE_H7C")
	L.addTurnBuff(server, battle, unit, KEY, {
		{ type = "CREATURE_DAMAGE", subtype = "creatureDamageBoth", val = self.damage or 3, hidden = true },
		{ type = "STACKS_SPEED", val = self.speed or 2, hidden = true },
		{ type = "MIND_IMMUNITY", val = 0, hidden = true },
		{ type = "H7_RAGE_H7C", val = self.damage or 3, icon = "h7/abilities/h7Rage" }
	})
	if fresh then
		server:showBattleAnimation(battle, { { unit = unit } }, "h7/fx/h7BearRage", "", 1.0, true)
		server:refreshBattleUnits(battle)
		L.log(server, battle, 10, { L.name(unit) }, {})
	end
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
