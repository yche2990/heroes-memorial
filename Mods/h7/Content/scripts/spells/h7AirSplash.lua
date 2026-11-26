--- Splash of Lightning Bolt (H7) at Advanced: enemy stacks of the caster adjacent to the main target take Air damage
--- Damage = base[mastery] + perPower[mastery] x SP (H7 average), then adjusted by the engine's spell damage flow (school reduction, magic resistance etc.).
--- The main target itself is not counted (it takes the main h5Damage of the same spell).
--- Parameters:
---   base, perPower   4 numbers, by none/basic/advanced/expert
---   anim, sound      animation and sound played on splash targets
local Base = require("spells/unitEffect")
local Lib = require("heroes-memorial:spells/h5SpellLib")
local Air = require("heroes-memorial.h7:spells/h7AirLib")
local BattleLog = require("battleLog")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local side = Air.sideNum(mechanics:getCasterSide())
	local sp, lvl = Lib.power(mechanics), Lib.level(mechanics)
	local raw = Lib.value(self.base, self.perPower, lvl, sp) * Lib.casterDamageFactor(mechanics)
	if raw <= 0 then return end
	local describe = server:describeChanges()

	local victims, seen = {}, {}
	for _, dest in ipairs(target) do
		local main = dest.unit
		if main then
			seen[main:unitID()] = true
			local around = Air.adjacentUnits(battle, main, function(u)
				return Air.sideNum(u:getSide()) ~= side and not u:isInvincible()
					and u:isValidTarget(false) and mechanics:isReceptive(u)
			end)
			for _, u in ipairs(around) do
				if not seen[u:unitID()] then
					seen[u:unitID()] = true
					victims[#victims + 1] = u
				end
			end
		end
	end
	if #victims == 0 then return end

	if describe and self.anim then
		local dests = {}
		for _, u in ipairs(victims) do dests[#dests + 1] = { unit = u } end
		server:showBattleAnimation(battle, dests, self.anim, self.sound or "", 1.0, true)
	end

	local total, kills = 0, 0
	for _, u in ipairs(victims) do
		if u:isAlive() then
			local dmg = math.max(1, Lib.adjust(mechanics, u, raw))
			local d, k = server:damageUnit(battle, u, dmg)
			total, kills = total + d, kills + k
		end
	end
	if describe and total > 0 then
		BattleLog.spellDamage(server, battle, mechanics:getSpell(), #victims == 1 and victims[1] or nil, total, kills)
	end
end

function Script:describeTargetStep()
	return nil
end

--- Hover estimate: same formula as apply. Enemy stacks of the caster adjacent to the main target each take base + perPower x SP air damage (through the engine's spell damage rules, at least 1).
--- The main target's share is reported by the h5Damage effect of the same spell, and the engine adds the two
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local battle = mechanics:getBattle()
		local side = Air.sideNum(mechanics:getCasterSide())
		local raw = Lib.value(self.base, self.perPower, Lib.level(mechanics), Lib.power(mechanics)) * Lib.casterDamageFactor(mechanics)
		if raw <= 0 then return zero end
		local victims, seen = {}, {}
		for _, dest in ipairs(self:filterTarget(mechanics, spellTarget or {})) do
			local main = dest.unit
			if main then
				seen[main:unitID()] = true
				local around = Air.adjacentUnits(battle, main, function(u)
					return Air.sideNum(u:getSide()) ~= side and not u:isInvincible()
						and u:isValidTarget(false) and mechanics:isReceptive(u)
				end)
				for _, u in ipairs(around) do
					if not seen[u:unitID()] then
						seen[u:unitID()] = true
						victims[#victims + 1] = u
					end
				end
			end
		end
		local out = { hpDelta = 0, unitsDelta = 0 }
		for _, u in ipairs(victims) do
			if u:isAlive() then
				local copy = u:copy()
				local hp, cnt = copy:getAvailableHealth(), copy:getCount()
				copy:damage(math.max(1, Lib.adjust(mechanics, u, raw)))
				out.hpDelta = out.hpDelta - (hp - copy:getAvailableHealth())
				out.unitsDelta = out.unitsDelta - (cnt - copy:getCount())
			end
		end
		return out
	end)
	if ok and result then return result end
	return zero
end

return Script
