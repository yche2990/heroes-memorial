local Base = require("spells/demonSummon")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Summon Pit Lord (H5 Arch Devil): cast on a friendly corpse, turning it into Pit Lords (summoned, vanish after battle).
--- Count = min(Arch Devil count x perCaster, corpse total health / Pit Lord health); in the original each Arch Devil makes at most 2, each Pit Lord needs a corpse with 120 health.
--- Once per battle (1 cast). Parameters: id (creature summoned), perCaster (default 2), permanent, requireAny (the corpse needs one of these bonuses; in the original only demon corpses)

function Script:raisedCreatureAmount(mechanics, unit)
	local creatureType = LIBRARY:getCreatureByName(self.id)
	local caster = mechanics:getUnitCaster()
	if creatureType == nil or caster == nil then return 0 end
	local fromHealth = math.floor(unit:getTotalHealth() / creatureType:getMaxHealth())
	local fromCaster = caster:getCount() * (self.perCaster or 2)
	return math.max(0, math.min(fromHealth, fromCaster))
end

function Script:isValidTarget(mechanics, unit)
	if unit:getSide() ~= mechanics:getCasterSide() then return false end
	if unit:isClone() then return false end
	if self.requireAny then
		local found = false
		for _, t in ipairs(self.requireAny) do
			local ok, has = pcall(function() return unit:hasBonuses({ type = t }) end)
			if ok and has then found = true break end
		end
		if not found then return false end
	end
	local ok, summoned = pcall(function() return unit:copy():isSummoned() end)
	if ok and summoned then return false end
	return Base.isValidTarget(self, mechanics, unit)
end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
