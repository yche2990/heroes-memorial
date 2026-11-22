local Base = require("spells/unitEffect")
local L = require("spells/h7abLib")
local Proxy = require("lib/kadAiProxy")   -- AI simulation branch (ai-skills-design, as round 352)
local AI = require("spells/h7AiTrial")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Active abilities of H7 creatures that "charge in, then attack" (batch E), split like the Sanctuary Kappa jump (round 298) into "charge" and "strike":
---   choose an enemy stack; the stack charges in a straight line to the free hex next to it that is nearest to itself (server:moveUnit normal move, the client slides over at once without pathfinding),
---   then it gets the bonuses in bonuses (usually until the end of this attack or the round) and "cannot move again after landing" (Speed -100%, this round).
---   The spell has canCastWithoutSkip and does not end the turn; the player then clicks a target to attack (a normal engine attack). Lua cannot make a stack attack.
---   mode = "feral"   Feral Charge (Silverback Wolf): unlimited distance
---   mode = "pounce"  Mighty Pounce (Ancient Behemoth): distance at most range x Speed (H7 "double movement", leaps over, ignoring obstacles)
--- Parameters: mode, range, bonuses (array of bonus descriptors, fields as in JSON; duration and valueType may be given by name), animation, endSound (on landing), log
--- Uses are handled by spells/h7AbUse in the same spell.

local function speedOf(u)
	local ok, v = pcall(function() return u:getBonusesValue({ type = "STACKS_SPEED" }) end)
	if ok and type(v) == "number" then return v end
	return 0
end

function Script:landing(mechanics, unit)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil then return nil end
	local hex = L.freeHexNextTo(battle, caster, unit, caster:getPosition())
	if hex == nil then return nil end
	if self.mode == "pounce" then
		local limit = (self.range or 2) * math.max(1, speedOf(caster))
		if L.hexDistance(caster:getPosition(), hex) > limit then return nil end
	end
	return hex
end

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	if caster == nil or unit == nil then return false end
	if not unit:isValidTarget(false) or not unit:isAlive() or unit:isGhost() or unit:isTurret() then return false end
	if unit:unitID() == caster:unitID() or not L.isEnemyOf(caster, unit) then return false end
	if L.adjacent(caster, unit) then return false end -- Already adjacent: attack directly
	return self:landing(mechanics, unit) ~= nil
end

function Script:isReceptive(mechanics, unit)
	return true
end

function Script:applicableTarget(mechanics, problem, target)
	for _, dest in ipairs(target) do
		if dest.unit and self:isValidTarget(mechanics, dest.unit) then return true end
	end
	problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
	return false
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	local dest = target[1]
	if caster == nil or not caster:isAlive() or dest == nil or dest.unit == nil then return end
	local unit = dest.unit
	local hex = self:landing(mechanics, unit)
	if hex == nil then return end

	-- AI simulation branch: no charge and no bonuses; the strike after landing is reported instead (attack bonus, no counterattack; Pounce hits all adjacent enemies; Feral Charge pays with Defense dropping to zero)
	if Proxy.trial(server) then
		local plus = 0
		for _, b in ipairs(self.bonuses or {}) do
			if b.type == "PRIMARY_SKILL" and b.subtype == "primarySkill.attack" then plus = plus + (b.val or 0) end
		end
		AI.charge(server, battle, caster, unit, hex, self.mode, plus)
		return
	end

	-- The setting-off sound is the spell's own sounds.cast
	local moved = pcall(function() server:moveUnit(battle, caster, hex, false) end)
	if not moved then pcall(function() server:moveUnit(battle, caster, hex, true) end) end

	for _, b in ipairs(self.bonuses or {}) do
		if b.stacking then L.removeByStacking(server, battle, caster, b.type, b.stacking) end
		L.addBonus(server, battle, caster, b)
	end
	L.removeByStacking(server, battle, caster, "STACKS_SPEED", "h7AbChargeLanded")
	L.addBonus(server, battle, caster, {
		type = "STACKS_SPEED", val = -100, valueType = "percentToAll",
		duration = "nTurns", turns = 1, stacking = "h7AbChargeLanded", hidden = true
	})
	L.markNoSkip(server, battle, caster)

	if server:describeChanges() then
		if self.animation or self.endSound then
			server:showBattleAnimation(battle, { { unit = caster } }, self.animation or "h7/fx/h7abBlank", self.endSound or "", 1.0, true)
		end
		server:refreshBattleUnits(battle)
		if self.log then L.log(server, battle, self.log, { L.name(caster), L.name(unit) }, {}) end
	end
end

function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
