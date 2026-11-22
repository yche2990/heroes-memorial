--- Heroes IV Memorial: a few Heroes IV spells that need scripts (spell effects)
--- Parameters: mode (banish / displace / martyr / drain / smoke), base, perPower (4-level arrays, value = base + perPower x Spell Power),
---       give (drain: hands the removed cast to a friendly caster), range (displace: farthest hexes), turns (smoke: rounds)
---   banish   Banish: only affects summoned stacks and clones, destroying "value" health
---   displace Displace: choose a stack, then a free hex within range hexes, and push it there (friend or foe)
---   martyr   Martyr: choose the martyr first, then another friendly stack; from then on all attack damage that stack takes goes to the martyr until the battle ends
---   drain    Mana Drain / Power Drain: an enemy caster casts one time fewer this battle (give: handed to a friendly caster)
---   smoke    Smoke: smoke on the target hex and the ring around it; shots through smoke deal half damage (settled in the tick of combat/h4Proc)
---   proxy    Proxy: effect and immunity all follow the original spell spell (every mod's changes to it still apply), only the animation is this spell's own (Heroes IV effect).
---            Used to give original spells cast actively by creatures a new effect (Mermaid's Hypnotize)
local Base = require("spells/unitEffect")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local function amount(self, mechanics)
	local lvl = (mechanics:getEffectLevel() or 0) + 1
	local sp = mechanics:getEffectPower() or 0
	local b = self.base and self.base[lvl] or 0
	local p = self.perPower and self.perPower[lvl] or 0
	return math.floor(b + p * sp)
end

local function hexDistance(a, b)
	local y1, y2 = a:getY(), b:getY()
	local x1 = a:getX() + math.floor(y1 / 2)
	local x2 = b:getX() + math.floor(y2 / 2)
	local dx, dy = x2 - x1, y2 - y1
	if (dx >= 0 and dy >= 0) or (dx < 0 and dy < 0) then return math.max(math.abs(dx), math.abs(dy)) end
	return math.abs(dx) + math.abs(dy)
end

local function ensureTick(server, battle)
	local any = battle:getUnitsIf(function(u)
		return u:getBonuses({ type = "COMBAT_EVENT_TRIGGER" }):filter(function(b) return b:getStacking() == "h4ProcTick" end):size() > 0
	end)
	if #any > 0 then return end
	server:addBattleBonus(battle, {
		type = "COMBAT_EVENT_TRIGGER", subtype = "h4Proc", val = 0, hidden = true, addInfo = { mode = "tick" },
		duration = "ONE_BATTLE", sourceType = "OTHER", stacking = "h4ProcTick"
	})
end

local function proxied(self)
	local sp = nil
	pcall(function() sp = LIBRARY:getSpellByName(self.spell) end)
	if sp == nil then pcall(function() sp = LIBRARY:getSpellByName("core:" .. self.spell) end) end
	return sp
end

function Script:isReceptive(mechanics, unit)
	if not Base.isReceptive(self, mechanics, unit) then return false end
	if self.mode ~= "proxy" then return true end
	local sp = proxied(self)
	if sp == nil or unit:hasAbsoluteImmunity(sp) then return false end
	if unit:hasBonuses({ type = "SPELL_IMMUNITY", subtype = self.spell }) then return false end
	return true
end

function Script:isValidTarget(mechanics, unit)
	if self.mode == "martyr" then return unit:isValidTarget(false) and unit:isAlive() end
	if not Base.isValidTarget(self, mechanics, unit) then return false end
	if self.mode == "banish" then return unit:copy():isSummoned() or unit:isClone() end
	if self.mode == "drain" then return unit:hasBonuses({ type = "SPELLCASTER" }) end
	return true
end

function Script:adjustTargetTypes(mechanics, types)
	if self.mode ~= "displace" and self.mode ~= "martyr" then return types end
	if #types == 0 then return types end
	if types[1] ~= ENUM.AimType.creature then return {} end
	local second = (self.mode == "displace") and ENUM.AimType.location or ENUM.AimType.creature
	if #types == 1 then return { ENUM.AimType.creature, second } end
	if types[2] ~= second then return {} end
	return types
end

function Script:applicableTarget(mechanics, problem, target)
	if (self.mode ~= "displace" and self.mode ~= "martyr") or #target <= 1 then
		return Base.applicableTarget(self, mechanics, problem, target)
	end
	local battle = mechanics:getBattle()
	local unit = target[1].unit
	if not unit then problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget); return false end
	if self.mode == "displace" then
		local toHex = target[2].hex
		local ok = toHex:isValid() and battle:isAccessibleForUnit(unit, toHex)
			and hexDistance(unit:getPosition(), toHex) <= (self.range or 2)
			and not battle:hasPenaltyOnLine(unit:getPosition(), toHex, true, true)
		if not ok then problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget) end
		return ok
	end
	local other = target[2].unit
	if not other or not other:isAlive() or other:unitID() == unit:unitID() or not mechanics:ownerMatches(other) then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
		return false
	end
	return true
end

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	local filtered = Base.transformTarget(self, mechanics, aimPoint, spellTarget)
	if (self.mode ~= "displace" and self.mode ~= "martyr") then return filtered end
	if #filtered == 0 then return {} end
	local result = { filtered[1] }
	if #aimPoint >= 2 then
		local dest = aimPoint[2]
		if self.mode == "martyr" then
			result[2] = { unit = dest.unit or mechanics:getBattle():getUnitByPos(dest.hex, true), hex = dest.hex }
		else
			result[2] = dest
		end
	end
	return result
end

function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	if self.mode == "proxy" then
		local sp, caster = proxied(self), mechanics:getUnitCaster()
		if sp == nil or caster == nil then return end
		local units = {}
		for _, d in ipairs(target) do if d.unit then table.insert(units, d.unit) end end
		-- Immunity not skipped: the original spell's own immunity rules (including those added by mods) apply here
		server:applySpellEffects(battle, caster, sp, units, mechanics:getEffectLevel(), mechanics:getEffectDuration(), false)
		return
	end
	local key = mechanics:getSpell():getJsonKey()
	if self.mode == "displace" then
		-- Nothing actually moves during the AI simulation (round 587)
		if server:describeChanges() and target[1] and target[1].unit and target[2] then server:moveUnit(battle, target[1].unit, target[2].hex, true) end
		return
	end
	if self.mode == "martyr" then
		local martyr, prot = target[1] and target[1].unit, target[2] and target[2].unit
		if not martyr or not prot then return end
		server:addUnitBonus(battle, prot, {
			type = "COMBAT_EVENT_TRIGGER", subtype = "h4Proc", val = martyr:unitID() + 1, addInfo = { mode = "martyrProt" },
			duration = "ONE_BATTLE", sourceType = "SPELL_EFFECT", sourceID = key, sourceSecondaryID = mechanics:getEffectLevel(),
			stacking = "h4Martyr", hidden = true
		}, false)
		server:addUnitBonus(battle, martyr, {
			type = "H4_MARTYR_H4C", val = 0, duration = "ONE_BATTLE", sourceType = "SPELL_EFFECT", sourceID = key,
			sourceSecondaryID = mechanics:getEffectLevel(), stacking = "h4Martyr"
		}, false)
		return
	end
	for _, dest in ipairs(target) do
		local u = dest.unit
		if u and u:isAlive() then
			if self.mode == "banish" then
				server:damageUnit(battle, u, amount(self, mechanics))
			elseif self.mode == "drain" then
				server:addUnitBonus(battle, u, {
					type = "CASTS", val = -1, duration = "ONE_BATTLE", sourceType = "SPELL_EFFECT", sourceID = key,
					sourceSecondaryID = mechanics:getEffectLevel(), stacking = "h4Drain", hidden = true
				}, true)
				if self.give then
					local side = mechanics:getCasterSide()
					local mates = battle:getUnitsIf(function(x)
						return x:isAlive() and x:getSide() == side and x:hasBonuses({ type = "SPELLCASTER" })
					end)
					if #mates > 0 then
						server:addUnitBonus(battle, mates[1], {
							type = "CASTS", val = 1, duration = "ONE_BATTLE", sourceType = "SPELL_EFFECT", sourceID = key,
							sourceSecondaryID = mechanics:getEffectLevel(), stacking = "h4Leech", hidden = true
						}, true)
					end
				end
			end
		end
	end
	server:refreshBattleUnits(battle)
end

return Script
