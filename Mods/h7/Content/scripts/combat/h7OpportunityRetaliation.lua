local Base = require("combat/combatScript")
local L = require("combat/h7AttackLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Opportunity Retaliation (Inquisitor, Purifier)
---
--- When an enemy attacks in melee (counterattacks and second strikes do not count) an ally adjacent to this stack, and the attacker is also adjacent to this stack, this stack immediately
--- makes a supporting retaliation against the attacker: normal melee damage (Attack/Defense modifier applied, no Luck), without using up retaliations, once per round.
--- Not triggered while this stack cannot act (Blind, Petrify, Incapacitated and other NOT_ACTIVE); not triggered if the attacker has "enemies cannot retaliate".
---
--- Setup: one visible copy of this script on the creature (for display) + one hidden copy passed battle-wide with BATTLE_WIDE (the carrier, run on the stack being hit)
--- + the hidden mark H7_OPP_RETALIATION_H7C (who has Opportunity Retaliation). The script tells friend from foe with getSide.
--- Approximation: the supporting retaliation has no attack animation (only a slash effect and the hit), and its damage is computed with the H3 formula.

local MARKER = "H7_OPP_RETALIATION_H7C"
local USED = "h7OppRetUsed"

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if payload.ranged or payload.isCounter or (payload.attackIndex or 0) ~= 0 then return end
	if other == nil or not other:isAlive() or not unit:isAlive() then return end
	if not battle:isHostile(other, unit) then return end
	if other:hasBonuses({ type = "BLOCKS_RETALIATION" }) or other:isInvincible() then return end

	local guards = battle:getUnitsIf(function(u)
		return u:isAlive() and not u:isGhost() and not u:isClone() and u:unitID() ~= unit:unitID() and u:unitID() ~= other:unitID()
			and u:hasBonuses({ type = MARKER }) and not battle:isHostile(u, unit) and battle:isHostile(u, other)
	end)
	for _, g in ipairs(guards) do
		if other:isAlive() and g:isAlive() and L.markValue(g, USED) == nil
			and not g:hasBonuses({ type = "NOT_ACTIVE" })
			and L.unitDistance(g, unit) == 1 and L.unitDistance(g, other) == 1 then
			L.setMark(server, battle, g, USED, 1, 1)
			local dmg = L.attackDamage(server, g, other, 100, false)
			local dealt, killed = L.hit(server, battle, other, dmg, "h7/fx/h7Cleave", "")
			L.log(server, battle, 1, { L.name(g) }, { dealt })
			L.perish(server, battle, other, killed)
		end
	end
end

return Script
