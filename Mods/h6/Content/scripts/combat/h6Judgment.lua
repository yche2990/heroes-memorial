local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Blade of Judgment (H6 Seraph, Celestial)
---
--- Damage +val% when attacking (counterattacks included) an enemy that killed one of its side's creatures this battle.
---
--- Done like the Intercept ability of the H4-H7 mechanics collection: the angel carries two bonuses, both using this script:
---   1. The angel's own (visible, role = "carrier"): value = damage bonus percentage. Before attacking it checks whether the target has the "killed our side" mark; if so a temporary damage bonus is added and removed after the attack.
---   2. The battle-wide one (hidden, role = "zone", BATTLE_WIDE): whenever any stack is hit and creatures die, the attacking enemy is marked "killed side X" (whole battle).
---      Kills before the battle starts do not count; deaths from spells or heroes do not count (no attacking stack).

local TAG = "h6Judgment"

local function killerKey(side)
	return "h6Killer" .. tostring(side)
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if self.role ~= "zone" then return end
	if other == nil or not other:isAlive() then return end
	local entry = self:ownEntry(unit, payload)
	if entry == nil or (entry.killed or 0) <= 0 then return end
	if unit:getSide() == other:getSide() then return end
	local key = killerKey(unit:getSide())
	if L.markValue(other, key) == nil then L.setMark(server, battle, other, key, 1) end
end

function Script:onBeforeAttack(server, battle, unit, other, payload)
	if self.role ~= "carrier" then return end
	L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_PREMY", TAG)
	if other == nil or not unit:isAlive() then return end
	if L.markValue(other, killerKey(unit:getSide())) == nil then return end
	L.addBonus(server, battle, unit, {
		type = "GENERAL_DAMAGE_PREMY", val = self.val or 20,
		duration = ENUM.BonusDuration.nTurns, turns = 1, stacking = TAG, hidden = true
	}, false)
	L.log(server, battle, "H6_JUDGMENT_H6C", 1, { L.name(unit), L.name(other) }, { self.val or 20 })
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if self.role ~= "carrier" then return end
	L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_PREMY", TAG)
end

return Script
