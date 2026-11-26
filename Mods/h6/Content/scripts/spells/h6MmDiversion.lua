--- Diversion (H6 Memorial Sanctum, Dungeon Might): places a shadowsteel decoy on a free hex (creature h6MmDiversionLure: 1 hex, 2 health, never acts, disappears at the start of the next round,
--- handled by its own combat/h6MmLure); enemies within one hex of the decoy are lured and lose their next action (mind-immune stacks are not affected).
--- Parameters: lure (full name of the decoy creature), animation, sound
local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local M = require("lib/h6MmLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:applicableGeneral(mechanics, problem) return true end

function Script:applicableTarget(mechanics, problem, target)
	local dest = target[1]
	local battle = mechanics:getBattle()
	if dest == nil or dest.hex == nil or not dest.hex:isValid() or not dest.hex:isAvailable()
	   or battle:getUnitByPos(dest.hex, true) ~= nil or #(battle:getObstaclesOnPos(dest.hex, false) or {}) > 0 then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
		return false
	end
	return true
end

--- 2026-11-08 (AI skill fixes, review A2): the target hex comes first (apply reads target[1].hex), followed by the enemies within one hex of the decoy that will be lured
--- (mind-immune ones are not affected and not listed), so that the engine and the AI (BattleAI choosing where to drop location spells) can count the affected stacks; it used to return only hexes, so the AI never cast it
local function lured(battle, hex, side)
	return battle:getUnitsIf(function(u)
		if not M.real(u) or u:getSide() == side or u:hasBonuses({ type = "MIND_IMMUNITY" }) then return false end
		local hs = u:getHexes()
		for i = 1, hs:size() do if L.hexDistance(hs:at(i), hex) <= 1 then return true end end
		return false
	end)
end

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	local aim = aimPoint[1]
	if aim == nil or aim.hex == nil or not aim.hex:isValid() then return spellTarget end
	local list = { { hex = aim.hex } }
	for _, u in ipairs(lured(mechanics:getBattle(), aim.hex, mechanics:getCasterSide())) do list[#list + 1] = { unit = u, hex = u:getPosition() } end
	return list
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local dest = target[1]
	if dest == nil or dest.hex == nil then return end
	local side = mechanics:getCasterSide()
	local victims = battle:getUnitsIf(function(u)
		if not M.real(u) or u:getSide() == side then return false end
		local hs = u:getHexes()
		for i = 1, hs:size() do if L.hexDistance(hs:at(i), dest.hex) <= 1 then return true end end
		return false
	end)
	if Proxy.trial(server) then
		-- 2026-11-08: mind-immune stacks are not lured and not reported in the simulation either
		for _, u in ipairs(victims) do
			if not u:hasBonuses({ type = "MIND_IMMUNITY" }) then Proxy.damage(server, battle, u, u:getAvailableHealth() * Proxy.controlRatio(1, 0.5)) end
		end
		return
	end
	local cr = LIBRARY:getCreatureByName(self.lure or "heroes-memorial.h6:h6MmDiversionLure")
	if cr == nil then return end
	local lure = server:addUnit(battle, { count = 1, type = cr, side = side, position = dest.hex, summoned = true })
	if self.animation and server:describeChanges() then
		server:showBattleAnimation(battle, { { hex = dest.hex } }, self.animation, self.sound or "", 1.0, false)
	end
	-- Original: surrounding enemies lose control and walk over to attack the decoy (wasting an action). The engine cannot force a target, and Berserk would attack allies (tested: a Centaur killed a whole stack of Gremlins in one blow),
	-- so instead they simply lose their next action (like Fear: NOT_ACTIVE until their turn comes)
	for _, u in ipairs(victims) do
		if not u:hasBonuses({ type = "MIND_IMMUNITY" }) then
			server:addUnitBonus(battle, u, { type = "NOT_ACTIVE", val = 0, duration = ENUM.BonusDuration.stackGetsTurn + ENUM.BonusDuration.nTurns,
				turns = 1, sourceType = ENUM.BonusSource.other, sourceID = u:getCreature():getJsonKey(), stacking = "h6MmDiversion" }, true)
			server:addUnitBonus(battle, u, { type = "H6_MM_DIVERTED_H6C", val = 1, duration = ENUM.BonusDuration.stackGetsTurn + ENUM.BonusDuration.nTurns,
				turns = 1, sourceType = ENUM.BonusSource.other, sourceID = u:getCreature():getJsonKey(), stacking = "h6MmDiversion",
				icon = "h6/abilities/mm_Diversion" }, true)
			L.log(server, battle, "H6_MM_STATUS_H6C", 7, { L.name(u) }, {})
		end
	end
	server:refreshBattleUnits(battle)
end

--- Cursor and status bar text while choosing a target: cursor kadCursorSummon; places a shadow steel decoy on a free hex.
--- Hexes where it fits show "Cast X" (as the engine default, with the estimate); hexes where it does not fit show the original "X cannot be placed here" (core.genrltxt.181),
--- where the engine default would show no text at all.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	if #partialTarget ~= 0 or hoveredHex == nil or not hoveredHex:isValid() or mechanics:isMassive() then return nil end
	local spellName = mechanics:getSpell():getNameTextID()
	return {
		cursor = "kadCursorSummon",
		text = { append = { "core.genrltxt.26" }, replaceStrings = { spellName } },        -- Cast %s
		blockedText = { append = { "core.genrltxt.181" }, replaceStrings = { spellName } }, -- %s cannot be placed here
		healthGainTextID = "vcmi.battleWindow.healValuePreview"
	}
end

return Script
