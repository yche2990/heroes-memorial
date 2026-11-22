local Base = require("spells/h6Wither")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Spectral Curse (H6 Spectral Dragon): on an enemy within range hexes: takes pct% of a normal attack as Dark damage (no counterattack),
--- and for the next turns rounds all damage its attacks deal heals this Spectral Dragon instead (settled by the battle-wide combat/h6CurseLeech).
--- On the target: H6_CURSED_H6C (value = Spectral Dragon's id + 1, visible, turns rounds). Parameters: pct, range, turns, key, animation, sound

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	local main = target[1] and target[1].unit
	if caster == nil or not caster:isAlive() or main == nil then return end
	local raw = L.attackDamage(server, caster, main, self.pct or 100, false)
	local dealt = L.hit(server, battle, main, math.floor(raw * (100 - L.schoolReduction(main, "02darkSchool")) / 100), self.animation, self.sound) or 0
	if main:isAlive() then
		L.removeByStacking(server, battle, main, "H6_CURSED_H6C", "h6SpectralCurse")
		server:addUnitBonus(battle, main, { type = "H6_CURSED_H6C", val = caster:unitID() + 1, duration = ENUM.BonusDuration.nTurns,
			turns = self.turns or 4, sourceType = ENUM.BonusSource.other, sourceID = caster:getCreature():getJsonKey(), stacking = "h6SpectralCurse" }, true)
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.log(server, battle, "H6_AREA_H6C", 5, { L.name(caster) }, { 1, dealt })
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

return Script
