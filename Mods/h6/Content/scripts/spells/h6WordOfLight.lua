local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Empowered Word of Light (H6 Michael): all friendly minions (guards, including dead ones whose corpses remain) regain heal% of their total health at battle start (can resurrect, permanent);
--- all enemies take dmg% of their own total health at battle start as Light damage (scaled by Light and all-spell reduction). Parameters: heal, dmg, minion, key, animation, sound

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
	local ids = {}
	for _, id in ipairs(self.minion or {}) do ids[id] = true end
	for _, g in ipairs(L.friendsOfType(battle, caster:getSide(), ids, false)) do
		if not g:isGhost() then
			local amt, lvl = L.reviveHeal(g, math.floor(L.initialHealth(g) * (self.heal or 100) / 100))   -- Ring of Oblivion
			server:healUnit(battle, g, amt, lvl, ENUM.HealPower.permanent)
		end
	end
	local list = battle:getUnitsIf(function(u) return L.real(u) and battle:isHostile(caster, u) and not u:isInvincible() end)
	local total = 0
	for _, u in ipairs(list) do
		local a = math.floor(L.initialHealth(u) * (self.dmg or 5) / 100 * (100 - L.schoolReduction(u, "01lightSchool")) / 100)
		total = total + (L.hit(server, battle, u, a, self.animation, self.sound) or 0)
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.log(server, battle, "H6_AREA_H6C", 8, { L.name(caster) }, { #list, total })
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

return Script
