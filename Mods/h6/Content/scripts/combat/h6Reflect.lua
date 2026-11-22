local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Pleasure in Pain, Painful Pleasure (H6 Lilim, Succubus)
---
--- Melee damage taken -pct% (same as the creature's melee GENERAL_DAMAGE_REDUCTION bonus); the blocked part is reflected to the melee attacker
--- (counterattacks included): reflected damage = actual damage taken x pct / (100 - pct). Parameters: pct, animation, sound

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if payload.ranged or other == nil or not other:isAlive() or not battle:isHostile(unit, other) then return end
	local entry = self:ownEntry(unit, payload)
	if entry == nil or (entry.damage or 0) <= 0 then return end
	local pct = self.pct or 10
	local amount = math.floor(entry.damage * pct / (100 - pct))
	if amount <= 0 then return end
	local dealt = L.hit(server, battle, other, amount, self.animation, self.sound)
	L.log(server, battle, "H6_REFLECT_H6C", 1, { L.name(unit), L.name(other) }, { dealt or 0 })
end

return Script
