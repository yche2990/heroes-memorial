local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Mad Laughter (H6 Maniac)
---
--- After each attack (counterattacks included) hits an enemy stack: the enemy deals -val damage per creature (status spell spell, lasting turns rounds),
--- and the Maniac deals +val damage per creature (also lasting turns rounds, refreshed on the next attack, no stacking).
--- Parameters: val, spell, turns, animation, sound

local TAG = "h6Laughter"

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local target = nil
	for _, t in ipairs(payload.targets or {}) do
		if t.unit then target = t.unit; break end
	end
	if target == nil or not L.real(target) or not battle:isHostile(unit, target) then return end
	local turns = self.turns or 2
	local spell = L.spell(self.spell or "heroes-memorial.h6:h6Mocked")
	if spell then server:applySpellEffects(battle, unit, spell, { target }, 3, turns, false) end
	L.removeByStacking(server, battle, unit, "CREATURE_DAMAGE", TAG)
	L.removeByStacking(server, battle, unit, "H6_LAUGHTER_H6C", TAG)
	L.addBonus(server, battle, unit, { type = "CREATURE_DAMAGE", subtype = "creatureDamageBoth", val = self.val or 1, hidden = true,
		duration = ENUM.BonusDuration.nTurns, turns = turns, stacking = TAG }, false)
	L.addBonus(server, battle, unit, { type = "H6_LAUGHTER_H6C", val = self.val or 1,
		duration = ENUM.BonusDuration.nTurns, turns = turns, stacking = TAG }, false)
	L.show(server, battle, { target }, self.animation, self.sound)
end

return Script
