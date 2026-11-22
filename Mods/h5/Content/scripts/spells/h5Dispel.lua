--- H5 Cleansing: dispels beneficial magic on enemy stacks and negative magic on own stacks;
--- each spell is rolled separately, success rate chance[mastery] (%, original 40/60/80/100).
--- Parameters: chance = {4}; with onlyPositive = true only beneficial magic is dispelled regardless of side (the Zealot's Purge).
local Base = require("spells/dispel")
local Lib = require("spells/h5SpellLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local function isEnemy(mechanics, unit)
	-- Hypnotized stacks count for the controlling side (as newer engines do)
	return mechanics:getBattle():getUnitController(unit) ~= mechanics:getCasterColor()
end

function Script:wantedFlags(mechanics, unit)
	if self.onlyPositive or isEnemy(mechanics, unit) then
		return true, false
	end
	return false, true
end

function Script:getDispelableBonuses(mechanics, unit)
	local currentSpellKey = mechanics:getSpell():getJsonKey()
	local pos, neg = self:wantedFlags(mechanics, unit)
	return unit:getBonuses({}):filter(function(bonus)
		if bonus:getSource() ~= ENUM.BonusSource.spellEffect then return false end
		if bonus:getSourceID() == currentSpellKey then return false end
		local sourceSpell = LIBRARY:getSpellByName(bonus:getSourceID())
		if not sourceSpell then return false end
		if sourceSpell:isPersistent() or sourceSpell:isAdventure() then return false end
		if pos and sourceSpell:isPositive() then return true end
		if neg and sourceSpell:isNegative() then return true end
		return false
	end)
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local chance = self.chance and (self.chance[Lib.level(mechanics) + 1] or 100) or 100
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit then
			local bonuses = self:getDispelableBonuses(mechanics, unit)
			-- Grouped by source spell, one roll per spell
			local bySpell, order = {}, {}
			for i = 1, bonuses:size() do
				local b = bonuses:getBonus(i)
				local key = b:getSourceID()
				if not bySpell[key] then bySpell[key] = true; table.insert(order, key) end
			end
			local remove = {}
			for _, key in ipairs(order) do
				if chance >= 100 or server:rngInt(1, 100) <= chance then remove[key] = true end
			end
			local list = bonuses:filter(function(b) return remove[b:getSourceID()] == true end)
			if list:size() > 0 then
				server:removeUnitBonuses(battle, unit, list)
			end
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
