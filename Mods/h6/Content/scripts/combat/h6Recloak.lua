local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Shadow Cloak, re-cloaking (H6 Assassin, Shadow)
---
--- Cloaking at battle start is done by the stealth script (heroes-memorial:h47Stealth); this adds the other half from H6: after being revealed, if for rounds consecutive rounds
--- it makes no attack of its own (counterattacks do not count) and has no enemy next to it at round start, it cloaks again (casts the stealth spell again).
--- Timed with two hidden marks: h6CloakWait (countdown, disappears when it expires) and h6CloakArm (countdown started).
--- Parameters: spell (full name of the stealth spell), rounds (default 2)

local WAIT, ARM = "h6CloakWait", "h6CloakArm"

local function stealthed(unit)
	return unit:hasBonuses({ type = "INVINCIBLE" })
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.isCounter or not unit:isAlive() then return end
	L.setMark(server, battle, unit, WAIT, 1, (self.rounds or 2) + 1)
	L.setMark(server, battle, unit, ARM, 1)
end

function Script:onRoundStart(server, battle, unit)
	if not L.real(unit) or unit:isClone() then return end
	if stealthed(unit) then L.clearMark(server, battle, unit, ARM); return end
	if L.markValue(unit, WAIT) then return end
	if not L.markValue(unit, ARM) then
		L.setMark(server, battle, unit, ARM, 1)
		L.setMark(server, battle, unit, WAIT, 1, self.rounds or 2)
		return
	end
	if #L.around(battle, unit, function(u) return battle:isHostile(unit, u) end) > 0 then return end
	local spell = L.spell(self.spell)
	if spell == nil or not server:describeChanges() then return end
	server:castSpell(battle, unit, spell, { unit }, 0)
	L.clearMark(server, battle, unit, ARM)
end

return Script
