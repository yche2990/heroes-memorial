local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Void Shock (H6 Void Avatar): strikes all adjacent enemies for pct% of a normal attack each (no counterattack); single-hex ones are pushed back knock hexes.
--- Parameters: pct, knock, key, animation, sound

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	if caster == nil or #L.around(mechanics:getBattle(), caster, function(u) return mechanics:getBattle():isHostile(caster, u) end) == 0 then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget); return false
	end
	return true
end
function Script:applicableTarget(mechanics, problem, target) return true end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil then return end
	local list = L.around(battle, caster, function(u) return battle:isHostile(caster, u) end)
	local total = 0
	for _, u in ipairs(list) do
		total = total + (L.hit(server, battle, u, L.attackDamage(server, caster, u, self.pct or 100, false), self.animation, self.sound) or 0)
		if u:isAlive() then L.knock(server, battle, caster, u, self.knock or 2) end
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.log(server, battle, "H6_AREA_H6C", 5, { L.name(caster) }, { #list, total })
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
