--- Dispel (H7): removes all spell effects on the target (beneficial, negative and neutral; friend or foe may be chosen).
--- Former Prime spell: enemies with Prime immunity (hidden mark H7_PRIME_IMMUNITY_H7C, put on the Djinn in batch A) are unaffected
--- (dispelling an enemy counts as a negative spell); friendly stacks with Prime immunity are dispelled as usual.
--- Otherwise as the core Dispel (core:dispel): persistent and adventure spells are not removed, nor this spell's own effects.
local Base = require("spells/dispel")
local Lib = require("heroes-memorial.h7:spells/h7SWLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local PRIME = "H7_PRIME_IMMUNITY_H7C"

function Script:describeTargetStep()
	return nil
end

local function hostile(mechanics, unit)
	-- Hypnotized stacks count for their controller (as the Magic Cleansing of heroes-memorial.h5)
	local ok, r = pcall(function() return mechanics:getBattle():getUnitController(unit) ~= mechanics:getCasterColor() end)
	if ok then return r end
	return unit:getSide() ~= mechanics:getCasterSide()
end

function Script:isValidTarget(mechanics, unit)
	if hostile(mechanics, unit) and Lib.value(unit, PRIME) > 0 then return false end
	return Base.isValidTarget(self, mechanics, unit)
end

function Script:apply(mechanics, server, target)
	local kept = {}
	for _, dest in ipairs(target) do
		local u = dest.unit
		if u ~= nil and not (hostile(mechanics, u) and Lib.value(u, PRIME) > 0) then table.insert(kept, dest) end
	end
	Base.apply(self, mechanics, server, kept)
end

return Script
