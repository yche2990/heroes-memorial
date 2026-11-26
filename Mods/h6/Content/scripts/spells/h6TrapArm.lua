local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Companion effect of the Crippling Trap (H6 Goblin, Goblin Hunter): records this Goblin stack's current trap power (per x count,
--- hidden mark h6TrapPower, the larger one is kept), read by h6TrapHit when the trap is sprung. Also refunds the cast. Parameter: per

--- 2026-11-08 (AI skill fixes): in the AI simulation a trap (hidden obstacle) is worth 0, so the AI never set one. The simulation now reports a proxy value instead:
--- only the one enemy most likely to step on it counts (a trap works once): enemies that cannot fly and are no farther from the trap hex than their Speed + 1;
--- 35% chance if the trap lies between it and our nearest stack (the trap hex is closer to that stack than the enemy is), otherwise 10%;
--- value = chance x (trap damage per x number of Goblins + Speed -3 for two rounds counted as 2% of its remaining health); the largest is reported with Proxy.damage.
--- For neutral location spells like this the AI picks the spot through the engine's defaultLocationSpellHeuristics: for each stack, a random free adjacent hex is a candidate,
--- and free hexes next to enemies facing our side are among them, so with the added value they can be chosen. Real casting (below) is unchanged.
local function trialValue(battle, caster, hex, per)
	local power = per * caster:getCount()
	local best, bestHp = nil, 0
	for _, e in ipairs(battle:getUnitsIf(function(u) return L.hostile(battle, caster, u) and not u:hasBonuses({ type = "FLYING" }) end)) do
		local ok, speed = pcall(function() return e:getBonusesValue({ type = "STACKS_SPEED" }) end)
		if not ok or type(speed) ~= "number" then speed = 0 end
		local d = Proxy.unitDistance(e, hex)
		if d >= 1 and d <= speed + 1 then
			local p = 0.1
			local friend, fd = Proxy.nearestHostile(battle, e)
			if friend ~= nil and Proxy.unitDistance(friend, hex) < fd then p = 0.35 end
			local hp = p * (power + e:getAvailableHealth() * 0.02)
			if hp > bestHp then best, bestHp = e, hp end
		end
	end
	return best, bestHp
end

function Script:apply(mechanics, server, target)
	local caster = mechanics:getUnitCaster()
	if caster == nil then return end
	local battle = mechanics:getBattle()
	if Proxy.trial(server) then
		local hex = target[1] and target[1].hex
		if hex and hex:isValid() then
			local e, hp = trialValue(battle, caster, hex, self.per or 2)
			if e then Proxy.damage(server, battle, e, hp) end
		end
		L.useCast(server, battle, caster, "h6TrapArm", nil)
		return
	end
	local v = (self.per or 2) * caster:getCount()
	L.setMark(server, battle, caster, "h6TrapPower", math.max(v, L.markValue(caster, "h6TrapPower") or 0))
	L.useCast(server, battle, caster, "h6TrapArm", nil)
end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Crippling Trap: sets a trap on a hex
--- The text copies the engine default (BattleSpellMechanics::describeTargetStep): on a unit "Cast X on Y" (core.genrltxt.27, Y singular or plural by count),
--- when it cannot be cast "Select a target for the spell" (23); on a hex "Cast X" (26); with clearAffected at this level a blocked hex shows "X cannot be placed here" (181) without an estimate; damage and healing estimates are appended as usual.
--- Steps (or modes) not listed in the table return nil and fall back to the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	local CURSORS = { [1] = "kadCursorPlace" } -- step number -> cursor
	local AIM = { ["*"] = "location" } -- target type of the first step (spell targetType)
	local CLEAR = { -- clearAffected of the spell at the current level (none/basic/advanced/expert)
		["heroes-memorial.h6:h6AbCripplingTraps"] = { true, true, true, true },
	}
	if hoveredHex == nil or not hoveredHex:isValid() or mechanics:isMassive() then return nil end
	local step = #partialTarget + 1
	local cursor = CURSORS[step]
	if cursor == nil then return nil end
	local spell = mechanics:getSpell()
	if step ~= 1 then return nil end
	local aim = AIM[spell:getJsonKey()] or AIM["*"]
	if aim ~= "creature" and aim ~= "location" then return nil end
	local spellName = spell:getNameTextID()
	if aim == "creature" then
		local battle = mechanics:getBattle()
		local unit = battle:getUnitByPos(hoveredHex, true) or battle:getUnitByPos(hoveredHex, false)
		local names = { spellName }
		if unit ~= nil then table.insert(names, unit:getCreature():getNameTextID(unit:getCount())) end
		return {
			cursor = cursor,
			text = { append = { "core.genrltxt.27" }, replaceStrings = names }, -- Cast %s on %s
			blockedText = { append = { "core.genrltxt.23" } },                  -- Select a target for the spell
			healthGainTextID = "vcmi.battleWindow.healValuePreview"
		}
	end
	local levels = CLEAR[spell:getJsonKey()]
	if step == 1 and levels ~= nil and levels[mechanics:getRangeLevel() + 1] then
		return {
			cursor = cursor,
			text = { append = { "core.genrltxt.26" }, replaceStrings = { spellName } },        -- Cast %s
			blockedText = { append = { "core.genrltxt.181" }, replaceStrings = { spellName } } -- %s cannot be placed here
		}
	end
	return {
		cursor = cursor,
		text = { append = { "core.genrltxt.26" }, replaceStrings = { spellName } }, -- Cast %s
		healthGainTextID = "vcmi.battleWindow.healValuePreview"
	}
end

return Script
