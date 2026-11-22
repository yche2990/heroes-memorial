--- H6 memorial hero spells: helpers shared by the scripts (not registered as a script; required by spells/h6Sp* and combat/h6Sp*).
--- Values: base and per are 4 numbers (none/basic/advanced/expert); value = base[level] + per[level] x Spell Power.
local L = require("combat/h6Lib")
local Proxy = require("lib/kadAiProxy")
local M = {}

function M.lvl(mechanics) return math.max(0, math.min(3, mechanics:getEffectLevel() or 0)) + 1 end
function M.power(mechanics) return math.max(0, mechanics:getEffectPower() or 0) end
function M.value(mechanics, base, per)
	local i = M.lvl(mechanics)
	return (base and base[i] or 0) + (per and per[i] or 0) * M.power(mechanics)
end
function M.pick(mechanics, arr) return arr and arr[M.lvl(mechanics)] or 0 end

--- A living stack of the casting side (used when the hero casts, to go through the engine's spell damage adjustments: school reduction, immunity, the hero's spell damage bonus)
function M.actor(mechanics)
	local u = mechanics:getUnitCaster()
	if u then return u end
	local side = mechanics:getCasterSide()
	for _, x in ipairs(mechanics:getBattle():getUnitsIf(function(x) return x:getSide() == side and x:isAlive() and not x:isTurret() end)) do return x end
	return nil
end

--- Spell damage: through the engine's adjustments for this spell; without a casting-side stack, scaled by school reduction
function M.spellDamage(mechanics, unit, raw, school)
	local sp = mechanics:getSpell()
	local a = M.actor(mechanics)
	if a then
		local ok, v = pcall(function() return sp:adjustDamage(mechanics:getBattle(), a, unit, math.floor(raw)) end)
		if ok and v then return v end
	end
	return math.floor(raw * (100 - L.schoolReduction(unit, school)) / 100)
end

--- Remove all bonuses a given spell put on a stack (only this spell's; same type and value from other sources are untouched)
function M.removeSpell(server, battle, unit, spellKey)
	local list = unit:getBonuses({ sourceType = ENUM.BonusSource.spellEffect }):filter(function(b) return b:getSourceID() == spellKey end)
	if list:size() > 0 then Proxy.removeExact(server, battle, unit, list) end
end

--- Spells on the stack that raise or lower (sign 1 = positive, -1 = negative) a given bonus (MORALE etc.): dispel those spells completely
function M.dispelBySign(server, battle, unit, bonusType, sign, keep)
	local keys = {}
	local list = unit:getBonuses({ type = bonusType, sourceType = ENUM.BonusSource.spellEffect })
	for i = 1, list:size() do
		local b = list:getBonus(i)
		if b:getVal() * sign > 0 and b:getSourceID() ~= keep then keys[b:getSourceID()] = true end
	end
	for k in pairs(keys) do M.removeSpell(server, battle, unit, k) end
end

--- Evil stacks (Heal and Mass Heal deal Light damage to them): undead, demons (Tears of Ashan DEMONIC; H6 Inferno creatures by id), H5 orcs (H5_DEMON_RAGED_H5C), H6 Stronghold creatures
function M.evil(u)
	if u:hasBonuses({ type = "UNDEAD" }) then return true end
	for _, t in ipairs({ "tears-of-ashan:DEMONIC", "H5_DEMON_RAGED_H5C" }) do
		local ok, r = pcall(function() return u:hasBonuses({ type = t }) end)
		if ok and r then return true end
	end
	local key = u:getCreature():getJsonKey()
	return string.find(key, "h6Stronghold", 1, true) ~= nil or string.find(key, "h6Inferno", 1, true) ~= nil
end

-- ---- Zones and obstacles (batch 3: Ice Wall, Wall of Rock, Frozen Ground, Blizzard, Poison Cloud) ---------------------------------

--- Hexes of a zone: mode = "disc" (radius rings around the center), "wall" (3-hex wall: the center and the hexes above and below it on the enemy-facing side), "rocks" (3 rocks: the center and the hexes one row apart straight above and below)
function M.zoneHexes(battle, mode, center, radius, side)
	local out = {}
	local function put(h) if h and h:isValid() and h:isAvailable() then out[#out + 1] = h end end
	if mode == "disc" then
		for _, h in pairs(L.hexTable(battle)) do
			if h:isAvailable() and L.hexDistance(h, center) <= (radius or 1) then out[#out + 1] = h end
		end
	elseif mode == "idol" then
		put(center)
	elseif mode == "wall" then
		put(center)
		if side == ENUM.BattleSide.attacker then put(center:copyToNorthEast()); put(center:copyToSouthEast())
		else put(center:copyToNorthWest()); put(center:copyToSouthWest()) end
	elseif mode == "rocks" then
		put(center)
		local up = center:copyToNorthEast(); if up and up:isValid() then put(up:copyToNorthWest()) end
		local dn = center:copyToSouthEast(); if dn and dn:isValid() then put(dn:copyToSouthWest()) end
	end
	return out
end

--- Whether a hex holds an obstacle of this zone. centerIdx (review A4, 2026-11-08): only obstacles whose anchor (center hex at cast time) matches count,
--- since each zone has exactly one active obstacle anchored at the center hex at cast time, an enemy zone of the same name covering these hexes is not taken for our own
--- (obstacle objects do not expose the caster's side, so the anchor tells them apart; two zones of both sides centered on the very same hex still cannot be told apart, which is very rare)
local function hasSpellObstacle(battle, hex, key, centerIdx)
	for _, o in ipairs(battle:getObstaclesOnPos(hex, false) or {}) do
		local s = o:getSpell()
		if s ~= nil and s:getJsonKey() == key and (centerIdx == nil or L.hexIndex(o:getPosition()) == centerIdx) then return true end
	end
	return false
end

--- Settle a zone once according to info (called at cast time and at the start of each round). info: spell, side, mode, center, radius,
--- who ("inside" stacks in the zone / "adjacent" stacks touching the zone), hostileOnly, amount (raw damage computed at cast time, 0 = no damage),
--- school, status (status name), animation, sound;
--- aura (statue: range = aura rings around the center), alliedOnly (only the casting side's stacks), bonus ({ {type, subtype, val} } a 1-round bonus for the casting side's stacks in the zone),
--- chain (number of Chain Lightning targets: starts at a random enemy in the zone, each jump halves the damage)
function M.zoneTick(server, battle, info)
	local spell = LIBRARY:getSpellByName(info.spell or "")
	if spell == nil then return end
	local key = spell:getJsonKey()
	local cells = L.hexTable(battle)
	local center = cells[info.center or -1]
	if center == nil then return end
	local hexes = {}
	for _, h in ipairs(M.zoneHexes(battle, info.mode, center, info.radius, info.side)) do
		if hasSpellObstacle(battle, h, key, info.center) then hexes[#hexes + 1] = h end
	end
	if #hexes == 0 then
		-- Round 416: when a zone expires (runs out or is dismantled), the visible strips are removed from top to bottom, then the fading animation plays
		if info.fx then
			local cs = {}
			for _, i in ipairs(info.fx.centers or {}) do if cells[i] then cs[#cs + 1] = cells[i] end end
			M.zoneFxClear(server, battle, cs, info.fx, info.fx.removal, center)
		end
		return
	end
	if info.fxOnly then return end
	if (info.aura or 0) > 0 then            -- Statue: the obstacle occupies only the center hex; the range is aura rings around the center
		hexes = M.zoneHexes(battle, "disc", center, info.aura, info.side)
	end
	local hit = {}
	for _, u in ipairs(battle:getUnitsIf(function(x) return L.real(x) end)) do
		if not (info.hostileOnly and u:getSide() == info.side) and not (info.alliedOnly and u:getSide() ~= info.side) then
			local ok = false
			for _, h in ipairs(hexes) do
				if info.who == "adjacent" then
					local uh = u:getHexes()
					for i = 1, uh:size() do if L.hexDistance(uh:at(i), h) == 1 then ok = true; break end end
				elseif u:coversPos(h) then ok = true end
				if ok then break end
			end
			if ok then hit[#hit + 1] = u end
		end
	end
	if info.bonus and server:describeChanges() then   -- Bonus for stacks in the zone: each settlement removes the old one first, then gives stacks in the zone 1 round
		-- Review A4 (2026-11-08): only remove it from the casting side's own stacks (the bonus is only given to the casting side); what an enemy zone of the same name gave the enemy stays
		for _, u in ipairs(battle:getUnitsIf(function(x) return x:isAlive() and x:getSide() == info.side end)) do M.removeSpell(server, battle, u, key) end
		for _, u in ipairs(hit) do
			if u:getSide() == info.side then for _, b in ipairs(info.bonus) do
				-- Review A1: store the casting level (info.level, recorded by spells/h6SpZone at cast time; 0 for old saves without it), so right-clicking a stack does not index out of range
				server:addUnitBonus(battle, u, { type = b.type, subtype = b.subtype, val = b.val or 0, duration = "N_TURNS", turns = 1,
					sourceType = "SPELL_EFFECT", sourceID = key, sourceSecondaryID = info.level or 0 }, false)
			end end
		end
	end
	if info.chain and (info.amount or 0) > 0 then    -- Chain Lightning: starts at a random enemy in the zone, jumps to the nearest other enemy, halving the damage each jump
		local foes = {}
		for _, u in ipairs(hit) do if u:getSide() ~= info.side then foes[#foes + 1] = u end end
		if #foes == 0 then if server:describeChanges() then server:refreshBattleUnits(battle) end return end
		local cur = foes[server:rngInt(1, #foes)]
		local done = {}
		local amount = info.amount
		local chainHit = {}
		for _ = 1, info.chain do
			if cur == nil then break end
			done[cur:unitID()] = true
			chainHit[#chainHit + 1] = { u = cur, raw = amount }
			amount = math.floor(amount / 2)
			local nxt, best = nil, 1000
			for _, u in ipairs(battle:getUnitsIf(function(x) return L.real(x) and x:getSide() ~= info.side and not done[x:unitID()] end)) do
				local d = L.unitDistance(cur, u)
				if d < best then nxt, best = u, d end
			end
			cur = nxt
		end
		hit = {}
		for _, c in ipairs(chainHit) do hit[#hit + 1] = c.u end
		info = setmetatable({ chainRaw = chainHit }, { __index = info })
	end
	if #hit == 0 then return end
	local actor = nil
	for _, x in ipairs(battle:getUnitsIf(function(x) return x:getSide() == info.side and x:isAlive() and not x:isTurret() end)) do actor = x; break end
	local status = info.status and LIBRARY:getSpellByName("kad-mechanics:" .. info.status) or nil
	local BattleLog = require("battleLog")
	local rawOf = {}
	if info.chainRaw then for _, c in ipairs(info.chainRaw) do rawOf[c.u:unitID()] = c.raw end end
	for _, u in ipairs(hit) do
		local raw = rawOf[u:unitID()] or info.amount or 0
		if raw > 0 and u:isAlive() then
			local dmg = nil
			if actor then
				local ok, v = pcall(function() return spell:adjustDamage(battle, actor, u, math.floor(raw)) end)
				if ok and v then dmg = v end
			end
			if dmg == nil then dmg = math.floor(raw * (100 - L.schoolReduction(u, info.school)) / 100) end
			if dmg > 0 then
				if info.animation and server:describeChanges() then
					server:showBattleAnimation(battle, { { unit = u } }, info.animation, info.sound or "", 1.0, true)
				end
				local _, killed = server:damageUnit(battle, u, dmg)
				if server:describeChanges() then BattleLog.creaturesPerish(server, battle, u, killed) end
			end
		end
		if status and u:isAlive() and server:describeChanges() then
			local others = battle:getUnitsIf(function(x) return x:getSide() ~= u:getSide() and x:isAlive() and not x:isTurret() end)
			server:castSpell(battle, others[1] or u, status, { u }, 0)
		end
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
end

--- Round 416: zone visuals (engine rules at the top of r416\fx\obstacle416.py).
--- Appearing and fading play with showBattleAnimation on the center hex (waiting until done); the persistent image is cut into horizontal strips by hex row, each a visible obstacle:
--- marker spell h6SpZoneFx, empty customSize (occupies no hex, blocks nothing, not swept by "remove obstacle" spells), permanent; removed by zoneTick when the zone expires.
--- fx = { D = number of strips - 1, E = { E for even rows, E for odd rows } }: the anchor of strip d (d rows below the center row) is the hex in that row whose center is E pixels from the image's left edge relative to the center hex,
--- when the left edge cannot be reached, column 0 is used with the left-cropped version (suffix e<actual E>); rows below 10 are not drawn.
--- Strips are placed from bottom to top; "appear" is 1 frame "this row and everything above" (_h<d>), so the image stays complete while queued; removal goes top to bottom, and "fade" also uses _h<d>.
local function px(x, y) return 14 + ((y % 2 == 0) and 22 or 0) + 44 * x end
local MARKER = "heroes-memorial.h6:h6SpZoneFx"
--- Strips of one center hex: returns { hex, d, suffix } in placing order (bottom to top)
function M.zoneFxList(battle, center, fx)
	local tbl = L.hexTable(battle)
	local hx, hy = center:getX(), center:getY()
	local out = {}
	for d = math.min(fx.D or 0, 10 - hy), 0, -1 do
		local Y = hy + d
		local E = fx.E[(d % 2) + 1]
		local X = math.floor((px(hx, hy) + 22 - E - px(0, Y)) / 44 + 0.5)
		if X < 0 then X = 0 end
		local h = tbl[X + Y * L.W]
		if h ~= nil then
			local e = px(hx, hy) + 22 - px(X, Y)
			out[#out + 1] = { hex = h, d = d, suffix = "_h" .. d .. ((e == E) and "" or ("e" .. e)), bsuffix = "_b" .. d .. ((e == E) and "" or ("e" .. e)) }
		end
	end
	return out
end
--- Place strips (centers: center hexes; Wall of Rock has one per rock)
function M.zoneFxPlace(server, battle, centers, fx, idle, side, passable, hidden)
	if not server:describeChanges() then return end
	local marker = LIBRARY:getSpellByName(MARKER)
	if marker == nil then return end
	for _, c in ipairs(centers) do
		for _, b in ipairs(M.zoneFxList(battle, c, fx)) do
			server:addObstacle(battle, {
				pos = b.hex, obstacleType = ENUM.ObstacleType.spellCreated, spell = marker,
				casterSpellPower = 0, spellLevel = 0, casterSide = side, turnsRemaining = -1,
				hidden = hidden or false, passable = (b.d > 0) or (passable or false), nativeVisible = false,
				trap = false, removeOnTrigger = false, trigger = "", appearSound = "",
				appearAnimation = idle .. b.suffix, animation = idle .. b.bsuffix, removalAnimation = idle .. b.suffix,
				customSize = {},
			})
		end
	end
end
--- Remove strips (top to bottom); the fading animation only plays if something was removed; returns how many were removed
function M.zoneFxClear(server, battle, centers, fx, removal, anchorHex)
	if not server:describeChanges() then return 0 end
	local n = 0
	for _, c in ipairs(centers) do
		local list = M.zoneFxList(battle, c, fx)
		for i = #list, 1, -1 do
			local b = list[i]
			for _, o in ipairs(battle:getAllObstacles() or {}) do
				local s = o:getSpell()
				if s ~= nil and s:getJsonKey() == MARKER and L.hexIndex(o:getPosition()) == L.hexIndex(b.hex) then
					server:removeObstacle(battle, o); n = n + 1; break
				end
			end
		end
	end
	if n > 0 and removal and removal ~= "" and anchorHex then
		server:showBattleAnimation(battle, { { hex = anchorHex } }, removal, "", 1.0)
	end
	return n
end

-- ---- Value helpers for the AI simulation (2026-11-08, AI skill fixes) ------------------------------------------
-- Only used in the simulation branch (Proxy.trial), never by real casts. Values are measured as in kadAiProxy: value per creature x health fraction.

--- Value of unit's best single normal attack: estimate the expected damage against each enemy that can be hit (Proxy.attackEstimate, no dice;
--- shooters by their shot, others in melee, not above the enemy's remaining health), convert to the enemy's value (damage / health per creature x value per creature), take the maximum. 0 without enemies.
--- Bosses' support abilities and self-buffs use it as the yardstick "compared with a normal attack".
function M.attackValue(battle, unit)
	if unit == nil or not unit:isAlive() then return 0 end
	local best = 0
	for _, e in ipairs(battle:getUnitsIf(function(x) return Proxy.hostile(battle, unit, x) end)) do
		local dmg = math.min(Proxy.attackEstimate(unit, e, 100, unit:isShooter()), e:getAvailableHealth())
		local v = dmg / math.max(1, e:getMaxHealth()) * Proxy.value(e)
		if v > best then best = v end
	end
	return best
end

--- Book value against the casting side's enemies (by the casting stack's side if there is one, by the casting side for hero casts); returns how many points were deducted
function M.credit(server, battle, mechanics, value)
	if value == nil or value <= 0 then return 0 end
	local caster = mechanics:getUnitCaster()
	if caster ~= nil then return Proxy.credit(server, battle, caster, value) end
	return Proxy.creditSide(server, battle, mechanics:getCasterSide(), value)
end

return M
