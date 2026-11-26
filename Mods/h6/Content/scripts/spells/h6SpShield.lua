--- Celestial Armor (H6, single / mass): Defense +def, all magic damage -mres%, and absorbs pct% of the damage taken until base + per x Spell Power has been absorbed
--- (absorption settled by combat/h6SpShieldAbsorb; when full, all effects of this spell are removed; otherwise it lasts until the battle ends). Casting again resets the absorption to the new value.
--- Parameters: base, per, def, mres (4 numbers), pct
local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local S = require("lib/h6SpLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local key = mechanics:getSpell():getJsonKey()
	local amount = math.floor(S.value(mechanics, self.base, self.per))
	local lvl = mechanics:getEffectLevel()
	for _, dest in ipairs(target) do
		local u = dest.unit
		if u and u:isAlive() then
			if Proxy.trial(server) then
				Proxy.buff(server, battle, u, { type = "PRIMARY_SKILL", subtype = "defence", val = 2 + math.floor(amount / math.max(1, u:getMaxHealth())), turns = 3 })
			else
				local function add(d)
					d.duration = "ONE_BATTLE"; d.sourceType = "SPELL_EFFECT"; d.sourceID = key; d.sourceSecondaryID = lvl
					server:addUnitBonus(battle, u, d, false)
				end
				add({ type = "PRIMARY_SKILL", subtype = "defence", val = S.pick(mechanics, self.def) })
				add({ type = "SPELL_DAMAGE_REDUCTION", subtype = "spellSchool.any", val = S.pick(mechanics, self.mres) })
				add({ type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h6:h6SpShieldAbsorb", val = 0, addInfo = { pct = self.pct or 100, spell = key, key = key } })
				L.setMark(server, battle, u, key, amount)
			end
		end
	end
end
if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
