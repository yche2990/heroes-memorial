--- Abyssal Gate (H6 class ability, approximation): a friendly stack returns to the Abyss for 1 round: it cannot act where it stands and takes no damage, and a gate opens under it;
--- at the start of the next round it comes back with a stack of the same creature as reinforcements next to it (summoned, gone after battle), total health base + per x Spell Power (at least 1).
--- In the original the gate can be attacked 3 times and if destroyed the stack only comes back after battle; VCMI obstacles cannot be attacked, so that is not done.
--- Settled by combat/h6SpAbyssReturn at the start of the next round. Parameters: base, per (4 numbers), animation (gate)
local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local S = require("lib/h6SpLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:isValidTarget(mechanics, unit)
	return unit:isAlive() and not unit:isTurret() and unit:getSide() == mechanics:getCasterSide()
		and not unit:hasBonuses({ type = "SIEGE_WEAPON" }) and not unit:isClone() and not unit:copy():isSummoned()
end

function Script:applicableGeneral(mechanics, problem)
	if #mechanics:getBattle():getUnitsIf(function(u) return self:isValidTarget(mechanics, u) end) == 0 then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local u = target[1] and target[1].unit
	if u == nil or not u:isAlive() then return end
	local hp = math.floor(S.value(mechanics, self.base, self.per))
	if Proxy.trial(server) then
		Proxy.buff(server, battle, u, { type = "STACKS_SPEED", val = 1, turns = 2 })
		return
	end
	local key = mechanics:getSpell():getJsonKey()
	local d = { duration = "N_TURNS", turns = 2, sourceType = "SPELL_EFFECT", sourceID = key, sourceSecondaryID = mechanics:getEffectLevel() }
	local function add(t) for k, v in pairs(d) do t[k] = v end; server:addUnitBonus(battle, u, t, false) end
	add({ type = "NOT_ACTIVE", subtype = key, val = 0 })
	add({ type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll", val = 100 })
	add({ type = "SPELL_DAMAGE_REDUCTION", subtype = "spellSchool.any", val = 100 })
	add({ type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h6:h6SpAbyssReturn", val = 0, addInfo = { spell = key, hp = hp } })
	if self.animation then
		server:addObstacle(battle, {
			pos = u:getPosition(), obstacleType = ENUM.ObstacleType.spellCreated, spell = mechanics:getSpell(),
			casterSpellPower = S.power(mechanics), spellLevel = mechanics:getEffectLevel(), casterSide = mechanics:getCasterSide(),
			turnsRemaining = 1, hidden = false, passable = true, nativeVisible = false, trap = false, removeOnTrigger = false, trigger = "",
			appearSound = "", appearAnimation = "", animation = self.animation, removalAnimation = "", customSize = { u:getPosition() },
		})
	end
	server:refreshBattleUnits(battle)
end
if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

return Script
