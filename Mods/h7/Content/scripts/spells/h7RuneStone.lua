local Base = require("spells/spellEffect")
local L = require("heroes-memorial.h7:combat/h7dLib")
local R = require("heroes-memorial.h7:combat/h7RuneLib")
local BattleLog = require("battleLog")
local Proxy = require("lib/kadAiProxy")   -- AI simulation branch (ai-skills-design, as round 352)
local AI = require("spells/h7AiTrial")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 memorial runes (Rune of Fortune, Rune of Destruction, Rune of Resilience). Parameter mode:
---   "summon"    cast by the hero (Rune school): summons a Rune Stone (creature) on the target free hex, records the hero's Rune school level and hero level,
---               adds the battle-wide aura upkeep script (watchScript, default h7RuneAura) and refreshes the aura at once.
---   "activate"  cast by the Rune Stone itself (once per stone per battle): click any hex in the aura.
---               Fortune: allies in the aura get a shield absorbing 6 + 4 x hero level damage (h7RuneShield, whole battle, the larger value kept);
---               Destruction: enemies in the aura take 18 + 12 x hero level magic damage of no school (only the "all magic" reduction applies; invincible stacks and those absolutely immune to this spell are unaffected);
---               Resilience: all stacks in the aura (friend and foe) are pushed 1 hex away from the Rune Stone (those that cannot move stay; arrow towers and war machines are unaffected).
---   "radiance"  Rune of Radiance (cast by the Rune Stone itself; only usable if the hero's Runelore was Expert at cast time, once per stone per battle): aura effects x3 until the end of the next round.
--- When both Activate and Rune of Radiance are used up, the stone gets NOT_ACTIVE and no longer gets turns.
--- Parameters: mode, creature (summon), shieldBase/shieldPerLevel, damageBase/damagePerLevel, icon (shield icon), watchScript

local ACT_ANIM = { fortune = "h7/fx/h7rActFortune", destruction = "h7/fx/h7rActDestruction", resilience = "h7/fx/h7rActResilience" }
local ACT_SOUND = { fortune = "h7/r_rune_fortune.ogg", destruction = "h7/r_rune_destruction.ogg", resilience = "h7/r_rune_resilience.ogg" }

local function destHex(target)
	local d = target and target[1]
	if d == nil or d.hex == nil or not d.hex:isValid() then return nil end
	return d.hex
end

local function stoneCaster(self, mechanics)
	local c = mechanics:getUnitCaster()
	if c == nil or not R.isStone(c) then return nil end
	if self.mode == "activate" then
		if R.used(c, "h7RuneUsed") then return nil end
	elseif self.mode == "radiance" then
		if R.level(c) < 3 or R.used(c, "h7RuneRadUsed") then return nil end
	end
	return c
end

function Script:applicableGeneral(mechanics, problem)
	if self.mode == "summon" then return true end
	if stoneCaster(self, mechanics) == nil then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:applicableTarget(mechanics, problem, target)
	local hex = destHex(target)
	local battle = mechanics:getBattle()
	local ok = false
	if hex ~= nil then
		if self.mode == "summon" then
			local creature = LIBRARY:getCreatureByName(self.creature)
			ok = creature ~= nil and hex:isAvailable() and battle:getUnitByPos(hex, true) == nil
				and battle:isAccessibleForNewUnit(hex, creature, mechanics:getCasterSide())
		else
			local c = stoneCaster(self, mechanics)
			ok = c ~= nil and L.hexDistance(c:getPosition(), hex) <= R.radius(c)
		end
	end
	if not ok then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
		return false
	end
	return true
end

function Script:adjustAffectedHexes(mechanics, hexes, spellTarget)
	local hex = destHex(spellTarget)
	if hex == nil then return hexes end
	local battle = mechanics:getBattle()
	local center, radius = hex, 1
	if self.mode ~= "summon" then
		local c = mechanics:getUnitCaster()
		if c ~= nil and R.isStone(c) then center, radius = c:getPosition(), R.radius(c) end
	else
		local lvl = math.max(0, math.min(3, mechanics:getEffectLevel()))
		if lvl >= 3 then radius = 2 end
	end
	for _, h in pairs(L.hexTable(battle)) do
		if L.hexDistance(h, center) <= radius then hexes:insert(h) end
	end
	return hexes
end

-- ------------------------------------------------------------------ Summon

local function heroLevel(mechanics)
	local h = mechanics:getHeroCaster()
	if h == nil then return 1 end
	local ok, v = pcall(function() return h:getLevel() end)
	if ok and type(v) == "number" and v > 0 then return v end
	return 1
end

function Script:summon(mechanics, server, battle, hex)
	local creature = LIBRARY:getCreatureByName(self.creature)
	if creature == nil then return end
	local side = mechanics:getCasterSide()
	-- Only one stone of each rune per side (Yu's decision 2026-11-01, so they do not fill the battlefield together with battlefield sigils): an existing one of the same kind is moved to the new position,
	-- keeping whether Activate and Radiance were used (recasting does not grant an extra activation)
	local key = creature:getJsonKey()
	local old = battle:getUnitsIf(function(u)
		return u:isAlive() and u:getSide() == side and u:getCreature():getJsonKey() == key
	end)[1]
	local stone
	if old ~= nil then
		server:moveUnit(battle, old, hex, true)
		stone = old
	else
		stone = server:addUnit(battle, {
			count = 1,
			type = creature,
			side = side,
			position = hex,
			summoned = true
		})
	end
	if stone == nil then return end
	local lvl = math.max(0, math.min(3, mechanics:getEffectLevel()))
	L.setMark(server, battle, stone, R.STONE, lvl, nil, "h7RuneLevel", true)
	L.setMark(server, battle, stone, R.STONE, heroLevel(mechanics), nil, "h7RuneHero", true)
	if server:describeChanges() then
		local watch = self.watchScript or "h7RuneAura"
		local any = battle:getUnitsIf(function(u) return u:isAlive() end)
		if not (any[1] and L.hasCarrier(any[1], watch)) then
			server:addBattleBonus(battle, {
				type       = "COMBAT_EVENT_TRIGGER",
				subtype    = L.MOD .. ":" .. watch,
				val        = 0,
				duration   = ENUM.BonusDuration.oneBattle,
				sourceType = ENUM.BonusSource.other,
				stacking   = "h7RuneAuraWatch",
				hidden     = true
			})
		end
	end
	R.refresh(server, battle)
	if server:describeChanges() then
		server:refreshBattleUnits(battle)
	end
end

-- ------------------------------------------------------------------ Activate

local DIRS = { "copyToNorthWest", "copyToNorthEast", "copyToEast", "copyToSouthEast", "copyToSouthWest", "copyToWest" }

local function toList(arr)
	local out = {}
	for i = 1, arr:size() do out[#out + 1] = arr:at(i) end
	return out
end

local function minDist(hexes, c)
	local best = 1000
	for _, h in ipairs(hexes) do
		local d = L.hexDistance(h, c)
		if d < best then best = d end
	end
	return best
end

local function sumDist(hexes, c)
	local s = 0
	for _, h in ipairs(hexes) do s = s + L.hexDistance(h, c) end
	return s
end

local function immovable(u)
	return u:isTurret() or u:hasBonuses({ type = "SIEGE_WEAPON" })
end

--- Landing spot for a 1-hex push outward (nil if none): every hex moves one step in the same direction, the nearest distance to the center grows by 1, and the direction with the largest total distance is chosen
local function pushDest(battle, u, c)
	local pos = u:getPosition()
	local hexes = toList(u:getHexes())
	local d0 = minDist(hexes, c)
	local best, bestScore = nil, -1
	for _, dir in ipairs(DIRS) do
		local np = pos[dir](pos)
		if np:isValid() and np:isAvailable() then
			local nh, ok = {}, true
			for i, h in ipairs(hexes) do
				local n = h[dir](h)
				if not n:isValid() or not n:isAvailable() then ok = false break end
				nh[i] = n
			end
			if ok and minDist(nh, c) == d0 + 1 and battle:isAccessibleForUnit(u, np)
				and not battle:hasPenaltyOnLine(pos, np, true, false) then
				local score = sumDist(nh, c)
				if score > bestScore then best, bestScore = np, score end
			end
		end
	end
	return best
end

function Script:activate(mechanics, server, battle, stone)
	local info = R.info(stone)
	local side = stone:getSide()
	local describe = server:describeChanges()
	local hl = R.heroLevel(stone)
	local center = stone:getPosition()
	if describe then
		server:showBattleAnimation(battle, { { hex = center } }, ACT_ANIM[info.kind], ACT_SOUND[info.kind], 1.0, true)
	end
	if info.kind == "fortune" then
		local amount = (self.shieldBase or 6) + (self.shieldPerLevel or 4) * hl
		local list = R.unitsInAura(battle, stone, function(u) return u:getSide() == side and L.isReal(u) end)
		for _, u in ipairs(list) do
			local cur = 0
			local own = u:getBonuses({ type = "COMBAT_EVENT_TRIGGER" }):filter(function(b) return b:getStacking() == "h7RuneShield" end)
			for i = 1, own:size() do cur = math.max(cur, own:getBonus(i):getVal()) end
			if amount > cur then
				if own:size() > 0 then Proxy.removeExact(server, battle, u, own) end
				server:addUnitBonus(battle, u, {
					type = "COMBAT_EVENT_TRIGGER",
					subtype = "heroes-memorial.h7:h7RuneShield",
					val = amount,
					duration = ENUM.BonusDuration.oneBattle,
					sourceType = ENUM.BonusSource.other,
					sourceID = "heroes-memorial.h7:h7RuneStoneFortune",
					stacking = "h7RuneShield",
					icon = self.icon,
					addInfo = { icon = self.icon }
				}, false)
			end
		end
		if describe then R.log(server, battle, 1, {}, { #list, amount }) end
	elseif info.kind == "destruction" then
		local raw = (self.damageBase or 18) + (self.damagePerLevel or 12) * hl
		local spell = mechanics:getSpell()
		local list = R.unitsInAura(battle, stone, function(u)
			if u:getSide() == side or not L.isReal(u) or u:isInvincible() then return false end
			local ok, imm = pcall(function() return u:hasAbsoluteImmunity(spell) end)
			return not (ok and imm)
		end)
		local total = 0
		local hit = {}
		for _, u in ipairs(list) do
			local red = u:getBonusesValue({ type = "SPELL_DAMAGE_REDUCTION", subtype = "spellSchool.any" }) or 0
			red = math.max(0, math.min(100, red))
			local amount = math.floor(raw * (100 - red) / 100)
			if amount > 0 then hit[#hit + 1] = { unit = u, amount = amount } end
		end
		if describe and #hit > 0 then
			local t = {}
			for _, h in ipairs(hit) do t[#t + 1] = { unit = h.unit } end
			server:showBattleAnimation(battle, t, "h7/fx/h7rDestructionHit", "", 0.9, true)
		end
		for _, h in ipairs(hit) do
			local done, killed = server:damageUnit(battle, h.unit, h.amount)
			total = total + (done or h.amount)
			if describe and killed and killed > 0 then BattleLog.creaturesPerish(server, battle, h.unit, killed) end
		end
		if describe then R.log(server, battle, 2, {}, { #hit, total }) end
	else
		local list = R.unitsInAura(battle, stone, function(u) return L.isReal(u) and not immovable(u) end)
		table.sort(list, function(a, b)
			local da, db = L.unitHexDistance(a, center), L.unitHexDistance(b, center)
			if da ~= db then return da > db end
			return a:unitID() < b:unitID()
		end)
		local moved = 0
		for _, u in ipairs(list) do
			local dest = pushDest(battle, u, center)
			if dest ~= nil then
				local ok = pcall(function() server:moveUnit(battle, u, dest, true) end)
				if ok then moved = moved + 1 end
			end
		end
		if describe then R.log(server, battle, 3, {}, { moved }) end
	end
	L.setMark(server, battle, stone, R.STONE, 1, nil, "h7RuneUsed", true)
end

function Script:radiance(mechanics, server, battle, stone)
	server:addUnitBonus(battle, stone, {
		type       = R.RADIANT,
		val        = 3,
		duration   = ENUM.BonusDuration.nTurns,
		turns      = 2,
		sourceType = ENUM.BonusSource.other,
		sourceID   = "heroes-memorial.h7:h7RuneStoneFortune",
		stacking   = "h7RuneRadiant",
		icon       = "h7/abilities/h7RuneRadiance",
		hidden     = false
	}, false)
	L.setMark(server, battle, stone, R.STONE, 1, nil, "h7RuneRadUsed", true)
	if server:describeChanges() then
		server:showBattleAnimation(battle, { { unit = stone } }, "h7/fx/h7rRadiance", "h7/r_rune_radiance.ogg", 1.0, true)
		R.log(server, battle, 4, { L.name(stone) }, {})
	end
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local hex = destHex(target)
	if hex == nil then return end
	if self.mode == "summon" then
		self:summon(mechanics, server, battle, hex)
		return
	end
	local stone = stoneCaster(self, mechanics)
	if stone == nil then return end
	-- AI simulation branch: the Fortune shield, the Resilience push and the Rune of Radiance are worth 0 in the AI's estimate, so proxy values are reported (Destruction's activation is real damage and runs normally for the engine to value)
	local info = R.info(stone)
	if Proxy.trial(server) and info ~= nil and (self.mode == "radiance" or info.kind ~= "destruction") then
		local base = { fortune = 1, destruction = 4, resilience = 6 }
		AI.rune(server, battle, stone, info.kind, self.mode, function(u) return R.inAura(stone, u) end,
			(self.shieldBase or 6) + (self.shieldPerLevel or 4) * R.heroLevel(stone), (base[info.kind] or 0) * math.max(1, R.level(stone)))
		return
	end
	if self.mode == "activate" then
		self:activate(mechanics, server, battle, stone)
	else
		self:radiance(mechanics, server, battle, stone)
	end
	R.refresh(server, battle)
	if R.remaining(stone) == 0 then
		server:addUnitBonus(battle, stone, {
			type       = "NOT_ACTIVE",
			val        = 0,
			duration   = ENUM.BonusDuration.oneBattle,
			sourceType = ENUM.BonusSource.other,
			sourceID   = "heroes-memorial.h7:h7RuneStoneFortune",
			stacking   = "h7RuneSpent",
			hidden     = true
		}, false)
	end
	if server:describeChanges() then
		server:refreshBattleUnits(battle)
	end
end

--- Cursor and status bar text while choosing a target: cursor kadCursorSummon; the summon mode (the hero summons a rune stone) needs a free hex; activation modes (click any hex in the aura) use the engine default.
--- Hexes where it fits show "Cast X" (as the engine default, with the estimate); hexes where it does not fit show the original "X cannot be placed here" (core.genrltxt.181),
--- where the engine default would show no text at all.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	if #partialTarget ~= 0 or hoveredHex == nil or not hoveredHex:isValid() or mechanics:isMassive() then return nil end
	if self.mode ~= "summon" then return nil end
	local spellName = mechanics:getSpell():getNameTextID()
	return {
		cursor = "kadCursorSummon",
		text = { append = { "core.genrltxt.26" }, replaceStrings = { spellName } },        -- Cast %s
		blockedText = { append = { "core.genrltxt.181" }, replaceStrings = { spellName } }, -- %s cannot be placed here
		healthGainTextID = "vcmi.battleWindow.healValuePreview"
	}
end

--- Hover estimate: only activating a Rune of Destruction (mode = activate, rune kind = destruction) deals damage, same formula as apply / activate:
--- enemy stacks in the aura (except invulnerable ones and those absolutely immune to this spell) each take (damageBase + damagePerLevel x hero level) x (100 - "all spells" reduction)% damage,
--- damage and kills are summed. Summoning a rune stone and the Fate, Endurance and Radiance runes return 0
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	if self.mode ~= "activate" then return zero end
	local ok, result = pcall(function()
		local stone = stoneCaster(self, mechanics)
		if stone == nil then return zero end
		local info = R.info(stone)
		if info == nil or info.kind ~= "destruction" then return zero end
		local battle = mechanics:getBattle()
		local side = stone:getSide()
		local raw = (self.damageBase or 18) + (self.damagePerLevel or 12) * R.heroLevel(stone)
		local spell = mechanics:getSpell()
		local list = R.unitsInAura(battle, stone, function(u)
			if u:getSide() == side or not L.isReal(u) or u:isInvincible() then return false end
			local okImm, imm = pcall(function() return u:hasAbsoluteImmunity(spell) end)
			return not (okImm and imm)
		end)
		local out = { hpDelta = 0, unitsDelta = 0 }
		for _, u in ipairs(list) do
			local red = u:getBonusesValue({ type = "SPELL_DAMAGE_REDUCTION", subtype = "spellSchool.any" }) or 0
			red = math.max(0, math.min(100, red))
			local amount = math.floor(raw * (100 - red) / 100)
			if amount > 0 then
				local copy = u:copy()
				local hp, cnt = copy:getAvailableHealth(), copy:getCount()
				copy:damage(amount)
				out.hpDelta = out.hpDelta - (hp - copy:getAvailableHealth())
				out.unitsDelta = out.unitsDelta - (cnt - copy:getCount())
			end
		end
		return out
	end)
	if ok and result then return result end
	return zero
end

return Script
