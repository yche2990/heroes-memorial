local Base = require("combat/combatScript")
local L = require("combat/h7AttackLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Opportunity Attack (Gnoll Hunter)
---
--- After an enemy is attacked in melee (by either side; counterattacks and second strikes do not count), if this stack is not blocked by an adjacent enemy and can shoot,
--- it immediately shoots that enemy once for 50% of a normal shot (halved again with the range penalty). Once per round.
---
--- Setup: one visible copy of this script on the creature (for display) + one hidden copy passed battle-wide with BATTLE_WIDE (the carrier, run on the stack being hit)
--- + the hidden mark H7_OPP_ATTACK_H7C (who has Opportunity Attack).
--- Approximation: no shooting animation, no projectile, no ammunition used (Lua cannot change ammunition); only an effect on the target, then the damage; no Luck.
---
--- Parameter: val (damage percentage, default 50)

local MARKER = "H7_OPP_ATTACK_H7C"
local USED = "h7OppAtkUsed"

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if payload.ranged or payload.isCounter or (payload.attackIndex or 0) ~= 0 then return end
	if other == nil or not L.damageable(unit) then return end
	if not battle:isHostile(other, unit) then return end

	local hunters = battle:getUnitsIf(function(u)
		return u:isAlive() and not u:isGhost() and not u:isClone() and u:unitID() ~= unit:unitID()
			and u:hasBonuses({ type = MARKER }) and battle:isHostile(u, unit)
	end)
	for _, h in ipairs(hunters) do
		if unit:isAlive() and h:isAlive() and L.markValue(h, USED) == nil
			and not h:hasBonuses({ type = "NOT_ACTIVE" }) and L.canShoot(h) and not L.engaged(battle, h) then
			L.setMark(server, battle, h, USED, 1, 1)
			local pct = self.val or 50
			local far = false
			pcall(function() far = battle:hasDistancePenalty(h, unit) end)
			if far then pct = pct / 2 end
			local dmg = L.attackDamage(server, h, unit, pct, true)
			if dmg <= 0 then return end -- H7 audit A3: shots at targets inside a Mist Veil deal 0 damage
			local dealt, killed = L.hit(server, battle, unit, dmg, "h7/fx/h7OpportunityAttack", "")
			L.log(server, battle, 2, { L.name(h) }, { dealt })
			L.perish(server, battle, unit, killed)
		end
	end
end

return Script
