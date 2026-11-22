local Base = require("spells/unitEffect")
local Lib = require("heroes-memorial:spells/h5SpellLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 "randomly dispel N effects" (Cleansing Light: allies' negative effects; Purge: enemies' positive effects).
--- Grouped by source spell, count[mastery] of such spells on the target are chosen at random and all effects they left are removed.
--- Persistent (permanent) spells, adventure spells and effects left by this spell itself do not count.
---
--- Parameters:
---   count            4 numbers, how many to dispel by none/basic/advanced/expert
---   dispelPositive   dispel positive magic
---   dispelNegative   dispel negative magic

function Script:spellsOn(mechanics, unit)
	local current = mechanics:getSpell():getJsonKey()
	local bonuses = unit:getBonuses({}):filter(function(b)
		if b:getSource() ~= ENUM.BonusSource.spellEffect then return false end
		local key = b:getSourceID()
		if key == current then return false end
		local s = LIBRARY:getSpellByName(key)
		if not s or s:isPersistent() or s:isAdventure() then return false end
		if self.dispelPositive and s:isPositive() then return true end
		if self.dispelNegative and s:isNegative() then return true end
		return false
	end)
	local keys, seen = {}, {}
	for i = 1, bonuses:size() do
		local k = bonuses:getBonus(i):getSourceID()
		if not seen[k] then seen[k] = true; keys[#keys + 1] = k end
	end
	table.sort(keys)
	return keys
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local lvl = Lib.level(mechanics)
	local n = self.count and (self.count[lvl + 1] or self.count[#self.count]) or 1
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit and unit:isAlive() then
			local keys = self:spellsOn(mechanics, unit)
			local pick = {}
			for _ = 1, math.min(n, #keys) do
				local i = server:rngInt(1, #keys)
				pick[table.remove(keys, i)] = true
			end
			local list = unit:getBonuses({}):filter(function(b)
				return b:getSource() == ENUM.BonusSource.spellEffect and pick[b:getSourceID()] == true
			end)
			if list:size() > 0 then server:removeUnitBonuses(battle, unit, list) end
		end
	end
end

--- Newer engines call this every time a target is chosen (logging an error if missing); returning nil uses the engine's default hint
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
