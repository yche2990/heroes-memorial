--- Feign Death (H6 Memorial Sanctum, Dungeon Might): marks a friendly stack. The first time it is attacked it takes no damage (all of this damage is restored, killed creatures saved too),
--- and then "falls": after this action it leaves the battlefield until the start of the next round (meanwhile it cannot be attacked or targeted); when it gets up it has Speed +speed until it acts.
--- Marking and triggering are handled by combat/h6MmFeignHit, putting it back next round by combat/h6MmFeignEnd on the battlefield. Parameters: speed, animation, sound
local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local M = require("lib/h6MmLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:isValidTarget(mechanics, unit)
	return M.real(unit) and unit:getSide() == mechanics:getCasterSide() and not unit:isClone()
end
function Script:isReceptive(mechanics, unit) return true end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local u = target[1] and target[1].unit
	if u == nil or not u:isAlive() then return end
	if Proxy.trial(server) then
		Proxy.buff(server, battle, u, { type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll", val = 50, turns = 1 })
		return
	end
	L.show(server, battle, { u }, self.animation, self.sound)
	for _, t in ipairs({ "COMBAT_EVENT_TRIGGER", "H6_MM_FEIGN_H6C" }) do L.removeByStacking(server, battle, u, t, "h6MmFeign") end
	M.addOther(server, battle, u, { type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h6:h6MmFeignHit", val = self.speed or 4, hidden = true, stacking = "h6MmFeign" })
	M.addOther(server, battle, u, { type = "H6_MM_FEIGN_H6C", val = 1, stacking = "h6MmFeign", icon = "h6/abilities/mm_FeignDeath" })
	server:refreshBattleUnits(battle)
end
if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
