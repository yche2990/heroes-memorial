--- H5 spells that "work round by round once attached" (Plague, Regeneration, Vampirism, Celestial Shield):
--- attach a combat event bonus to the target, with value and duration computed by the H5 formulas first.
--- Parameters:
---   eventScript            combat event script name
---   base, perPower         bonus value = trunc(base + perPower*SP) (Plague damage per action, Regeneration healing, Vampirism percent, shield capacity)
---   durBase, durPer        duration = trunc(durBase + durPer*SP), at least 1
---   eventParameters        passed to the script as is
---   requireAny, exclude    target filter
---   icon                   icon shown on the stack (description from the one the script registers)
local Base = require("spells/unitEffect")
local Lib = require("spells/h5SpellLib")
local Proxy = require("lib/kadAiProxy")   -- Round 375: AI simulation branch
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:isValidTarget(mechanics, unit)
	if not Base.isValidTarget(self, mechanics, unit) then return false end
	return Lib.passesFilter(unit, self.requireAny, self.exclude)
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local spellKey = mechanics:getSpell():getJsonKey()
	local sp, lvl = Lib.power(mechanics), Lib.level(mechanics)
	local val = math.floor(Lib.value(self.base, self.perPower, lvl, sp))
	local turns = Lib.duration(self.durBase, self.durPer, lvl, sp) or mechanics:getEffectDuration()
	if self.eventScript == "h5PlagueTick" and Proxy.trial(server) then
		-- Round 375: AI simulation branch (Plague). Combat scripts on stacks are worth 0 in the AI's estimate, so it was never cast;
		-- in the simulation it instead deducts damage per action x rounds (at most 3) x 0.6 at once; real casts do not go through here
		for _, dest in ipairs(target) do
			local unit = dest.unit
			if unit and unit:isAlive() then
				Proxy.damage(server, battle, unit, val * math.min(turns or 1, 3) * 0.6, { spell = spellKey, school = "earth", negative = true })
			end
		end
		return
	end
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit and unit:isAlive() then
			local d = {
				type = "COMBAT_EVENT_TRIGGER",
				subtype = self.eventScript,
				val = val,
				duration = "N_TURNS",
				turns = turns,
				sourceType = "SPELL_EFFECT",
				sourceID = spellKey,
				sourceSecondaryID = mechanics:getEffectLevel(), -- Round 339: since engine 89ce99f1, omitting the casting level means "any level", and looking at a stack's spell status reads the description with that level out of range, giving garbage (log: Unable to find localization); the level is stated
				stacking = spellKey,
				addInfo = self.eventParameters
			}
			if self.icon then d.icon = self.icon end
			server:addUnitBonus(battle, unit, d, false)
		end
	end
end

--- 2026-11-06: engine 89ce99f1 calls describeTargetStep when choosing a target; the core spellEffect.lua has this function,
--- but unitEffect.lua does not inherit it (heal, dispel, damage and timed all come from unitEffect), and the log reports function 'describeTargetStep' not found.
--- If the base class lacks it, one returning nil is added (= the engine's default cursor text, same display as before); once the engine adds it, the engine's is used.
if not Base.describeTargetStep then
	function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
		return nil
	end
end

return Script
