local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Gluttony's Eye (H6 Hellhound, Cerberus)
---
--- Enemies that attacked it (counterattacks included) are marked (whole battle, H6_GLUTTONY_H6C, kept per Hellhound side);
--- this side's Hellhounds and Cerberi deal +val% damage when attacking (counterattacks included) a marked enemy. Parameter: val

local TAG = "h6Gluttony"

local function key(side) return "h6Glut" .. tostring(side) end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if other == nil or not other:isAlive() or not battle:isHostile(unit, other) then return end
	if L.markValue(other, key(unit:getSide())) then return end
	L.setMark(server, battle, other, key(unit:getSide()), 1)
	L.addBonus(server, battle, other, { type = "H6_GLUTTONY_H6C", val = self.val or 20, stacking = key(unit:getSide()) }, false)
end

function Script:onBeforeAttack(server, battle, unit, other, payload)
	L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_PREMY", TAG)
	if other == nil or not unit:isAlive() or L.markValue(other, key(unit:getSide())) == nil then return end
	L.addBonus(server, battle, unit, { type = "GENERAL_DAMAGE_PREMY", val = self.val or 20, hidden = true,
		duration = ENUM.BonusDuration.nTurns, turns = 1, stacking = TAG }, false)
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_PREMY", TAG)
end

return Script
