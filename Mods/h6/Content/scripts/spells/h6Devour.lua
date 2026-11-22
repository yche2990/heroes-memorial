local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Devour (H6 Abyssal Worm): swallows an adjacent single-hex enemy, which cannot act or be attacked (H6_DEVOURED_H6C, NOT_ACTIVE, INVINCIBLE)
--- and takes digestion damage at the start of each round (settled by combat/h6BossWorm); it is spat out when the Worm dies; other single-hex enemies next to the Worm are pushed back 1 hex.
--- Only one stack can be swallowed at a time. Parameters: key, digest (only for the AI simulation estimate; added to the spell config and schema in review B11, 2026-11-08;
--- must match digest of the boss creature h6BossWorm, the actual digestion damage is settled by combat/h6BossWorm with its own parameters), animation, sound

local function busy(battle, caster)
	local id = caster:unitID() + 1
	return #battle:getUnitsIf(function(u)
		return u:isAlive() and u:getBonuses({ type = "H6_DEVOURED_H6C" }):filter(function(b) return b:getVal() == id end):size() > 0
	end) > 0
end

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	if caster == nil or not L.real(unit) or unit:isInvincible() then return false end
	return mechanics:getBattle():isHostile(caster, unit) and unit:getHexes():size() == 1 and L.adjacent(caster, unit)
end

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	local battle = mechanics:getBattle()
	if caster == nil or busy(battle, caster) or #battle:getUnitsIf(function(u) return self:isValidTarget(mechanics, u) end) == 0 then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget); return false
	end
	return true
end

function Script:applicableTarget(mechanics, problem, target)
	for _, dest in ipairs(target) do if dest.unit and self:isValidTarget(mechanics, dest.unit) then return true end end
	problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget); return false
end

function Script:filterTarget(mechanics, target)
	local out = {}
	for _, dest in ipairs(target) do if dest.unit and self:isValidTarget(mechanics, dest.unit) then out[#out + 1] = dest end end
	return out
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	local main = target[1] and target[1].unit
	if caster == nil or main == nil or not main:isAlive() then return end
	local src = caster:getCreature():getJsonKey()
	-- Round 419: the AI simulation does not really swallow (the swallowed stack becomes invincible, which would look like a buff in the estimate); proxy damage is reported instead: three rounds of digestion + the lost action
	if Proxy.trial(server) then
		Proxy.damage(server, battle, main, (self.digest or 600) * 3 + main:getAvailableHealth() * Proxy.controlRatio(3, 1))
		L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
		return
	end
	L.show(server, battle, { main }, self.animation, self.sound)
	for _, t in ipairs({ { "H6_DEVOURED_H6C", caster:unitID() + 1 }, { "NOT_ACTIVE", 0 }, { "INVINCIBLE", 0 } }) do
		server:addUnitBonus(battle, main, { type = t[1], val = t[2], duration = ENUM.BonusDuration.oneBattle,
			sourceType = ENUM.BonusSource.other, sourceID = src, stacking = "h6Devour" }, true)
	end
	for _, u in ipairs(L.around(battle, caster, function(u) return battle:isHostile(caster, u) and u:unitID() ~= main:unitID() end)) do
		L.knock(server, battle, caster, u, 1)
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.log(server, battle, "H6_DEVOURED_H6C", 1, { L.name(caster), L.name(main) }, {})
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

--- 2026-11-07: the engine only gives spell effect scripts hexes as targets, so the stack on the hex is attached (see h6Lib.unitTarget)
function Script:transformTarget(mechanics, aimPoint, spellTarget) return L.unitTarget(mechanics, spellTarget) end

return Script
