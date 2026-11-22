local Base = require("spells/spellEffect")
local BattleLog = require("battleLog")
local L = require("spells/h5AbLib")
local C, A = L.C, L.A
local Proxy = require("lib/kadAiProxy")   -- Round 344: AI simulation branch (ai-skills-design)
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Area abilities of H5 creatures cast on a battlefield hex:
---   mode = "scatter" Scatter Shot (Archer): all stacks on the target hex and the ring around it (H5's 3x3), friend or foe, take pct% of normal shot damage, using 1 shot of ammo. Unlimited
---   mode = "storm"   Call Storm (Storm Lord): calls a thundercloud on the target hex and the ring around it for turns rounds;
---                    at the start of each round stacks in the cloud take Storm Lord count x per Air damage, and shooters in the cloud deal -min(Storm Lord count x 1%, 90%) ranged damage
---                    (settled by combat/h5AbStormTick). Unlimited; only the newest cloud is kept at a time
---   mode = "snare"   Set Snares (Goblin Trapper): places a trap invisible to the enemy on the target hex (only one at a time; placing again moves it),
---                    enemies stepping on it stop (like Quicksand). Unlimited
--- Parameters: mode, pct, per, turns, maxPenalty, tickScript, mark, animation (persistent cloud animation), appear, removal (fade animation)
--- Thundercloud: one cloud drawn only on the center hex for the whole area (the H5 CallStorm cloud: Storm_idle_start loop + Storm_end fade); the other 6 hexes get the transparent placeholder fx_blank

local function areaHexes(battle, center, radius)
	local out = {}
	for _, h in pairs(C.hexTable(battle)) do
		if h:isAvailable() and C.hexDistance(h, center) <= radius then out[#out + 1] = h end
	end
	return out
end

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	if caster == nil or (self.mode == "scatter" and not caster:isShooter()) then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:applicableTarget(mechanics, problem, target)
	local dest = target[1]
	if dest == nil or dest.hex == nil or not dest.hex:isValid() or not dest.hex:isAvailable() then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
		return false
	end
	if self.mode == "snare" and mechanics:getBattle():getUnitByPos(dest.hex, true) ~= nil then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
		return false
	end
	return true
end

function Script:adjustAffectedHexes(mechanics, hexes, spellTarget)
	local dest = spellTarget[1]
	if dest and dest.hex and dest.hex:isValid() then
		local r = (self.mode == "snare") and 0 or 1
		for _, h in ipairs(areaHexes(mechanics:getBattle(), dest.hex, r)) do hexes:insert(h) end
	end
	return hexes
end

-- Round 375: clouds are kept separate by casting side. Scripts cannot read which side placed an obstacle, so each time a cloud is placed the center hex is recorded on all stacks of that side
-- (mark h5StormC = center hex + 1; h5StormSeq = how many times this side has placed one), and deleting the old cloud only removes clouds around this side's old center (it used to delete the other side's too)
local CENTER, SEQ = "h5StormC", "h5StormSeq"

local function hexOfIndex(i)
	return { getX = function() return i % C.W end, getY = function() return math.floor(i / C.W) end }
end

local function sideMark(battle, side, key)
	local best = nil
	for _, u in ipairs(battle:getUnitsIf(function(x) return x:getSide() == side end)) do
		local v = C.markValue(u, key)
		if v ~= nil and (best == nil or v > best) then best = v end
	end
	return best
end

local function removeOwn(server, battle, spell, side)
	local key = spell:getJsonKey()
	if side == nil then
		for _, o in ipairs(battle:getAllObstacles() or {}) do
			local s = o:getSpell()
			if s ~= nil and s:getJsonKey() == key then server:removeObstacle(battle, o) end
		end
		return
	end
	local c = sideMark(battle, side, CENTER)
	if c == nil then return end
	local center = hexOfIndex(c - 1)
	for _, o in ipairs(battle:getAllObstacles() or {}) do
		local s = o:getSpell()
		if s ~= nil and s:getJsonKey() == key and C.hexDistance(o:getPosition(), center) <= 1 then server:removeObstacle(battle, o) end
	end
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then return end
	local dest = target[1]
	if dest == nil or dest.hex == nil then return end
	local center = dest.hex
	local spell = mechanics:getSpell()
	local mode = self.mode

	if mode == "scatter" then
		local seen = {}
		for _, h in ipairs(areaHexes(battle, center, 1)) do
			local u = battle:getUnitByPos(h, true)
			if u ~= nil and not seen[u:unitID()] and u:unitID() ~= caster:unitID() and A.damageable(u) then
				seen[u:unitID()] = true
				local dmg = A.attackDamage(server, caster, u, self.pct or 50, true)
				local _, killed = server:damageUnit(battle, u, dmg)
				if server:describeChanges() then BattleLog.creaturesPerish(server, battle, u, killed) end
			end
		end
		-- Scatter Shot is also a shot: uses 1 shot of ammo (negative SHOTS bonus, whole battle)
		L.addBonus(server, battle, caster, { type = "SHOTS", val = -1, hidden = true }, true)
	elseif mode == "snare" and Proxy.trial(server) then
		-- Round 344: AI simulation branch (ai-skills-design #46 Set Snares). An invisible trap is worth 0 in the AI's estimate: of enemy ground melee stacks within 2 hexes of the spot and not yet engaged,
		-- the most valuable one is reported as total health x 1/8 x 0.3 x stepping chance 0.3, capped as a weak ability. Real casts do not go through here
		local best, bestHp = nil, 0
		for _, u in ipairs(battle:getUnitsIf(function(x)
			return Proxy.hostile(battle, caster, x) and not x:isShooter() and not x:hasBonuses({ type = "FLYING" })
				and Proxy.unitDistance(x, center) <= 2
		end)) do
			if #Proxy.adjacent(battle, u, function(x) return not battle:isHostile(caster, x) end) == 0 then
				local hp = Proxy.capWeak(u:getAvailableHealth() / 8 * 0.3 * 0.3, battle, caster, u)
				if hp > bestHp then best, bestHp = u, hp end
			end
		end
		if best ~= nil and bestHp >= best:getMaxHealth() then Proxy.damage(server, battle, best, bestHp) end
		return
	elseif mode == "storm" and Proxy.trial(server) then
		-- Round 344: AI simulation branch (ai-skills-design #5). The cloud (obstacle + battlefield script) is worth 0 in the AI's estimate, so equivalent health loss is reported instead:
		-- each enemy in the cloud: Storm Lord count x per x (one strike at the start of each of the next three rounds, with enemies walking away: 0.5 + 0.4 + 0.15);
		-- allies in the cloud get hit too, discounted by their loss (enemy gain x (1 - ally loss / enemy gain)); only 0.3 if the side already has a cloud of its own
		-- (the new cloud replaces the old). Real casts do not go through here
		local per = caster:getCount() * (self.per or 10) * (0.5 + 0.4 + 0.15)
		local gain, loss, list = 0, 0, {}
		for _, h in ipairs(areaHexes(battle, center, 1)) do
			local u = battle:getUnitByPos(h, true)
			if u ~= nil and not list[u:unitID()] and A.damageable(u) and not Proxy.immune(u, { school = "air" }) then
				list[u:unitID()] = u
				local v = math.min(per, u:getAvailableHealth()) / u:getMaxHealth() * Proxy.value(u)
				if battle:isHostile(caster, u) then gain = gain + v else loss = loss + v end
			end
		end
		if gain <= loss then return end
		local scale = 1 - loss / gain
		for _, o in ipairs(battle:getAllObstacles() or {}) do
			local s = o:getSpell()
			if s ~= nil and s:getJsonKey() == spell:getJsonKey() then scale = scale * 0.3 break end
		end
		for _, u in pairs(list) do
			if battle:isHostile(caster, u) then Proxy.damage(server, battle, u, per * scale, { school = "air" }) end
		end
		return
	elseif mode == "storm" or mode == "snare" then
		removeOwn(server, battle, spell, (mode == "storm") and caster:getSide() or nil)
		local hexes = (mode == "storm") and areaHexes(battle, center, 1) or { center }
		for _, h in ipairs(hexes) do
			local mid = C.hexDistance(h, center) == 0
			server:addObstacle(battle, {
				pos              = h,
				obstacleType     = ENUM.ObstacleType.spellCreated,
				spell            = spell,
				casterSpellPower = caster:getCount(),
				spellLevel       = 0,
				casterSide       = mechanics:getCasterSide(),
				turnsRemaining   = (mode == "storm") and (self.turns or 3) or -1,
				hidden           = (mode == "snare"),
				passable         = true,
				nativeVisible    = false,
				trap             = (mode == "snare"),
				removeOnTrigger  = (mode == "snare"),
				trigger          = "",
				appearSound      = (mode == "storm" and mid) and "LIGHTBLT" or "",
				appearAnimation  = mid and (self.appear or "") or "",
				animation        = (mid or mode ~= "storm") and (self.animation or "") or "h5/fx/fx_blank",
				removalAnimation = mid and (self.removal or "") or "",
				customSize       = { h },
			})
		end
		if mode == "storm" and server:describeChanges() then
			-- Round 375: one settling bonus per side (stacking group carries the side id), value = how many times this side has placed a cloud: the engine keeps only the largest of a stacking group,
			-- so it always settles by the center and Storm Lord count of the newest cloud; the caster is recorded so the cloud does not hurt it
			-- (originally: both sides shared one stacking group h5AbStormTick, val 0, so which one was kept was uncertain)
			local side = caster:getSide()
			local seq = (sideMark(battle, side, SEQ) or 0) + 1
			local ci = C.hexIndex(center)
			for _, u in ipairs(battle:getUnitsIf(function(x) return x:getSide() == side and x:isAlive() end)) do
				C.setMark(server, battle, u, CENTER, ci + 1, nil)
				C.setMark(server, battle, u, SEQ, seq, nil)
			end
			server:addBattleBonus(battle, {
				type       = "COMBAT_EVENT_TRIGGER",
				subtype    = self.tickScript or "heroes-memorial.h5:h5AbStormTick",
				val        = seq,
				duration   = "ONE_BATTLE",
				sourceType = "OTHER",
				stacking   = "h5AbStormTick" .. tostring(side),
				addInfo    = { spell = spell:getJsonKey(), power = caster:getCount(), per = self.per or 10, maxPenalty = self.maxPenalty or 90,
					center = ci, caster = caster:unitID() }
			})
		end
	end

	if server:describeChanges() then
		server:refreshBattleUnits(battle)
		if self.mark then L.log(server, battle, self.mark, 1, { C.name(caster) }) end
	end
	L.useCast(server, battle, caster, "h5AbZone" .. (mode or ""), self.uses)
end

return Script
