--- Might over Magic (H6 Memorial Sanctum, Stronghold Warfare): for turns rounds, all friendly stacks take -(own hero Attack + Defense - enemy hero Defense) x pct% magic damage, at most cap%.
--- The enemy hero's Defense is read from the Defense enemy stacks get from their hero's primary skills. Parameters: pct (4 numbers, unit 0.1%), cap, turns, animation, sound
local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local M = require("lib/h6MmLib")
local S = require("lib/h6SpLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:isValidTarget(mechanics, unit)
	return M.real(unit) and unit:getSide() == mechanics:getCasterSide()
end
function Script:isReceptive(mechanics, unit) return true end

function Script:reduction(mechanics)
	local battle = mechanics:getBattle()
	local side = mechanics:getCasterSide()
	local foeDef = 0
	for _, u in ipairs(battle:getUnitsIf(function(u) return M.real(u) and u:getSide() ~= side end)) do
		foeDef = math.max(foeDef, M.heroSkill(u, "defence"))
	end
	local base = M.heroPrim(mechanics, "attack") + M.heroPrim(mechanics, "defence") - foeDef
	return math.max(0, math.min(self.cap or 80, math.floor(base * S.pick(mechanics, self.pct) / 10)))
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local r = self:reduction(mechanics)
	local turns = self.turns or 2
	local units = {}
	for _, dest in ipairs(target) do if dest.unit and M.real(dest.unit) then units[#units + 1] = dest.unit end end
	if Proxy.trial(server) then
		for _, u in ipairs(units) do Proxy.buff(server, battle, u, { type = "SPELL_DAMAGE_REDUCTION", subtype = "spellSchool.any", val = r, turns = turns }) end
		return
	end
	L.show(server, battle, units, self.animation, self.sound)
	for _, u in ipairs(units) do
		L.removeByStacking(server, battle, u, "SPELL_DAMAGE_REDUCTION", "h6MmMightOverMagic")
		if r > 0 then
			M.addOther(server, battle, u, { type = "SPELL_DAMAGE_REDUCTION", subtype = "spellSchool.any", val = r, stacking = "h6MmMightOverMagic",
				icon = "h6/abilities/mm_MightOverMagic" }, turns)
		end
	end
	server:refreshBattleUnits(battle)
end
if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

return Script
