local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Mass Resurrection (H6 Uriel): all dead friendly stacks (corpses still there) are fully resurrected to their battle-start count (permanent). The caster itself is excluded.
--- Parameters: key, animation, sound

function Script:corpses(mechanics)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	return battle:getUnitsIf(function(u)
		return u:getSide() == caster:getSide() and not u:isAlive() and not u:isGhost() and u:unitID() ~= caster:unitID()
			and not u:isTurret() and not u:hasBonuses({ type = "SIEGE_WEAPON" })
	end)
end
function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	if caster == nil or #self:corpses(mechanics) == 0 then problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget); return false end
	return true
end
function Script:applicableTarget(mechanics, problem, target) return true end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil then return end
	local n = 0
	for _, u in ipairs(self:corpses(mechanics)) do
		local amt, lvl = L.reviveHeal(u, L.initialHealth(u))   -- Ring of Oblivion: corpses cannot be resurrected
		local _, raised = server:healUnit(battle, u, amt, lvl, ENUM.HealPower.permanent)
		if (raised or 0) > 0 then n = n + 1 end
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.log(server, battle, "H6_MASSRES_H6C", 1, { L.name(caster) }, { n })
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
