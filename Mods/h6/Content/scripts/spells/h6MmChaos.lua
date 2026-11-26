--- Mark of Chaos (H6 Memorial Sanctum, Inferno Warcry): the next count attacks (counterattacks included) the target enemy receives are certain critical hits: +100% damage, and no Luck is rolled for them.
--- How it works: the target gets combat/h6MmChaosHit and a visible "Mark of Chaos" status (val = remaining hits). Parameters: count, animation, sound
local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local M = require("lib/h6MmLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:isValidTarget(mechanics, unit)
	return M.real(unit) and unit:getSide() ~= mechanics:getCasterSide()
end
function Script:isReceptive(mechanics, unit) return M.receptive(mechanics, unit) end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local u = target[1] and target[1].unit
	if u == nil or not u:isAlive() then return end
	local n = self.count or 5
	if Proxy.trial(server) then
		Proxy.buff(server, battle, u, { type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll", val = -60, turns = 2 })
		return
	end
	L.show(server, battle, { u }, self.animation, self.sound)
	L.removeByStacking(server, battle, u, "COMBAT_EVENT_TRIGGER", "h6MmChaos")
	L.removeByStacking(server, battle, u, "H6_MM_CHAOS_H6C", "h6MmChaos")
	M.addOther(server, battle, u, { type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h6:h6MmChaosHit", val = 0, hidden = true, stacking = "h6MmChaos" })
	M.addOther(server, battle, u, { type = "H6_MM_CHAOS_H6C", val = n, stacking = "h6MmChaos", icon = "h6/abilities/mm_MarkOfChaos" })
	server:refreshBattleUnits(battle)
end
if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Mark of Chaos (H6)
--- The text copies the engine default (BattleSpellMechanics::describeTargetStep): on a unit "Cast X on Y" (core.genrltxt.27, Y singular or plural by count),
--- when it cannot be cast "Select a target for the spell" (23); on a hex "Cast X" (26); damage and healing estimates are appended as usual.
--- Steps (or modes) not listed in the table return nil and fall back to the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	local CURSORS = { [1] = "kadCursorCurse" } -- step number -> cursor
	local AIM = { ["*"] = "creature" } -- target type of the first step (spell targetType)
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
	return {
		cursor = cursor,
		text = { append = { "core.genrltxt.26" }, replaceStrings = { spellName } }, -- Cast %s
		healthGainTextID = "vcmi.battleWindow.healValuePreview"
	}
end

return Script
