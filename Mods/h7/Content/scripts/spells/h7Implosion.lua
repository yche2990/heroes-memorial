--- Implosion (H7) (an H7 Prime spell, put in Earth in the memorial): cast on an enemy stack.
--- Damage = the target's current total health x min(cap, pctBase + pctPer x Spell Power)% (adjusted by the spell damage flow: school reduction, magic reduction, vulnerability, hero bonus).
--- Then other stacks within 3 hexes of the target (friend or foe, arrow towers and war machines excluded) are each pulled 1 hex closer (those that cannot move stay).
--- echo (Expert = Prime Understanding III): the target is hit again at the start of the next round for echoBase + echoPer x Spell Power (capped at echoCap)% of its total health at that time (combat/h7ImplosionEcho).
--- Prime-immune creatures (H7_PRIME_IMMUNITY_H7C): halved damage (MORE_DAMAGE_FROM_SPELL added by the creature script h7PrimeImmunity, counted in the damage adjustment), not pulled, no aftershock.
local Base = require("spells/damage")
local Lib = require("spells/h5SpellLib")
local E = require("heroes-memorial.h7:combat/h7EarthLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local function pick(arr, lvl, default)
	if not arr then return default end
	return arr[lvl + 1] or arr[#arr] or default
end

function Script:percent(mechanics)
	local lvl, sp = Lib.level(mechanics), Lib.power(mechanics)
	local pct = pick(self.pctBase, lvl, 1) + pick(self.pctPer, lvl, 1) * sp
	return math.min(pick(self.cap, lvl, 30), pct)
end

function Script:isValidTarget(mechanics, unit)
	if not Base.isValidTarget(self, mechanics, unit) then return false end
	return not unit:isTurret()
end

function Script:damageForTarget(targetIndex, mechanics, unit)
	local raw = unit:getAvailableHealth() * self:percent(mechanics) / 100 * Lib.casterDamageFactor(mechanics)
	return Lib.adjust(mechanics, unit, raw)
end

--- Move u one hex toward centerUnit: the hex among the 6 neighbours that is closer to the target and where it fits
local function pullOne(server, battle, u, centerUnit)
	local pos = u:getPosition()
	local cur = E.unitHexDistance(centerUnit, pos)
	local best, bestD = nil, cur
	for _, step in ipairs({ "copyToWest", "copyToEast", "copyToNorthWest", "copyToNorthEast", "copyToSouthWest", "copyToSouthEast" }) do
		local ok, h = pcall(function() return pos[step](pos) end)
		if ok and h and h:isValid() and h:isAvailable() then
			local d = E.unitHexDistance(centerUnit, h)
			if d < bestD and d >= 1 and not centerUnit:coversPos(h) then
				local acc = false
				pcall(function() acc = battle:isAccessibleForUnit(u, h) end)
				local occupant = battle:getUnitByPos(h, true)
				if acc and (occupant == nil or occupant:unitID() == u:unitID()) then
					best, bestD = h, d
				end
			end
		end
	end
	if best then
		server:moveUnit(battle, u, best, true)
		return true
	end
	return false
end

function Script:pull(mechanics, server, centerUnit)
	local battle = mechanics:getBattle()
	local spell = mechanics:getSpell()
	local cid = centerUnit:unitID()
	local list = battle:getUnitsIf(function(u)
		if u:unitID() == cid or not E.real(u) then return false end
		if E.has(u, "SIEGE_WEAPON") or E.primeImmune(u) then return false end
		if u:hasAbsoluteImmunity(spell) then return false end
		local dist = 1000
		local hs = u:getHexes()
		for i = 1, hs:size() do
			local x = E.unitHexDistance(centerUnit, hs:at(i))
			if x < dist then dist = x end
		end
		return dist >= 2 and dist <= (self.pullRange or 3)
	end)
	table.sort(list, function(a, b)
		return E.unitHexDistance(centerUnit, a:getPosition()) < E.unitHexDistance(centerUnit, b:getPosition())
	end)
	local moved = false
	for _, u in ipairs(list) do
		if pullOne(server, battle, u, centerUnit) then moved = true end
	end
	if moved then server:refreshBattleUnits(battle) end
end

function Script:apply(mechanics, server, target)
	Base.apply(self, mechanics, server, target)
	if not server:describeChanges() then return end
	local battle = mechanics:getBattle()
	local spellKey = mechanics:getSpell():getJsonKey()
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit and unit:isAlive() and not unit:isGhost() then
			self:pull(mechanics, server, unit)
			if self.echo and not E.primeImmune(unit) then
				local sp = Lib.power(mechanics)
				local pct = math.min(self.echoCap or 60, (self.echoBase or 3) + (self.echoPer or 1.5) * sp)
				server:addUnitBonus(battle, unit, {
					type = "COMBAT_EVENT_TRIGGER",
					subtype = self.echoScript or "heroes-memorial.h7:h7ImplosionEcho",
					val = math.max(1, math.floor(pct + 0.5)),
					duration = "N_TURNS",
					turns = 2,
					sourceType = "SPELL_EFFECT", sourceSecondaryID = mechanics:getEffectLevel(),
					sourceID = spellKey,
					stacking = "h7ImplosionEcho",
					-- H7 audit B1: the casting hero's spell bonus (Sorcery, specialty etc.) is converted to a percentage at cast time and applied again when the aftershock is settled
					addInfo = { side = mechanics:getCasterSide(), spell = spellKey, bonus = math.floor(mechanics:applySpellBonus(1000, unit) / 10 + 0.5) },
					icon = self.icon
				}, false)
			end
		end
	end
end

function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
