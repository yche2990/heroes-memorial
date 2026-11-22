local Base = require("combat/combatScript")
local L = require("heroes-memorial.h7:combat/h7SLLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Agony (H7): added by the spell h7Agony (heroes-memorial:h5Attach), lasting 3 rounds.
--- Each time the stack's own action ends (attack, move, wait, defend and cast all count) it takes val Dark damage (computed from Spell Power at cast time),
--- then adjusted by the target's Dark / all-school spell damage reduction and vulnerability to Agony. Invincible stacks are skipped.
---
--- Parameters:
---   val   raw damage each time

local KEY = "h7Agony"
local ANIM = "h7/fx/slAgonyTick"
local SOUND = "h7/spell_agony_02.ogg"

function Script:onActionFinished(server, battle, unit, other, payload)
	if other == nil or other:unitID() ~= unit:unitID() then return end
	if not unit:isAlive() or unit:isGhost() or unit:isInvincible() then return end
	local dmg = L.resist(unit, self.val or 0, "darkSchool", KEY)
	if dmg <= 0 then return end
	L.anim(server, battle, { unit }, ANIM, SOUND, 0.9)
	local done, killed = server:damageUnit(battle, unit, dmg)
	server:appendLog(battle, {
		append         = { "core.bonus.H7_SL_LOG_H7C.description.3" },
		replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) },
		replaceNumbers = { done }
	})
	L.perishLog(server, battle, unit, killed)
end

return Script
