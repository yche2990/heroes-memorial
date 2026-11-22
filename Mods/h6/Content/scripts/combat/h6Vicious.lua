local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Ambush (H6 Goblin Hunter)
---
--- Two bonuses, both using this script:
---   1. The Goblin Hunter's own (role = "carrier"): damage +val% when attacking (counterattacks included) an enemy that has not acted yet this round.
---   2. The battle-wide one (hidden, role = "zone"): after any stack moves, attacks, defends or casts, it is marked "acted this round"
---      (gone at the start of the next round). Waiting does not count as acting.
--- Parameters: role, val

local ACTED = "h6Acted"
local TAG = "h6Vicious"

local function acted(server, battle, unit)
	if unit:isAlive() and L.markValue(unit, ACTED) == nil then L.setMark(server, battle, unit, ACTED, 1, 1) end
end

function Script:onAfterMove(server, battle, unit) if self.role == "zone" then acted(server, battle, unit) end end
function Script:onDefend(server, battle, unit) if self.role == "zone" then acted(server, battle, unit) end end
function Script:onUnitSpellcast(server, battle, unit) if self.role == "zone" then acted(server, battle, unit) end end

function Script:onBeforeAttack(server, battle, unit, other, payload)
	if self.role ~= "carrier" then return end
	L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_PREMY", TAG)
	if other == nil or not unit:isAlive() or L.markValue(other, ACTED) ~= nil then return end
	L.addBonus(server, battle, unit, { type = "GENERAL_DAMAGE_PREMY", val = self.val or 50, hidden = true,
		duration = ENUM.BonusDuration.nTurns, turns = 1, stacking = TAG }, false)
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if self.role == "carrier" then
		L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_PREMY", TAG)
	elseif self.role == "zone" and not payload.isCounter then
		acted(server, battle, unit)
	end
end

return Script
