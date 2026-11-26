--- Burning Heart, Despair (H6): dispel the target's opposite-direction morale spells when cast. sign = -1: dispel morale-lowering spells (Burning Heart); sign = 1: dispel morale-raising ones (Despair).
local Base = require("spells/unitEffect")
local S = require("lib/h6SpLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:apply(mechanics, server, target)
	if not server:describeChanges() then return end
	local battle = mechanics:getBattle()
	local own = mechanics:getSpell():getJsonKey()
	for _, dest in ipairs(target) do
		if dest.unit and dest.unit:isAlive() then S.dispelBySign(server, battle, dest.unit, "MORALE", self.sign or -1, own) end
	end
end
if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
