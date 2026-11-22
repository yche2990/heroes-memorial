local Base = require("combat/combatScript")
local L = require("heroes-memorial.h7:combat/h7SLLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Retribution (H7): added by the spell h7Retribution (heroes-memorial:h5Attach), lasting 3 rounds.
--- Each time a stack with this effect is attacked (melee, ranged or counterattack) and loses health, the attacker takes val Light damage (computed from Spell Power at cast time),
--- adjusted by the attacker's Light / all-school spell damage reduction and vulnerability to Retribution; Light-immune attackers (school immunity, negative Light immunity, Light reduction >= 100%) are unaffected.
--- Invincible, dead and same-side attackers (controlled stacks count for their current controller) are skipped.
---
--- Parameters:
---   val   raw damage of each retribution

local KEY = "h7Retribution"
local ANIM = "h7/fx/slRetributionHit"
local SOUND = "h7/spell_retribution_tick.ogg"

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if other == nil or not other:isAlive() or other:isGhost() then return end
	if other:isInvincible() then return end
	if not L.hostile(battle, other, unit) then return end
	local entry = self:ownEntry(unit, payload)
	if entry == nil or (entry.damage or 0) <= 0 then return end
	if L.schoolImmune(other, "lightSchool") then return end

	local dmg = L.resist(other, self.val or 0, "lightSchool", KEY)
	if dmg <= 0 then return end

	L.anim(server, battle, { other }, ANIM, SOUND, 0.9)
	local done, killed = server:damageUnit(battle, other, dmg)
	server:appendLog(battle, {
		append         = { "core.bonus.H7_SL_LOG_H7C.description.2" },
		replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()), other:getCreature():getNameTextID(other:getCount()) },
		replaceNumbers = { done }
	})
	L.perishLog(server, battle, other, killed)
end

return Script
