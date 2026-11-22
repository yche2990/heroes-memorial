local Base = require("combat/combatScript")
local L = require("combat/h7dLib")
local Z = require("combat/h7dZones")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Rune Priest, Rune Patriarch: Rune of Balance
---
--- Original: the player places one Rune of Balance per side during tactics; allies in its 3x3 aura share the damage they take; once per battle the rune itself can dispel
--- buffs on enemies and debuffs on allies in the aura; the rune is a unit that can teleport.
--- In this pack: at battle start (after tactics deployment) the first stack of its side with this ability places the rune one hex in front of itself (under itself if that hex is not possible),
--- one per side; afterwards the active ability "Rune of Balance" can move the rune elsewhere (spells/h7AbRunePlace),
--- and once per battle "Rune of Balance: Dispel" dispels the spells in the aura (spells/h7AbRuneCleanse).
--- Damage sharing is settled by the battle-wide hidden script h7RuneZone (added at battle start).
--- Parameters: none

local function frontHex(unit)
	local pos = unit:getPosition()
	if unit:getSide() == ENUM.BattleSide.attacker then return pos:copyToEast() end
	return pos:copyToWest()
end

function Script:onBattleStart(server, battle, unit, other, payload)
	if not L.isReal(unit) then return end
	Z.ensureCarrier(server, battle, unit, "h7RuneZone", "h7RuneZone")
	local side = unit:getSide()
	if Z.runeObstacle(battle, side) ~= nil or unit:hasBonuses({ type = Z.GONE }) then return end
	local hex = frontHex(unit)
	if not Z.placeable(battle, hex) then hex = unit:getPosition() end
	if not Z.placeable(battle, hex) then return end
	if Z.placeRune(server, battle, side, hex) then
		server:showBattleAnimation(battle, { { hex = hex } }, "h7/fx/h7dRuneCast", "", 1.0, true)
		server:refreshBattleUnits(battle)
		L.log(server, battle, 4, { L.name(unit) }, {})
	end
end

return Script
