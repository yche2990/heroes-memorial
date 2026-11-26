local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local S = require("lib/h6SpLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Spirit Devour (H6 Namtaru): drains an adjacent friendly minion (Ghosts) dry: it dies entirely and the caster regains the drained health x pct% (no resurrection).
--- Parameters: minion (list of full creature names), pct, key, animation, sound

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	if caster == nil or unit == nil or not unit:isAlive() or unit:unitID() == caster:unitID() then return false end
	if mechanics:getBattle():isHostile(caster, unit) or not L.adjacent(caster, unit) then return false end
	for _, id in ipairs(self.minion or {}) do if unit:getCreature():getJsonKey() == id then return true end end
	return false
end

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	local ok = caster ~= nil and caster:getAvailableHealth() < L.initialHealth(caster)
		and #mechanics:getBattle():getUnitsIf(function(u) return self:isValidTarget(mechanics, u) end) > 0
	if not ok then problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget) end
	return ok
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
	if caster == nil or main == nil then return end
	-- 2026-11-08 (AI skill fixes): the AI simulation does not really drain; eating its own Ghosts counts as "harming its own side" in the estimate, an automatic veto, so it was never cast.
	-- It is now booked by net value: the health the Namtaru can actually regain (drained x pct%, not more than she has lost) converted to value, minus the value of the Ghost stack;
	-- booked only if the net value is positive (Proxy.creditSide, on the enemy stack with the most health), and not more than the value of one of her normal attacks (so it is not cast every round);
	-- and more than half of the regained health must be useful (not cast when she has lost little, so the Ghosts are not wasted). Real casting (below) is unchanged.
	if Proxy.trial(server) then
		local drained = main:getAvailableHealth()
		local heal = math.floor(drained * (self.pct or 300) / 100)
		local lost = L.initialHealth(caster) - caster:getAvailableHealth()
		local used = math.min(heal, lost)
		if used > 0 and used * 2 >= heal then
			local gain = used / math.max(1, caster:getMaxHealth()) * Proxy.value(caster)
			local cost = drained / math.max(1, main:getMaxHealth()) * Proxy.value(main)
			local net = math.min(gain - cost, S.attackValue(battle, caster))
			if net > 0 then Proxy.creditSide(server, battle, caster:getSide(), net) end
		end
		L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
		return
	end
	local drained = main:getAvailableHealth()
	L.rawHit(server, battle, main, drained, self.animation, self.sound)
	local healed = server:healUnit(battle, caster, math.floor(drained * (self.pct or 300) / 100), ENUM.HealLevel.heal, ENUM.HealPower.permanent)
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.log(server, battle, "H6_DEVOUR_SPIRIT_H6C", 1, { L.name(caster) }, { healed or 0 })
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

--- 2026-11-07: the engine only gives spell effect scripts hexes as targets, so the stack on the hex is attached (see h6Lib.unitTarget)
function Script:transformTarget(mechanics, aimPoint, spellTarget) return L.unitTarget(mechanics, spellTarget) end

--- Cursor and status bar text while choosing a target: cursor combatSacrifice, "Drain X" (drains an adjacent ghost stack to heal) instead of "Cast".
--- The text is in the spell parameter hoverText (one %s = the stack pointed at); spells without hoverText use the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	if #partialTarget ~= 0 or self.hoverText == nil or hoveredHex == nil or not hoveredHex:isValid() then return nil end
	local battle = mechanics:getBattle()
	local unit = battle:getUnitByPos(hoveredHex, true) or battle:getUnitByPos(hoveredHex, false)
	local text = { append = { self.hoverText } }
	if unit ~= nil then
		text.replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) }
	end
	return {
		cursor = "combatSacrifice",
		text = text,
		blockedText = { append = { "core.genrltxt.23" } }, -- Select a target for the spell (as the engine default)
		healthGainTextID = "vcmi.battleWindow.healValuePreview"
	}
end

--- Hover estimate: same formula as apply. Drains this ghost stack (all of it dies); the caster heals drained health x pct% (heal level heal, no resurrection).
--- Shows the health actually restored to the caster (the drained ghosts are not counted)
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local caster = mechanics:getUnitCaster()
		local first = self:filterTarget(mechanics, spellTarget or {})[1]
		local main = first and first.unit
		if caster == nil or main == nil then return zero end
		local amount = math.floor(main:getAvailableHealth() * (self.pct or 300) / 100)
		if amount <= 0 then return zero end
		local healed = caster:copy():heal(amount, ENUM.HealLevel.heal, ENUM.HealPower.permanent)
		return { hpDelta = healed or 0, unitsDelta = 0 }
	end)
	if ok and result then return result end
	return zero
end

return Script
