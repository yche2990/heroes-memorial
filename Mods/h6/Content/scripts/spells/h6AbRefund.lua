local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- A "counting" effect to go with other effects (as h5AbRefund in the H5 memorial): each cast is counted, and the cast is refunded if unlimited (uses not given) or uses not yet reached.
--- Used for creature active abilities built directly on engine effects (damage, timed etc.).
--- usedType: after casting, the caster gets a whole-battle hidden bonus (round 351; together with a limiter on the casting bonus it makes "once per battle" without a shared cooldown).
--- Parameters: key (counting mark), uses, usedType

function Script:apply(mechanics, server, target)
	local caster = mechanics:getUnitCaster()
	if caster == nil then return end
	L.useCast(server, mechanics:getBattle(), caster, self.key or ("h6AbRefund" .. mechanics:getSpell():getJsonKey()), self.uses)
	if self.usedType then
		server:addUnitBonus(mechanics:getBattle(), caster, { type = self.usedType, val = 1, duration = ENUM.BonusDuration.oneBattle,
			sourceType = ENUM.BonusSource.other, sourceID = caster:getCreature():getJsonKey(), hidden = true }, true)
	end
end

return Script
