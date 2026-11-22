local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Put a status spell on itself (H6 Namtaru "Dream Shield", Void Avatar "Void Circle"): the caster gets the effects of status
--- for turns rounds (0 = as written in the status spell itself, until the battle ends). The source is a spell, so it can be dispelled. Cannot be cast again while it has this status.
--- Parameters: status, turns, key, animation, sound

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	local sp = L.spell(self.status)
	local ok = caster ~= nil and caster:isAlive() and sp ~= nil
	if ok then
		local k = sp:getJsonKey()
		ok = caster:getBonuses({ sourceType = ENUM.BonusSource.spellEffect }):filter(function(b) return b:getSourceID() == k end):size() == 0
	end
	if not ok then problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget) end
	return ok
end
function Script:applicableTarget(mechanics, problem, target) return true end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	local sp = L.spell(self.status)
	if caster == nil or sp == nil then return end
	-- Round 419: in the AI simulation the status may consist only of custom marks (Void Circle), so a native damage reduction is reported as well so the AI can see it
	if Proxy.trial(server) then Proxy.buff(server, battle, caster, { type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll", val = 40, turns = self.turns or 1 }) end
	server:applySpellEffects(battle, caster, sp, { caster }, 3, self.turns or 1, true)
	L.show(server, battle, { caster }, self.animation, self.sound)
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

return Script
