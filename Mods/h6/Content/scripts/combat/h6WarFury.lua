local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- War Fury (H6 Panther Warrior, Panther Warlord): after first dealing damage to an enemy, immune to mind spells for the rest of the battle.

local TAG = "h6WarFury"

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() or unit:hasBonuses({ type = "H6_WAR_FURY_H6C" }) then return end
	local dealt = 0
	for _, t in ipairs(payload.targets or {}) do dealt = dealt + (t.damage or 0) end
	if dealt <= 0 then return end
	L.addBonus(server, battle, unit, { type = "H6_WAR_FURY_H6C", val = 0, stacking = TAG }, false)
	L.addBonus(server, battle, unit, { type = "MIND_IMMUNITY", val = 0, hidden = true, stacking = TAG }, false)
end

return Script
