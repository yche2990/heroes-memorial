--- Teleport (H7): teleports a friendly stack to a free hex within maxDistance[mastery] hexes (none/basic/advanced 3/5/7 hexes, unlimited at Expert).
--- At Expert the teleported stack also gets Speed +speedBonus for speedTurns rounds (H7: Initiative +50, 2 rounds).
--- Otherwise as the core teleport (core:teleport): cannot teleport into the walls or across the moat unless isWallPassable / isMoatPassable.
--- Parameters: maxDistance (4 numbers), speedBonus (4 numbers, 0 = none), speedTurns, isWallPassable, isMoatPassable
--- Round 403: AI-controlled casters (AI heroes; neutral monsters and AI creatures too) use a single step instead (B8 of review C):
--- the AI cannot build the two-step target "first the stack, then the landing spot", so it never cast this spell. The AI only chooses the stack to teleport (melee, with no enemy adjacent yet),
--- and the script picks the landing spot: a free hex within maxDistance next to the enemy its one attack would hurt most (not across walls or moat); if none, it cannot be cast.
--- In the AI simulation (describeChanges false) nothing moves; 0.6 x one attack - 0.5 x the loss from that enemy hitting back after landing is reported against that enemy; not cast if the net is below 1 creature.
--- Human casters (including human auto-combat) keep the two steps; effect and description unchanged.
local Base = require("spells/teleport")
local Lib = require("heroes-memorial.h7:spells/h7SWLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local AI_Q = 0.6
local AI_RISK = 0.5

local function aiSingle(mechanics)
	return Proxy.aiCaster(mechanics)
end

--- Net value of teleporting unit to attack e (in health points of e)
local function netGain(unit, e)
	local gain = AI_Q * Proxy.attackEstimate(unit, e, 100, false)
	local lost = Proxy.attackEstimate(e, unit, 100, false) / unit:getMaxHealth()
	return gain - AI_RISK * Proxy.costHp(unit, math.min(lost, unit:getCount()), e)
end

--- Landing spot of the AI single step: returns the landing hex and target enemy; nil if none
function Script:aiDestination(mechanics, unit)
	local battle = mechanics:getBattle()
	if unit == nil or not unit:isAlive() or unit:isShooter() then return nil end
	if #Proxy.adjacent(battle, unit, function(u) return Proxy.hostile(battle, unit, u) end) > 0 then return nil end
	local limit = Lib.pick(self.maxDistance, Lib.level(mechanics))
	local from = unit:getPosition()
	local bestHex, bestEnemy, bestScore = nil, nil, 0
	for _, e in ipairs(battle:getUnitsIf(function(x) return Proxy.hostile(battle, unit, x) end)) do
		local net = netGain(unit, e)
		local score = net / e:getMaxHealth() * Proxy.value(e)
		if net >= e:getMaxHealth() and score > bestScore then
			local hs = e:getSurroundingHexes()
			for i = 1, hs:size() do
				local h = hs:at(i)
				if h:isValid() and battle:isAccessibleForUnit(unit, h)
					and (limit <= 0 or Lib.unitDistance(unit, h) <= limit)
					and not battle:hasPenaltyOnLine(from, h, not self.isWallPassable, not self.isMoatPassable) then
					bestHex, bestEnemy, bestScore = h, e, score
					break
				end
			end
		end
	end
	return bestHex, bestEnemy
end

function Script:adjustTargetTypes(mechanics, types)
	if aiSingle(mechanics) then
		if #types == 0 then return types end
		if types[1] ~= ENUM.AimType.creature then return {} end
		return { ENUM.AimType.creature }
	end
	return Base.adjustTargetTypes(self, mechanics, types)
end

function Script:describeTargetStep()
	return nil
end

function Script:applicableTarget(mechanics, problem, target)
	if aiSingle(mechanics) and #target <= 1 then
		if not Base.applicableTarget(self, mechanics, problem, target) then return false end
		if self:aiDestination(mechanics, target[1] and target[1].unit) == nil then
			problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
			return false
		end
		return true
	end
	if not Base.applicableTarget(self, mechanics, problem, target) then return false end
	if #target <= 1 then return true end
	local unit, toHex = target[1].unit, target[2].hex
	if unit == nil or toHex == nil then return false end
	local limit = Lib.pick(self.maxDistance, Lib.level(mechanics))
	if limit > 0 and Lib.unitDistance(unit, toHex) > limit then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
		return false
	end
	return true
end

function Script:apply(mechanics, server, target)
	local unit = target[1] and target[1].unit
	if #target < 2 and aiSingle(mechanics) then
		local hex, enemy = self:aiDestination(mechanics, unit)
		if hex == nil then return end
		if Proxy.trial(server) then
			Proxy.damage(server, mechanics:getBattle(), enemy, netGain(unit, enemy))
			return
		end
		server:moveUnit(mechanics:getBattle(), unit, hex, true)
	else
		Base.apply(self, mechanics, server, target)
	end
	if unit == nil or not unit:isAlive() then return end
	local bonus = Lib.pick(self.speedBonus, Lib.level(mechanics))
	if bonus ~= 0 then
		server:addUnitBonus(mechanics:getBattle(), unit, {
			type = "STACKS_SPEED",
			val = bonus,
			duration = ENUM.BonusDuration.nTurns,
			turns = self.speedTurns or 2,
			sourceType = ENUM.BonusSource.spellEffect, sourceSecondaryID = mechanics:getEffectLevel(),
			sourceID = mechanics:getSpell():getJsonKey(),
			stacking = "h7TeleportSpeed"
		}, false)
	end
end

return Script
