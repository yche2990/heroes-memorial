--- Petrify (H6): the target turns to stone for turns rounds and takes no damage. Petrified enemy stacks cannot act; petrified friendly stacks can act, and acting ends the petrification.
--- Parameter: turns (4 numbers)
local Base = require("spells/unitEffect")
local S = require("lib/h6SpLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local key = mechanics:getSpell():getJsonKey()
	local turns = math.max(1, S.pick(mechanics, self.turns))
	local side = mechanics:getCasterSide()
	local lvl = mechanics:getEffectLevel()
	for _, dest in ipairs(target) do
		local u = dest.unit
		if u and u:isAlive() then
			local function add(d)
				d.duration = "N_TURNS"; d.turns = turns; d.sourceType = "SPELL_EFFECT"; d.sourceID = key; d.sourceSecondaryID = lvl
				server:addUnitBonus(battle, u, d, false)
			end
			add({ type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll", val = 100 })
			add({ type = "SPELL_DAMAGE_REDUCTION", subtype = "spellSchool.any", val = 100 })
			if u:getSide() ~= side then
				add({ type = "NOT_ACTIVE", subtype = key, val = 0 })
			else
				add({ type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h6:h6SpPetrifyBreak", val = 0, addInfo = { spell = key } })
			end
		end
	end
end
if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

return Script
