local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Active ability cooldown (active abilities of H6 creatures)
---
--- After a stack casts spell it gets the cooldown mark H6_COOLDOWN_H6C (N_TURNS); the creature's SPELLCASTER bonus has a limiter
--- "not active while the cooldown mark is present", so the ability cannot be used during the cooldown.
---   turns = cooldown in rounds: cast in round 1 with cooldown 1 -> usable again in round 3; with cooldown 3 -> round 5.
--- A stack has only one active ability with a cooldown, so the mark does not tell abilities apart.
---
--- Parameters: spell (full spell name), turns (cooldown rounds)

function Script:onUnitSpellcast(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local spell = payload and payload.spell
	if spell == nil or spell:getJsonKey() ~= self.spell then return end
	L.removeByStacking(server, battle, unit, "H6_COOLDOWN_H6C", "h6Cooldown")
	L.addBonus(server, battle, unit, {
		type = "H6_COOLDOWN_H6C", val = self.turns or 1,
		duration = ENUM.BonusDuration.nTurns, turns = (self.turns or 1) + 1,
		sourceType = ENUM.BonusSource.other, stacking = "h6Cooldown"
	}, false)
end

return Script
