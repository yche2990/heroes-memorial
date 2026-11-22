--- Poison Cloud (H7): cast on a hex of the battlefield; a poison cloud is placed on the target hex and the ring around it (H7's 3x3) for 3 rounds (this round + the next two),
--- and grows one ring outward at the start of each later round (settled by combat/h7PoisonCloudZone).
--- At cast time stacks in the cloud take base + perPower x Spell Power Earth damage (h5SpellLib formula, adjusted by the spell damage flow);
--- Undead, non-living (constructs), mechanical stacks and war machines are immune. Each stack takes cloud damage at most once per round.
--- Parameters: base, perPower (4 numbers), zoneScript (full name of the area script), zoneAnimation (persistent mist animation per hex), hitAnimation, hitSound, turns
local Base = require("spells/spellEffect")
local Lib = require("spells/h5SpellLib")
local E = require("heroes-memorial.h7:combat/h7EarthLib")
local BattleLog = require("battleLog")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

Script.IMMUNE = { "UNDEAD", "NON_LIVING", "MECHANICAL", "SIEGE_WEAPON" }
Script.HIT = "h7PoisonCloudHit"

local function areaHexes(battle, center, rMin, rMax)
	local out = {}
	for _, h in pairs(E.hexTable(battle)) do
		local d = E.hexDistance(h, center)
		if h:isAvailable() and d >= rMin and d <= rMax then out[#out + 1] = h end
	end
	return out
end
Script.areaHexes = areaHexes

function Script.cloudImmune(unit, spellKey)
	if not E.real(unit) or unit:isInvincible() then return true end
	for _, t in ipairs(Script.IMMUNE) do
		if E.has(unit, t) then return true end
	end
	return E.spellImmune(unit, spellKey, 4)
end

function Script.addRing(server, battle, spell, side, center, rMin, rMax, turns, animation)
	for _, h in ipairs(areaHexes(battle, center, rMin, rMax)) do
		server:addObstacle(battle, {
			pos              = h,
			obstacleType     = ENUM.ObstacleType.spellCreated,
			spell            = spell,
			casterSpellPower = 0,
			spellLevel       = 0,
			casterSide       = side,
			turnsRemaining   = turns,
			hidden           = false,
			passable         = true,
			nativeVisible    = true,
			trap             = false,
			removeOnTrigger  = false,
			trigger          = "",
			appearSound      = "",
			-- Round 416: the engine never draws obstacles with an empty appearing animation. Each hex gets only 1 appearing frame (<animation>_in, so the queue waits only 1 frame per hex),
			-- the persistent image loops the last few frames of the full growth (<animation>_loop; the original is a one-time animation growing from nothing), and the fade is left empty = that 1 frame played backwards
			appearAnimation  = (animation and animation ~= "") and (animation .. "_in") or "",
			animation        = (animation and animation ~= "") and (animation .. "_loop") or "",
			removalAnimation = "",
			customSize       = { h },
		})
	end
end

function Script:applicableTarget(mechanics, problem, target)
	local dest = target[1]
	if dest == nil or dest.hex == nil or not dest.hex:isValid() or not dest.hex:isAvailable() then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
		return false
	end
	return true
end

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	local aim = aimPoint[1]
	if aim and aim.hex and aim.hex:isValid() then
		-- The target hex comes first (apply uses it to find the center), followed by the stacks in the cloud that will be hit. H7 audit: BattleAI choosing where to drop a location spell only checks whether this list
		-- contains enemies; it used to return only hexes, so every spot of a negative spell was dropped as "hits no enemy" and the AI never cast it
		local list = { { hex = aim.hex } }
		local spell = mechanics:getSpell()
		local key = spell and spell:getJsonKey() or ""
		for _, u in ipairs(self:victims(mechanics:getBattle(), aim.hex, 1, key)) do
			list[#list + 1] = { unit = u }
		end
		return list
	end
	return spellTarget
end

function Script:adjustAffectedHexes(mechanics, hexes, spellTarget)
	local dest = spellTarget[1]
	if dest and dest.hex and dest.hex:isValid() then
		for _, h in ipairs(areaHexes(mechanics:getBattle(), dest.hex, 0, 1)) do hexes:insert(h) end
	end
	return hexes
end

function Script:victims(battle, center, radius, spellKey)
	return battle:getUnitsIf(function(u)
		return not Script.cloudImmune(u, spellKey) and E.unitHexDistance(u, center) <= radius
	end)
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local dest = target[1]
	if dest == nil or dest.hex == nil or not dest.hex:isValid() then return end
	local center = dest.hex
	local spell = mechanics:getSpell()
	local spellKey = spell:getJsonKey()
	local side = mechanics:getCasterSide()
	local sp, lvl = Lib.power(mechanics), Lib.level(mechanics)
	local raw = Lib.value(self.base, self.perPower, lvl, sp) * Lib.casterDamageFactor(mechanics)

	local list = self:victims(battle, center, 1, spellKey)
	if server:describeChanges() and #list > 0 then
		E.anim(server, battle, list, self.hitAnimation or "", self.hitSound or "", true)
	end
	for _, u in ipairs(list) do
		if E.markVal(u, Script.HIT) == nil then
			local amount = Lib.adjust(mechanics, u, raw)
			if amount > 0 then
				local _, killed = server:damageUnit(battle, u, amount)
				if server:describeChanges() then BattleLog.creaturesPerish(server, battle, u, killed) end
			end
			if u:isAlive() then E.setMark(server, battle, u, Script.HIT, 1, 1) end
		end
	end

	if server:describeChanges() then
		Script.addRing(server, battle, spell, side, center, 0, 1, self.turns or 3, self.zoneAnimation)
		-- H7 audit B1: later rounds' damage is also multiplied by the casting hero's spell bonus (converted to a percentage at cast time from the first stack in the cloud; any enemy stack if the cloud is empty)
		local probe = list[1]
		if probe == nil then
			local enemies = battle:getUnitsIf(function(u) return u:isAlive() and u:getSide() ~= side end)
			probe = enemies[1]
		end
		local bonus = 100
		if probe ~= nil then
			local okB, v = pcall(function() return mechanics:applySpellBonus(1000, probe) end)
			if okB and type(v) == "number" then bonus = math.floor(v / 10 + 0.5) end
		end
		-- H7 audit B3: each cloud has an id (the this-round settled mark is kept per id, so two clouds centered on the same hex count separately)
		local group = server:rngInt(1, 1000000)
		server:addBattleBonus(battle, {
			type       = "COMBAT_EVENT_TRIGGER",
			subtype    = self.zoneScript or "heroes-memorial.h7:h7PoisonCloudZone",
			val        = math.floor(raw),
			duration   = "ONE_BATTLE",
			sourceType = "OTHER",
			hidden     = true,
			stacking   = "h7PoisonCloud" .. E.hexIndex(center) .. "_" .. tostring(group),
			addInfo    = { center = E.hexIndex(center), side = side, spell = spellKey, turns = self.turns or 3, bonus = bonus, group = group,
			               animation = self.zoneAnimation or "", hitAnimation = self.hitAnimation or "", hitSound = self.hitSound or "" }
		})
		server:refreshBattleUnits(battle)
	end
end

function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
