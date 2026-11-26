--- H6 Dynasty Weapons: "once per battle / cooldown" gate effect. Written into the same spell together with the core effects (teleport, dispel...):
---   when already used this battle (or on cooldown) applicableGeneral returns false and the whole spell cannot be cast;
---   casting records "used". Target selection is unaffected (applicableTarget always passes, transformTarget returns as is).
--- Parameters: onceIndex (ability id, unique in the whole mod), cooldown (0 = once per battle; N = N-round cooldown)
local Base = require("spells/spellEffect")
local Lib = require("spells/h6dynLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:applicableGeneral(mechanics, problem)
	if Lib.used(mechanics, self.onceIndex or 0) then
		problem:addGeneric(mechanics)
		return false
	end
	return true
end

function Script:applicableTarget(mechanics, problem, target)
	return true
end

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	return spellTarget
end

function Script:filterTarget(mechanics, target)
	return target
end

function Script:apply(mechanics, server, target)
	if server:describeChanges() then Lib.markUsed(mechanics, server, self.onceIndex or 0, self.cooldown) end
end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
