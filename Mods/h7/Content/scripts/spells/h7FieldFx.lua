--- Battlefield-wide effect of H7 spells (Blizzard (H7)): plays an 820x676 full-battlefield animation once at cast time, changing no state itself.
--- Written into the same spell's battleEffects as the real effects (such as core:timed), marked optional, so it does not affect whether the spell can be cast.
--- Parameters:
---   anim    animation (e.g. "h7/fx/swBlizzardField")
---   sound   sound played with it, optional
local Base = require("spells/spellEffect")
local Lib = require("heroes-memorial.h7:spells/h7SWLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:describeTargetStep()
	return nil
end

function Script:apply(mechanics, server, target)
	if not server:describeChanges() then return end
	local battle = mechanics:getBattle()
	local ref = nil
	for _, dest in ipairs(target or {}) do
		if dest.hex ~= nil and dest.hex:isValid() then ref = dest.hex break end
		if dest.unit ~= nil then ref = dest.unit:getPosition() break end
	end
	ref = ref or Lib.anyHex(battle)
	Lib.fieldAnim(server, battle, ref, self.anim, self.sound)
end

return Script
