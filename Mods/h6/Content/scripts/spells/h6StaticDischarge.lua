local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Static Discharge (H6 Thunderbird): each enemy stack takes per Air damage, plus extra for each stack next to it (friend or foe).
--- Scaled by Air and all-spell reduction. Parameters: per, extra, key, animation, sound

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget); return false end
	return true
end
function Script:applicableTarget(mechanics, problem, target) return true end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil then return end
	local list = battle:getUnitsIf(function(u) return L.real(u) and battle:isHostile(caster, u) and not u:isInvincible() end)
	local amounts = {}
	for i, u in ipairs(list) do
		amounts[i] = (self.per or 100) + (self.extra or 100) * #L.around(battle, u, nil)
	end
	local total = 0
	for i, u in ipairs(list) do
		total = total + (L.hit(server, battle, u, math.floor(amounts[i] * (100 - L.schoolReduction(u, "air")) / 100), self.animation, self.sound) or 0)
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.log(server, battle, "H6_AREA_H6C", 10, { L.name(caster) }, { #list, total })
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

return Script
