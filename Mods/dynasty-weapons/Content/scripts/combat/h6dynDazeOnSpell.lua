--- H6 Dynasty Weapon, Oblivion level 4 "Daze of Oblivion": the hero's offensive spells hitting enemy stacks also daze them.
--- The script is on enemy stacks; after the hero's (other == nil) damage / negative spells hit, the original statuses in status are cast (round 316t: H6 Dazed, Speed -2, 2 rounds).
local Base = require("combat/combatScript")
local Lib = require("spells/h6dynLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onSpellHit(server, battle, unit, other, payload)
	if other ~= nil or not unit or not unit:isAlive() then return end
	local spell = payload.spell
	if not spell or not (spell:isNegative() or spell:isDamage()) then return end
	for _, b in pairs(self.bonuses or {}) do Lib.addBonus(server, battle, unit, b, "OTHER", nil, false, Lib.textOf(self)) end
	Lib.statuses(server, battle, unit, self.status)
	if Lib.anim(server, battle, unit, self.anim) then server:refreshBattleUnits(battle) end
end

return Script
