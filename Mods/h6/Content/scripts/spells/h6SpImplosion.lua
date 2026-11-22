--- Implosion (H6): the target takes base + per x Spell Power damage (Earth), and this damage cannot be healed or resurrected:
--- the health cap is kept in a hidden mark (total health at battle start - total Implosion damage), and combat/h6SpImplosionCap takes back any recovery above it at each settlement.
--- Parameters: base, per (4 numbers), animation, sound
local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local S = require("lib/h6SpLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local key = mechanics:getSpell():getJsonKey()
	local raw = S.value(mechanics, self.base, self.per)
	for _, dest in ipairs(target) do
		local u = dest.unit
		if u and u:isAlive() then
			local d = S.spellDamage(mechanics, u, raw, "earth")
			if Proxy.trial(server) then
				Proxy.damage(server, battle, u, d * 1.1, { school = "earth", negative = true })
			elseif d > 0 then
				local dealt = server:damageUnit(battle, u, d) or 0
				if u:isAlive() or not u:isGhost() then
					local cap = L.markValue(u, key) or L.initialHealth(u)
					L.setMark(server, battle, u, key, math.max(0, cap - dealt))
					server:addUnitBonus(battle, u, { type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h6:h6SpImplosionCap", val = 0,
						duration = "ONE_BATTLE", sourceType = "OTHER", stacking = "h6SpImplosionCap", hidden = true, addInfo = { key = key } }, false)
				end
			end
		end
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
end
if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

return Script
