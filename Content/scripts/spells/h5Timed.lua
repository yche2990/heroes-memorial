--- H5 duration spells: two changes on top of the core timed effect
---   1. Duration by the H5 formula: trunc(durBase[mastery] + durPer[mastery] x SP), at least 1 (same for hero and creature casts)
---   2. Some bonus values vary with SP: values = { bonus name = { base = {4}, per = {4}, scale = multiplier, mode = "..." } }
---      mode omitted: val = trunc((base + per*SP) * scale)
---      mode = "mulCap": "multiply by min(1, base+per*SP)" turned into a speed percent: val = trunc((min(1, x) - 1) * 100) (Puppet Master's initiative)
--- Also:
---   requireAny / exclude  target filter (bonus type names)
---   expertOnlyAboveTier   targets above this tier can only be cast on at Expert (Puppet Master: tier 7 needs Expert Dark Magic)
local Base = require("spells/timed")
local Lib = require("spells/h5SpellLib")
local Proxy = require("lib/kadAiProxy")   -- Round 375: AI simulation branch
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Round 375: substitution table for the simulation (custom bonus -> native bonus of the similar original effect)
---   Divine Strength H5_BLESS_H5C  -> original Bless ALWAYS_MAXIMUM_DAMAGE
---   Weakness H5_CURSE_H5C  -> original Curse ALWAYS_MINIMUM_DAMAGE
---   Confusion H5_FORGET_H5C -> original Forgetfulness FORGETFULL (value = percent forgetting to shoot)
local AI_PROXY = {
	H5_BLESS_H5C  = { type = "ALWAYS_MAXIMUM_DAMAGE", val = function(v) return 0 end },
	H5_CURSE_H5C  = { type = "ALWAYS_MINIMUM_DAMAGE", val = function(v) return 0 end },
	H5_FORGET_H5C = { type = "FORGETFULL", val = function(v) return v end },
}

function Script:isValidTarget(mechanics, unit)
	if not Base.isValidTarget(self, mechanics, unit) then return false end
	if not Lib.passesFilter(unit, self.requireAny, self.exclude) then return false end
	if self.expertOnlyAboveTier and unit:creatureLevel() > self.expertOnlyAboveTier and Lib.level(mechanics) < 3 then
		return false
	end
	return true
end

function Script:convertBonuses(mechanics)
	local converted = Base.convertBonuses(self, mechanics)
	local sp = Lib.power(mechanics)
	local lvl = Lib.level(mechanics)
	local dur = Lib.duration(self.durBase, self.durPer, lvl, sp)
	for name, nb in pairs(converted) do
		local spec = self.values and self.values[name]
		if spec then
			local x = Lib.value(spec.base, spec.per, lvl, sp)
			if spec.mode == "mulCap" then
				nb.val = math.floor((math.min(1, x) - 1) * 100)
			else
				nb.val = math.floor(x * (spec.scale or 1))
			end
		end
		if dur and not (self.bonus[name] and self.bonus[name].turns and self.bonus[name].turns > 0) then
			nb.turns = dur
		end
	end
	if self.aiTrial then
		-- Round 375: in the AI simulation custom bonuses are replaced by those of the similar original effects (the AI only knows native bonuses and values custom ones at 0, so it never cast them)
		for name, nb in pairs(converted) do
			local proxy = AI_PROXY[nb.type]
			if proxy then
				nb.type = proxy.type
				nb.subtype = nil
				nb.val = proxy.val(nb.val or 0)
			end
		end
	end
	return converted
end

--- Round 375: AI simulation branch. Only when describeChanges() is false (the AI estimating on an imaginary battlefield) the result of convertBonuses is swapped for native bonuses;
--- real casts are not changed at all.
function Script:apply(mechanics, server, target)
	if Proxy.trial(server) then
		self.aiTrial = true
		local ok, err = pcall(Base.apply, self, mechanics, server, target)
		self.aiTrial = nil
		if not ok then error(err) end
		return
	end
	return Base.apply(self, mechanics, server, target)
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
