--- Sacrifice (H6 class ability): first choose the friendly stack to protect, then the friendly stack to sacrifice. For the next turns rounds (or until the sacrificer is wiped out),
--- damage taken by the protected stack is taken by the sacrificer instead, reduced by reduce% (settled by combat/h6SpSacrificeLink). Parameters: turns, reduce
local Base = require("spells/unitEffect")
local S = require("lib/h6SpLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:adjustTargetTypes(mechanics, types)
	if #types == 0 then return types end
	if types[1] ~= ENUM.AimType.creature then return {} end
	if #types == 1 then return { ENUM.AimType.creature, ENUM.AimType.creature } end
	if types[2] ~= ENUM.AimType.creature then return {} end
	return types
end

local function ownAlive(mechanics, u)
	return u ~= nil and u:isAlive() and not u:isTurret() and u:getSide() == mechanics:getCasterSide()
		and not u:hasBonuses({ type = "SIEGE_WEAPON" }) and not u:isClone()
end

--- The first target is the protected stack, the second the sacrificer (two-step choice as in the engine's Sacrifice spell, sacrifice.lua)
function Script:applicableGeneral(mechanics, problem)
	local n = #mechanics:getBattle():getUnitsIf(function(u) return ownAlive(mechanics, u) end)
	if n >= 2 then return true end
	problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
	return false
end

function Script:applicableTarget(mechanics, problem, target)
	if #target == 0 then return false end
	local ward = target[1].unit
	if not ownAlive(mechanics, ward) then return false end
	if #target == 1 then return true end
	local victim = target[2].unit
	if not ownAlive(mechanics, victim) or victim:unitID() == ward:unitID() then return false end
	if mechanics:getBattle():getUnitController(victim) ~= mechanics:getCasterColor() then return false end
	return true
end

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	local filtered = Base.transformTarget(self, mechanics, aimPoint, spellTarget)
	if #filtered == 0 then return {} end
	local result = { filtered[1] }
	if #aimPoint >= 2 then
		local dest = aimPoint[2]
		result[2] = { unit = dest.unit or mechanics:getBattle():getUnitByPos(dest.hex, true), hex = dest.hex }
	end
	return result
end

function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	if #partialTarget ~= 1 then return nil end
	return { cursor = "combatSacrifice", text = { append = { "core.genrltxt.543" } }, blockedText = { append = { "core.genrltxt.543" } } }
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	if #target ~= 2 then return end
	local ward = target[1].unit
	local victim = target[2].unit
	if victim == nil or ward == nil or not victim:isAlive() or not ward:isAlive() then return end
	if Proxy.trial(server) then
		Proxy.buff(server, battle, ward, { type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll", val = 50, turns = 2 })
		return
	end
	local key = mechanics:getSpell():getJsonKey()
	local turns = math.max(1, S.pick(mechanics, self.turns) or 2)
	local d = { duration = "N_TURNS", turns = turns, sourceType = "SPELL_EFFECT", sourceID = key, sourceSecondaryID = mechanics:getEffectLevel() }
	local function add(u, t) for k, v in pairs(d) do t[k] = v end; server:addUnitBonus(battle, u, t, false) end
	S.removeSpell(server, battle, ward, key)
	add(ward, { type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h6:h6SpSacrificeLink", val = 0,
		addInfo = { spell = key, partner = victim:unitID(), reduce = S.pick(mechanics, self.reduce) or 33 } })
	add(victim, { type = "STACKS_SPEED", val = 0 })    -- Only so that the sacrificer also shows this spell
	if server:describeChanges() then server:refreshBattleUnits(battle) end
end

return Script
