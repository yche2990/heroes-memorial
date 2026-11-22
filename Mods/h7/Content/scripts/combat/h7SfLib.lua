--- Heroes VII creatures and spells (heroes-memorial.h7) spell batch SF (Fire): shared helpers.
--- Only loaded with require("combat/h7SfLib"), not registered as a script.
---
---   M.fireImmune(unit, spellName)     immune to this Fire damage: invincible, Fire immunity, negative Fire immunity, SPELL_IMMUNITY to this spell, level 5 spell immunity
---   M.fireDamage(unit, raw)           scaled by Fire damage reduction (SPELL_DAMAGE_REDUCTION Fire + any; negative is vulnerability), at least 1
---   M.hexDistance / M.unitDistance    same as the engine's BattleHex::getDistance
---   M.adjacentUnits(battle, unit)     living stacks adjacent to unit (itself and arrow towers excluded)

local M = {}

M.MOD = "heroes-memorial.h7"

local function has(unit, filter)
	local ok, r = pcall(function() return unit:hasBonuses(filter) end)
	return ok and r
end
M.has = has

local function value(unit, filter)
	local ok, r = pcall(function() return unit:getBonusesValue(filter) end)
	if ok and type(r) == "number" then return r end
	return 0
end

function M.fireImmune(unit, spellName)
	if unit:isInvincible() then return true end
	if has(unit, { type = "SPELL_SCHOOL_IMMUNITY", subtype = "fire" }) then return true end
	if has(unit, { type = "NEGATIVE_EFFECTS_IMMUNITY", subtype = "fire" }) then return true end
	if has(unit, { type = "NEGATIVE_EFFECTS_IMMUNITY", subtype = "any" }) then return true end
	if value(unit, { type = "LEVEL_SPELL_IMMUNITY" }) >= 5 then return true end
	if spellName then
		local short = string.gsub(spellName, "^.*:", "")
		if has(unit, { type = "SPELL_IMMUNITY", subtype = short }) then return true end
		if has(unit, { type = "SPELL_IMMUNITY", subtype = M.MOD .. ":" .. short }) then return true end
	end
	return false
end

function M.fireDamage(unit, raw)
	local red = value(unit, { type = "SPELL_DAMAGE_REDUCTION", subtype = "fire" })
		+ value(unit, { type = "SPELL_DAMAGE_REDUCTION", subtype = "any" })
	if red >= 100 then return 0 end
	local dmg = math.floor(raw * (100 - red) / 100)
	if dmg < 1 then dmg = 1 end
	return dmg
end

function M.hexDistance(a, b)
	local y1, y2 = a:getY(), b:getY()
	local x1 = a:getX() + math.floor(y1 / 2)
	local x2 = b:getX() + math.floor(y2 / 2)
	local dx, dy = x2 - x1, y2 - y1
	if (dx >= 0 and dy >= 0) or (dx < 0 and dy < 0) then
		return math.max(math.abs(dx), math.abs(dy))
	end
	return math.abs(dx) + math.abs(dy)
end

function M.unitDistance(a, b)
	local ha, hb = a:getHexes(), b:getHexes()
	local best = 1000
	for i = 1, ha:size() do
		for j = 1, hb:size() do
			best = math.min(best, M.hexDistance(ha:at(i), hb:at(j)))
		end
	end
	return best
end

function M.adjacent(a, b)
	local around = a:getSurroundingHexes()
	local hexes = b:getHexes()
	for i = 1, hexes:size() do
		if around:contains(hexes:at(i)) then return true end
	end
	return false
end

function M.adjacentUnits(battle, unit)
	local id = unit:unitID()
	return battle:getUnitsIf(function(u)
		return u:unitID() ~= id and u:isAlive() and not u:isGhost() and not u:isTurret() and M.adjacent(unit, u)
	end)
end

--- Add a hidden mark (an older mark with the same stacking is removed first); turns nil means the whole battle
function M.setMark(server, battle, unit, typeName, val, turns)
	local list = unit:getBonuses({ type = typeName })
	if list:size() > 0 then server:removeUnitBonuses(battle, unit, list) end
	local d = {
		type       = typeName,
		val        = val,
		sourceType = ENUM.BonusSource.other,
		sourceID   = unit:getCreature():getJsonKey(),
		stacking   = typeName,
		hidden     = true
	}
	if turns then
		d.duration = ENUM.BonusDuration.nTurns
		d.turns = turns
	else
		d.duration = ENUM.BonusDuration.oneBattle
	end
	server:addUnitBonus(battle, unit, d, true)
end

return M
