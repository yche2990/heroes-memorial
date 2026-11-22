--- Heroes VII creatures and spells (heroes-memorial.h7) batch D: battlefield helpers for the Rune of Balance and Living Shelter. Only loaded with require("combat/h7dZones"), not registered as a script.
---
--- Rune of Balance
---   At most one rune per side: an obstacle of the rune school (occupying only the rune's 1 hex), whose spell is a per-side marker spell
---   h7RuneBalanceMarkA (attacker) / h7RuneBalanceMarkD (defender), so scripts can tell whose rune it is (the obstacle interface does not expose the caster's side).
---   The obstacle's anchor (bottom-left corner) is 1 hex west of the rune hex, image h7/fx/h7dRune_k1 (centered on the rune hex).
---   After the Rune Priest uses "Rune Teleport", the rune disappears; the priest gets H7_RUNE_CARRY_H7C (the aura goes with it) and its side gets H7_RUNE_GONE_H7C (no more runes).
---   Aura range = the rune hex (or the hexes of the stack carrying the aura) and the ring around it.
---   Z.runeCenter(battle, side)          the side's rune hex (nil if none)
---   Z.runeObstacle(battle, side)
---   Z.runeArea(battle, side)            index -> BattleHex
---   Z.inArea(unit, area)                whether one of the stack's hexes is in the range
---   Z.placeRune(server, battle, side, hex)   place (or move) the rune
---   Z.removeRune(server, battle, side)
---   Z.ensureCarrier(server, battle, unit, script, stacking)   add a hidden battle-wide combat event script (not if already present)
--- Living Shelter
---   After a Treant chooses to defend, an obstacle is added on the adjacent free hexes (spell h7AbLivingShelter, hidden, trap type: entering stops movement).
---   The obstacle belongs to the "other side" (casterSide = the opponent) and is hidden from its own side: enemies see it when pathfinding and do not plan routes through it;
---   its own side does not see it and plans as usual; before a friendly stack moves (onBeforeMove of h7LivingShelterZone) the friendly Treants' shelters are removed, and re-added by the current situation after the action.
---   Z.shelterActive(u)                  whether a Treant has Living Shelter (H7_SHELTER_H7C)
---   Z.refreshShelters(server, battle)   remove all shelter obstacles, then re-add them for every Treant with an active shelter
---   Z.removeSideShelters(server, battle, side)  remove the shelter obstacles of side's Treants

local L = require("combat/h7dLib")
local Z = {}

Z.MARK_A = "h7RuneBalanceMarkA"
Z.MARK_D = "h7RuneBalanceMarkD"
Z.CARRY = "H7_RUNE_CARRY_H7C"
Z.GONE = "H7_RUNE_GONE_H7C"
Z.SHELTER = "H7_SHELTER_H7C"
Z.SHELTER_SPELL = "h7AbLivingShelter"

local function markName(side)
	if side == ENUM.BattleSide.attacker then return Z.MARK_A end
	return Z.MARK_D
end

function Z.runeObstacle(battle, side)
	local list = L.obstacles(battle, markName(side))
	return list[1]
end

function Z.runeCenter(battle, side)
	local o = Z.runeObstacle(battle, side)
	if o == nil then return nil end
	local h = o:getPosition():copyToEast()
	if h ~= nil and h:isValid() then return h end
	return nil
end

function Z.carriers(battle, side)
	return battle:getUnitsIf(function(u)
		return u:getSide() == side and L.isReal(u) and u:hasBonuses({ type = Z.CARRY })
	end)
end

function Z.runeArea(battle, side)
	local centers = {}
	local c = Z.runeCenter(battle, side)
	if c ~= nil then centers[#centers + 1] = c end
	for _, u in ipairs(Z.carriers(battle, side)) do
		local hs = u:getHexes()
		for i = 1, hs:size() do centers[#centers + 1] = hs:at(i) end
	end
	if #centers == 0 then return nil end
	return L.around(battle, centers)
end

function Z.inArea(unit, area)
	if area == nil then return false end
	local hs = unit:getHexes()
	for i = 1, hs:size() do
		if area[L.hexIndex(hs:at(i))] ~= nil then return true end
	end
	return false
end

function Z.removeRune(server, battle, side)
	for _, o in ipairs(L.obstacles(battle, markName(side))) do
		server:removeObstacle(battle, o)
	end
end

function Z.placeRune(server, battle, side, hex)
	local anchor = L.westOf(hex, 1)
	local spell = L.spell(markName(side))
	if anchor == nil or spell == nil then return false end
	Z.removeRune(server, battle, side)
	server:addObstacle(battle, {
		pos              = anchor,
		obstacleType     = ENUM.ObstacleType.spellCreated,
		spell            = spell,
		casterSpellPower = 0,
		spellLevel       = 0,
		casterSide       = side,
		turnsRemaining   = -1,
		hidden           = false,
		passable         = true,
		nativeVisible    = true,
		trap             = false,
		removeOnTrigger  = false,
		trigger          = "",
		appearSound      = "",
		appearAnimation  = "h7/fx/h7dRune_k1_in",
		animation        = "h7/fx/h7dRune_k1",
		removalAnimation = "h7/fx/h7dRune_k1_out",
		customSize       = { hex },
	})
	return true
end

--- Hexes where a rune can be placed or a teleport can land: on the battlefield, no living stack, no blocking obstacle
function Z.freeHex(battle, hex)
	if hex == nil or not hex:isValid() or not hex:isAvailable() then return false end
	if battle:getUnitByPos(hex, true) ~= nil then return false end
	local blocking = battle:getObstaclesOnPos(hex, true)
	return blocking == nil or #blocking == 0
end

function Z.placeable(battle, hex)
	if hex == nil or not hex:isValid() or not hex:isAvailable() then return false end
	local blocking = battle:getObstaclesOnPos(hex, true)
	return blocking == nil or #blocking == 0
end

function Z.ensureCarrier(server, battle, unit, script, stacking)
	if L.hasCarrier(unit, script) then return end
	server:addBattleBonus(battle, {
		type       = "COMBAT_EVENT_TRIGGER",
		subtype    = L.MOD .. ":" .. script,
		val        = 0,
		duration   = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.other,
		stacking   = stacking,
		hidden     = true
	})
end

-- Living Shelter ------------------------------------------------------------------

function Z.shelterActive(u)
	return L.isReal(u) and u:hasBonuses({ type = Z.SHELTER })
end

local function adjacentTo(unit, hex)
	return unit:getSurroundingHexes():contains(hex)
end

function Z.removeSideShelters(server, battle, side)
	local list = L.obstacles(battle, Z.SHELTER_SPELL)
	if #list == 0 then return end
	local treants = battle:getUnitsIf(function(u) return u:getSide() == side and Z.shelterActive(u) end)
	for _, o in ipairs(list) do
		local p = o:getPosition()
		for _, t in ipairs(treants) do
			if adjacentTo(t, p) then
				server:removeObstacle(battle, o)
				break
			end
		end
	end
end

function Z.placeShelter(server, battle, treant)
	local spell = L.spell(Z.SHELTER_SPELL)
	if spell == nil then return end
	local around = treant:getSurroundingHexes()
	local hexes = {}
	for i = 1, around:size() do
		local h = around:at(i)
		if Z.freeHex(battle, h) then hexes[#hexes + 1] = h end
	end
	if #hexes == 0 then return end
	server:addObstacle(battle, {
		pos              = hexes[1],
		obstacleType     = ENUM.ObstacleType.spellCreated,
		spell            = spell,
		casterSpellPower = 0,
		spellLevel       = 0,
		casterSide       = L.otherSide(treant:getSide()),
		turnsRemaining   = -1,
		hidden           = true,
		passable         = true,
		nativeVisible    = false,
		trap             = true,
		removeOnTrigger  = false,
		trigger          = "",
		appearSound      = "",
		appearAnimation  = "h7/fx/h7dBlank",
		animation        = "h7/fx/h7dBlank",
		removalAnimation = "h7/fx/h7dBlank",
		customSize       = hexes,
	})
end

function Z.refreshShelters(server, battle)
	local list = L.obstacles(battle, Z.SHELTER_SPELL)
	local treants = battle:getUnitsIf(Z.shelterActive)
	if #list == 0 and #treants == 0 then return end
	for _, o in ipairs(list) do server:removeObstacle(battle, o) end
	for _, t in ipairs(treants) do Z.placeShelter(server, battle, t) end
end

return Z
