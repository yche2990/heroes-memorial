local Base = require("spells/spellEffect")
local L = require("spells/h5AbLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- "Counter" effect paired with other effects: each cast is counted, and the cast is refunded when unlimited (uses omitted) or uses is not yet reached.
--- Used on creature active abilities that apply engine effects directly (timed etc.). Parameters: key (counter mark), uses

function Script:apply(mechanics, server, target)
	local caster = mechanics:getUnitCaster()
	if caster == nil then return end
	L.useCast(server, mechanics:getBattle(), caster, self.key or ("h5AbRefund" .. mechanics:getSpell():getJsonKey()), self.uses)
end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
