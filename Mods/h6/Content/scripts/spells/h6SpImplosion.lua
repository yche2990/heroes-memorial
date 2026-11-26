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

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

--- Hover estimate: same formula as apply. base + per x Spell Power earth damage (through the engine's spell damage adjustment), summed over targets
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local raw = S.value(mechanics, self.base, self.per)
		local out = { hpDelta = 0, unitsDelta = 0 }
		for _, dest in ipairs(self:filterTarget(mechanics, spellTarget or {})) do
			local u = dest.unit
			if u and u:isAlive() then
				local d = math.floor(S.spellDamage(mechanics, u, raw, "earth") or 0)
				if d > 0 then
					local copy = u:copy()
					local hp, cnt = copy:getAvailableHealth(), copy:getCount()
					copy:damage(d)
					out.hpDelta = out.hpDelta - (hp - copy:getAvailableHealth())
					out.unitsDelta = out.unitsDelta - (cnt - copy:getCount())
				end
			end
		end
		return out
	end)
	if ok and result then return result end
	return zero
end

return Script
