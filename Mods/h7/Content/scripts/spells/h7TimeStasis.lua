--- Time Stasis (H7) (an H7 Prime spell, put in Earth in the memorial): cast on a stack (friend or foe).
--- The target temporarily leaves the battlefield until the start of the next round (written like the leaving of Battle Dive h47Dive: ghost state, no position):
--- it loses its actions not yet taken this round; meanwhile it cannot be attacked, targeted by spells or affected by anything.
--- At the start of the next round combat/h7TimeStasisEnd puts it back where it was (on the nearest free hex if occupied), and it acts as usual.
--- Cannot be cast on a side's last stack on the field (the battle would be judged over); no effect on enemy Prime-immune creatures (H7_PRIME_IMMUNITY_H7C).
--- Parameters: endScript (full name of the script putting it back next round), mark (mark stacking), animation, sound
local Base = require("spells/unitEffect")
local E = require("heroes-memorial.h7:combat/h7EarthLib")
local Proxy = require("lib/kadAiProxy")   -- Round 401: AI simulation branch
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

Script.MARK = "h7Stasis"

local function othersOnSide(battle, unit)
	local side, id = unit:getSide(), unit:unitID()
	local list = battle:getUnitsIf(function(u)
		return u:unitID() ~= id and u:getSide() == side and E.real(u)
			and not E.has(u, "SIEGE_WEAPON") and not E.has(u, "NOT_ACTIVE")
	end)
	return #list
end

function Script:isValidTarget(mechanics, unit)
	if not Base.isValidTarget(self, mechanics, unit) then return false end
	if not E.real(unit) or E.has(unit, "SIEGE_WEAPON") then return false end
	if unit:getSide() ~= mechanics:getCasterSide() and E.primeImmune(unit) then return false end
	if othersOnSide(mechanics:getBattle(), unit) == 0 then return false end
	return true
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	-- Round 401: AI simulation branch. The simulation cannot really remove the stack (on the imaginary battlefield it would have no position and the AI's following hex calculations around it would go out of range),
	-- so an equivalent value is reported: the enemy loses this round's action, counted as 1 round of control = 1/8 of its remaining health; casting on its own side (protection) is worth 0 in the estimate
	if Proxy.trial(server) then
		local side = mechanics:getCasterSide()
		for _, dest in ipairs(target) do
			local unit = dest.unit
			if unit and E.real(unit) and unit:getSide() ~= side then
				Proxy.damage(server, battle, unit, unit:getAvailableHealth() * Proxy.controlRatio(1, 1))
			end
		end
		return
	end
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit and E.real(unit) then
			if server:describeChanges() then
				-- No deferred for this animation before leaving (the stack leaves right after, and queued actions must not outlast its leaving)
				server:showBattleAnimation(battle, { { unit = unit } }, self.animation or "h7/fx/h7eTimeStasis",
					self.sound or "h7/spell_time_stasis_impact.ogg", 1.0)
				server:addBattleBonus(battle, {
					type       = "COMBAT_EVENT_TRIGGER",
					subtype    = self.endScript or "heroes-memorial.h7:h7TimeStasisEnd",
					val        = 0,
					duration   = "ONE_BATTLE",
					sourceType = "OTHER",
					hidden     = true,
					stacking   = "h7TimeStasisEnd",
					addInfo    = { animation = self.animation or "h7/fx/h7eTimeStasis" }
				})
			end
			E.setMark(server, battle, unit, Script.MARK, E.hexIndex(unit:getPosition()) + 1, nil)
			local state = unit:copy()
			state:setGhost(true)
			state:setHadMorale(true)
			state:setPosition(-1)
			server:changeUnit(battle, state)
		end
	end
end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Stasis (H7): the target leaves the battlefield for a while
--- The text copies the engine default (BattleSpellMechanics::describeTargetStep): on a unit "Cast X on Y" (core.genrltxt.27, Y singular or plural by count),
--- when it cannot be cast "Select a target for the spell" (23); on a hex "Cast X" (26); damage and healing estimates are appended as usual.
--- Steps (or modes) not listed in the table return nil and fall back to the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	local CURSORS = { [1] = "kadCursorBanish" } -- step number -> cursor
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
