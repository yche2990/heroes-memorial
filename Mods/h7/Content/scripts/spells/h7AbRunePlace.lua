local Base = require("spells/spellEffect")
local L = require("combat/h7dLib")
local Z = require("combat/h7dZones")
local Proxy = require("lib/kadAiProxy")   -- AI simulation branch (ai-skills-design, as round 352)
local AI = require("spells/h7AiTrial")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Active abilities of the H7 Rune of Balance (Rune Cleric, Rune Hierarch):
---   mode = "place"   Rune of Balance: moves the side's Rune of Balance to the target hex (places one if the side has none; cannot be placed again after the rune was used up by "Rune Teleport"). Unlimited
---   mode = "cleanse" Rune of Balance: Dispel: once per battle (shared by the side), dispels buffs on enemies and debuffs on allies in the rune aura.
---                    Must click a hex inside the aura
---   mode = "teleport" Rune Teleport (Rune Hierarch): teleports into its side's rune aura (onto the free hex in the aura nearest the clicked one if that hex is occupied),
---                    the rune disappears and the aura goes with the stack (H7_RUNE_CARRY_H7C) until the battle ends. Unlimited (in practice usable once: the rune is gone)
--- All refund the cast (L.refundCast); "Dispel" is blocked after use by the hidden mark H7_RUNE_CLEANSED_H7C.
--- Parameter: mode

local CLEANSED = "H7_RUNE_CLEANSED_H7C"

local function caster(mechanics)
	return mechanics:getUnitCaster()
end

function Script:describeTargetStep(mechanics, target)
	return nil
end

function Script:applicableGeneral(mechanics, problem)
	local c = caster(mechanics)
	local battle = mechanics:getBattle()
	if c == nil then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	local side = c:getSide()
	local hasRune = Z.runeObstacle(battle, side) ~= nil
	local ok = true
	if self.mode == "place" then
		ok = hasRune or not c:hasBonuses({ type = Z.GONE })
	elseif self.mode == "cleanse" then
		ok = hasRune and not c:hasBonuses({ type = CLEANSED })
	elseif self.mode == "teleport" then
		ok = hasRune and not c:hasBonuses({ type = Z.CARRY })
	end
	if not ok then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

local function destHex(target)
	local d = target and target[1]
	if d == nil or d.hex == nil or not d.hex:isValid() then return nil end
	return d.hex
end

--- Landing spot of Rune Teleport: the clicked hex if it can stand there, otherwise the free hex in the aura nearest to it
local function landing(battle, area, hex)
	if area == nil then return nil end
	if area[L.hexIndex(hex)] ~= nil and Z.freeHex(battle, hex) then return hex end
	if area[L.hexIndex(hex)] == nil then return nil end
	local best, bestD = nil, 1000
	for _, h in pairs(area) do
		if Z.freeHex(battle, h) then
			local d = L.hexDistance(h, hex)
			if d < bestD then best, bestD = h, d end
		end
	end
	return best
end

--- AI single step (ai-skills-design 3.4): BattleAI only picks spots among the hexes of stacks and one random hex next to them, so it almost never hits the rune aura;
--- when the AI's casting side clicks outside the aura, the spot becomes the free hex in the aura nearest the rune. Players still have to click inside the aura
local function teleportLanding(mechanics, battle, cur, hex)
	local area = L.around(battle, { cur })
	local land = landing(battle, area, hex)
	if land == nil and area[L.hexIndex(hex)] == nil and Proxy.aiCaster(mechanics) then
		local bestD = 1000
		for _, h in pairs(area) do
			if Z.freeHex(battle, h) and L.hexDistance(h, cur) < bestD then land, bestD = h, L.hexDistance(h, cur) end
		end
	end
	return land
end

function Script:applicableTarget(mechanics, problem, target)
	local battle = mechanics:getBattle()
	local c = caster(mechanics)
	local hex = destHex(target)
	if c == nil or hex == nil then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
		return false
	end
	local side = c:getSide()
	local ok
	if self.mode == "place" then
		local cur = Z.runeCenter(battle, side)
		ok = Z.placeable(battle, hex) and (cur == nil or L.hexIndex(cur) ~= L.hexIndex(hex))
	elseif self.mode == "cleanse" then
		local cur = Z.runeCenter(battle, side)
		ok = cur ~= nil and L.hexDistance(cur, hex) <= 1
	else
		local cur = Z.runeCenter(battle, side)
		ok = cur ~= nil and teleportLanding(mechanics, battle, cur, hex) ~= nil
	end
	if not ok then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
		return false
	end
	return true
end

function Script:adjustAffectedHexes(mechanics, hexes, spellTarget)
	local battle = mechanics:getBattle()
	local c = caster(mechanics)
	local hex = destHex(spellTarget)
	if c == nil or hex == nil then return hexes end
	local area
	if self.mode == "place" then
		area = L.around(battle, { hex })
	elseif self.mode == "cleanse" then
		local cur = Z.runeCenter(battle, c:getSide())
		area = cur and L.around(battle, { cur }) or {}
	else
		area = { [L.hexIndex(hex)] = hex }
	end
	for _, h in pairs(area) do hexes:insert(h) end
	return hexes
end

local function spellOf(b)
	local id = b:getSourceID()
	if id == nil or id == "" then return nil end
	local ok, s = pcall(function() return LIBRARY:getSpellByName(id) end)
	if ok then return s end
	return nil
end

local function cleanseUnit(server, battle, u, removePositive)
	local list = u:getBonuses({ sourceType = ENUM.BonusSource.spellEffect }):filter(function(b)
		local s = spellOf(b)
		if s == nil then return false end
		if removePositive then return s:isPositive() end
		return s:isNegative()
	end)
	if list:size() == 0 then return false end
	server:removeUnitBonuses(battle, u, list)
	return true
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local c = caster(mechanics)
	if c == nil or not c:isAlive() then return end
	local hex = destHex(target)
	if hex == nil then return end
	local side = c:getSide()
	local describe = server:describeChanges()

	if self.mode == "place" then
		-- Round 403: AI simulation branch (moving the rune): the rune's position is worth 0 in the AI's estimate, so the extra value of damage sharing in the new aura is reported (h7AiTrial.runePlace)
		if Proxy.trial(server) then
			local cur, new = {}, { hex }
			local rc = Z.runeCenter(battle, side)
			if rc ~= nil then cur[#cur + 1] = rc end
			for _, u in ipairs(Z.carriers(battle, side)) do
				local hs = u:getHexes()
				for i = 1, hs:size() do cur[#cur + 1] = hs:at(i); new[#new + 1] = hs:at(i) end
			end
			AI.runePlace(server, battle, c, new, cur)
			return
		end
		if Z.placeRune(server, battle, side, hex) and describe then
			server:showBattleAnimation(battle, { { hex = hex } }, "h7/fx/h7dRuneCast", "", 1.0, true)
			server:refreshBattleUnits(battle)
			L.log(server, battle, 4, { L.name(c) }, {})
		end
	elseif self.mode == "cleanse" then
		local area = Z.runeArea(battle, side)
		local n = 0
		local hit = {}
		for _, u in ipairs(battle:getUnitsIf(function(x) return L.isReal(x) and Z.inArea(x, area) end)) do
			if cleanseUnit(server, battle, u, u:getSide() ~= side) then
				n = n + 1
				hit[#hit + 1] = { unit = u }
			end
		end
		for _, u in ipairs(battle:getUnitsIf(function(x) return x:getSide() == side and x:isAlive() end)) do
			L.setMark(server, battle, u, CLEANSED, 1, nil, "h7RuneCleansed", true)
		end
		if describe then
			local cur = Z.runeCenter(battle, side)
			if cur then server:showBattleAnimation(battle, { { hex = cur } }, "h7/fx/h7dRuneCast", "", 1.0, true) end
			if #hit > 0 then server:showBattleAnimation(battle, hit, "h7/fx/h7dDispel", "", 1.0, true) end
			server:refreshBattleUnits(battle)
			L.log(server, battle, 5, {}, { n })
		end
	elseif self.mode == "teleport" then
		local cur = Z.runeCenter(battle, side)
		if cur == nil then return end
		local land = teleportLanding(mechanics, battle, cur, hex)
		if land == nil then return end
		-- AI simulation branch (Rune Teleport): position is worth 0 in the AI's estimate, so the extra attack / the shot after escaping is reported instead
		if Proxy.trial(server) then
			AI.runeTeleport(server, battle, c, land)
			return
		end
		local moved = pcall(function() server:moveUnit(battle, c, land, true) end)
		if not moved then return end
		Z.removeRune(server, battle, side)
		L.setMark(server, battle, c, Z.CARRY, 1, nil, "h7RuneCarry", false, { icon = "h7/abilities/h7RuneTeleport" })
		for _, u in ipairs(battle:getUnitsIf(function(x) return x:getSide() == side and x:isAlive() end)) do
			L.setMark(server, battle, u, Z.GONE, 1, nil, "h7RuneGone", true)
		end
		if describe then
			server:showBattleAnimation(battle, { { unit = c } }, "h7/fx/h7dRuneCast", "", 1.0, true)
			server:refreshBattleUnits(battle)
			L.log(server, battle, 6, { L.name(c) }, {})
		end
	end
	L.refundCast(server, battle, c)
end

return Script
