local Base = require("spells/spellEffect")
local L = require("combat/h7dLib")
local Proxy = require("lib/kadAiProxy")   -- AI simulation branch (ai-skills-design, as round 352)
local AI = require("spells/h7AiTrial")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Ground area abilities of H7 creatures (batch D):
---   mode = "magma"  Magma Pool (Magma Elemental, cast on itself): its own hexes and the ring around them become a magma pool (obstacle, spell h7AbMagmaPond),
---                   lasting turns rounds (2 = until the end of next round). Stacks entering the pool take Magma Elemental count x per Fire damage
---                   (obstacle trigger spell h7AbMagmaBurn, spells/h7ZoneBurn); stacks still in the pool at the start of each round take the same damage
---                   (battle-wide script h7ZoneTick); at most once per stack per round. Unlimited (cast refunded)
---   mode = "thorns" Thorns (Elder Druid, cast on a hex): thorns grow on this hex, the hex to the east and the two below (2x2) (spell h7AbThorns),
---                   lasting turns rounds. Enemies in the area get Speed -speed (when cast and at the start of each round, until the start of next round);
---                   enemies starting a move from the thorns or ending a move in them take Elder Druid count x per Earth damage (battle-wide script h7ZoneTick),
---                   at most once per round. Once per battle (hidden mark H7_THORNS_USED_H7C)
--- Obstacle images: the anchor is k hexes west of the area's bottom-left hex (h7/fx/h7dMagma_k<k>, h7dThorns_k<k>; larger k leaves more room on the left).
--- Parameters: mode, per, turns, speed, trigger (full name of the trigger spell), tick (full name of the battle-wide script)

local USED = "H7_THORNS_USED_H7C"

local function thornHexes(hex)
	if hex == nil or not hex:isValid() then return nil end
	local e, sw, se = hex:copyToEast(), hex:copyToSouthWest(), hex:copyToSouthEast()
	local list = { hex, e, sw, se }
	for _, h in ipairs(list) do
		if h == nil or not h:isValid() or not h:isAvailable() then return nil end
	end
	return list
end

local function clearGround(battle, hexes)
	for _, h in ipairs(hexes) do
		local blocking = battle:getObstaclesOnPos(h, true)
		if blocking ~= nil and #blocking > 0 then return false end
	end
	return true
end

function Script:applicableGeneral(mechanics, problem)
	local c = mechanics:getUnitCaster()
	if c == nil or (self.mode == "thorns" and c:hasBonuses({ type = USED })) then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:applicableTarget(mechanics, problem, target)
	if self.mode ~= "thorns" then return true end
	local d = target and target[1]
	local hexes = d and thornHexes(d.hex)
	if hexes == nil or not clearGround(mechanics:getBattle(), hexes) then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
		return false
	end
	return true
end

function Script:adjustAffectedHexes(mechanics, hexes, spellTarget)
	if self.mode == "thorns" then
		local d = spellTarget and spellTarget[1]
		local list = d and thornHexes(d.hex)
		for _, h in ipairs(list or {}) do hexes:insert(h) end
	elseif self.mode == "magma" then
		local c = mechanics:getUnitCaster()
		if c ~= nil then
			local hs = c:getHexes()
			local own = {}
			for i = 1, hs:size() do own[#own + 1] = hs:at(i) end
			for _, h in pairs(L.around(mechanics:getBattle(), own)) do hexes:insert(h) end
		end
	end
	return hexes
end

--- Anchor at most maxK hexes to the west (within bounds), returns anchor, k
local function anchorOf(hex, maxK)
	for k = maxK, 0, -1 do
		local a = L.westOf(hex, k)
		if a ~= nil then return a, k end
	end
	return hex, 0
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local c = mechanics:getUnitCaster()
	if c == nil or not c:isAlive() then return end
	-- AI simulation branch (Magma Pool): obstacle damage is worth 0 in the AI's estimate, so the Fire damage of the stacks in the pool over the next two rounds is reported instead (Thorns apply native slow, which the AI already casts; unchanged);
	-- Round 403: the pool also burns itself and adjacent allies, counted into the cost with resistances (h7AiTrial.magma)
	if self.mode == "magma" and Proxy.trial(server) then
		AI.magma(server, battle, c, self.per or 10, mechanics:getSpell())
		return
	end
	local describe = server:describeChanges()
	local count = math.max(1, c:getCount())
	local per = self.per or 10
	local side = mechanics:getCasterSide()
	local spell = mechanics:getSpell()
	local hexes, anchor, k, anim, center

	if self.mode == "magma" then
		local hs = c:getHexes()
		local own, left = {}, nil
		for i = 1, hs:size() do
			local h = hs:at(i)
			own[#own + 1] = h
			if left == nil or h:getX() < left:getX() then left = h end
		end
		hexes = {}
		for _, h in pairs(L.around(battle, own)) do
			if h:isAvailable() then hexes[#hexes + 1] = h end
		end
		anchor, k = anchorOf(left, 2)
		anim = "h7/fx/h7dMagma_k" .. k
	else
		local d = target and target[1]
		center = d and d.hex
		hexes = thornHexes(center)
		if hexes == nil then return end
		anchor, k = anchorOf(hexes[3], 2)
		anim = "h7/fx/h7dThorns_k" .. k
	end

	server:addObstacle(battle, {
		pos              = anchor,
		obstacleType     = ENUM.ObstacleType.spellCreated,
		spell            = spell,
		casterSpellPower = count,
		spellLevel       = 0,
		casterSide       = side,
		minimalDamage    = count * per,
		turnsRemaining   = self.turns or 2,
		hidden           = false,
		passable         = true,
		nativeVisible    = true,
		trap             = false,
		removeOnTrigger  = false,
		trigger          = self.trigger or "",
		appearSound      = "",
		appearAnimation  = anim .. "_in",
		animation        = anim,
		removalAnimation = anim .. "_out",
		customSize       = hexes,
	})

	local info = { anchor = L.hexIndex(anchor), spell = spell:getJsonKey(), power = count, per = per,
		side = side, caster = c:unitID(), speed = self.speed or 0, mode = self.mode }

	if self.mode == "thorns" then
		-- Enemies in the area are slowed at once (until the start of next round)
		local inside = {}
		for _, h in ipairs(hexes) do inside[L.hexIndex(h)] = true end
		for _, u in ipairs(battle:getUnitsIf(function(x) return L.isReal(x) and battle:isHostile(c, x) end)) do
			local hs = u:getHexes()
			for i = 1, hs:size() do
				if inside[L.hexIndex(hs:at(i))] then
					L.setMark(server, battle, u, "STACKS_SPEED", -(self.speed or 3), 1, "h7ThornsSlow", true)
					break
				end
			end
		end
		L.setMark(server, battle, c, USED, 1, nil, "h7ThornsUsed", true)
	else
		L.refundCast(server, battle, c)
	end

	if describe then
		if self.tick then
			server:addBattleBonus(battle, {
				type       = "COMBAT_EVENT_TRIGGER",
				subtype    = self.tick,
				val        = 0,
				duration   = ENUM.BonusDuration.oneBattle,
				sourceType = ENUM.BonusSource.other,
				hidden     = true,
				addInfo    = info
			})
		end
		if self.mode == "magma" then
			server:showBattleAnimation(battle, { { unit = c } }, "h7/fx/h7dMagmaInit", "", 1.0, true)
			L.log(server, battle, 7, { L.name(c) }, {})
		else
			server:showBattleAnimation(battle, { { hex = center } }, "h7/fx/h7dThornsCast", "", 1.0, true)
			L.log(server, battle, 9, { L.name(c) }, {})
		end
		server:refreshBattleUnits(battle)
	end
end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): H7 ground area abilities
--- The text copies the engine default (BattleSpellMechanics::describeTargetStep): on a unit "Cast X on Y" (core.genrltxt.27, Y singular or plural by count),
--- when it cannot be cast "Select a target for the spell" (23); on a hex "Cast X" (26); damage and healing estimates are appended as usual.
--- Steps (or modes) not listed in the table return nil and fall back to the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	local BY_MODE = {
		magma = {},
		thorns = { [1] = "kadCursorPlace" },
	}
	local CURSORS = BY_MODE[self.mode or ""] or {  }
	local AIM = { -- target type of the first step (spell targetType)
		["heroes-memorial.h7:h7AbMagmaPond"] = "nothing",
		["heroes-memorial.h7:h7AbThorns"] = "location",
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
	return {
		cursor = cursor,
		text = { append = { "core.genrltxt.26" }, replaceStrings = { spellName } }, -- Cast %s
		healthGainTextID = "vcmi.battleWindow.healValuePreview"
	}
end

return Script
