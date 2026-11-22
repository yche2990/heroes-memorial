--- Shared by H7 warfare units (round 428): levels, factions, the H7 machine for each slot, swapping in / back, syncing health and death.
--- Only loaded with require("heroes-memorial.h7:combat/h7WarfareLib"), not registered as a script.
---
--- How it works (as h6FormSwap of heroes-memorial.h6): the original war machine O is not removed but "hidden" (ghost: does not act, occupies no hex, cannot be targeted,
--- but stays in the army); a temporary stack G (summoned, does not join the army after battle) is added in its place. When G dies O dies too, and after battle it is settled as O:
--- if killed, the machine is lost as usual (the Catapult is never lost); if not, the machine remains.
--- Level: the hero's Artillery / Ballistics / First Aid (Basic 2, Advanced 3, Expert 4; level 5 for all when the hero has all three). Skill levels, faction and smithy marks
--- are hidden bonuses H7_WARFARE_MARK_H7C on the hero (kept apart by stacking group), inherited by stacks and read by the script on O.
--- Machine creature configs hold level 2 values; the differences for levels 3-5 are added here as hidden bonuses (health, Attack/Defense, damage) instead of making 5 creatures each.

local M = {}
local MOD = "heroes-memorial.h7:"
M.MARK = "H7_WARFARE_MARK_H7C"
M.SHOW = "H7_WARFARE_LV_H7C"
M.LINK = "h7WfOrig"   -- On G: stack id of the original machine
M.LEVEL = "h7WfLevel" -- On G: level
M.PREFIX = "h7Warfare" -- Creature id = h7Warfare + the short name in the table below

-- Faction ids (the smithy records them on the hero by hero class: stacking h7WfFaction, value 1-7)
M.FACTIONS = { "castle", "tower", "necropolis", "stronghold", "rampart", "dungeon", "bastille" }

-- Original machine -> slot
M.SLOT_OF = { ballista = "ballista", firstAidTent = "tent", catapult = "catapult", ammoCart = "cart" }
-- Slot -> skill deciding the level
M.SKILL_OF = { ballista = "artillery", cart = "artillery", tent = "firstAid", catapult = "ballistics" }

-- Faction -> slot -> unit (Necropolis and Stronghold have no ranged / support warfare units: the Ballista and Tent slots stay original; Namtaru and Dream Walker take the Ammo Cart slot)
M.UNITS = {
	castle = { ballista = "HavenBallista", tent = "HealingSister", catapult = "HavenCatapult" },
	tower = { ballista = "SmallPyramid", tent = "HealingTent", catapult = "GreatPyramid" },
	necropolis = { cart = "Namtaru", catapult = "SpittingSpider" },
	stronghold = { cart = "Dreamwalker", catapult = "TamedCyclops" },
	rampart = { ballista = "SylvanBallista", tent = "MotherTreant", catapult = "GreaterEarthElemental" },
	dungeon = { ballista = "ShadowLurker", tent = "Faceless", catapult = "CaveWyvern" },
	bastille = { ballista = "DwarvenBallista", tent = "Runestone", catapult = "FireCannon" },
}
-- Those replaced by another creature at level 5 (the Sister resurrects at level 5, siege units get 1 more shot); other level 5 effects are decided by the skill scripts by level
M.LV5 = { HealingSister = "HealingSister5", HavenCatapult = "HavenCatapult5", GreatPyramid = "GreatPyramid5",
	SpittingSpider = "SpittingSpider5", TamedCyclops = "TamedCyclops5", GreaterEarthElemental = "GreaterEarthElemental5",
	CaveWyvern = "CaveWyvern5", FireCannon = "FireCannon5" }

-- Differences of levels 3-5 from level 2 (creature config): health, Attack, Defense, minimum / maximum damage per creature (section 7 of the data sheet)
M.DELTA = {
	HavenBallista = { [3] = { hp = 83, att = 8, def = 15, dmin = 1, dmax = 1 }, [4] = { hp = 166, att = 16, def = 22, dmin = 1, dmax = 1 }, [5] = { hp = 291, att = 25, def = 36, dmin = 2, dmax = 3 } },
	SylvanBallista = { [3] = { hp = 83, att = 8, def = 7, dmin = 0, dmax = 1 }, [4] = { hp = 167, att = 16, def = 15, dmin = 0, dmax = 1 }, [5] = { hp = 250, att = 25, def = 22, dmin = 1, dmax = 2 } },
	DwarvenBallista = { [3] = { hp = 84, att = 8, def = 15, dmin = 0, dmax = 1 }, [4] = { hp = 167, att = 16, def = 22, dmin = 0, dmax = 1 }, [5] = { hp = 334, att = 25, def = 36, dmin = 1, dmax = 2 } },
	SmallPyramid = { [3] = { hp = 83, att = 8, def = 7, dmin = 1, dmax = 1 }, [4] = { hp = 167, att = 16, def = 15, dmin = 1, dmax = 1 }, [5] = { hp = 333, att = 25, def = 22, dmin = 2, dmax = 3 } },
	ShadowLurker = { [3] = { hp = 83, att = 17, def = 7, dmin = 0, dmax = 1 }, [4] = { hp = 166, att = 25, def = 15, dmin = 0, dmax = 1 }, [5] = { hp = 291, att = 33, def = 22, dmin = 1, dmax = 2 } },
	HealingSister = { [3] = { hp = 25, att = 0, def = 0 }, [4] = { hp = 50, att = 0, def = 0 }, [5] = { hp = 75, att = 0, def = 0 } },
	HealingTent = { [3] = { hp = 25, att = 0, def = 0 }, [4] = { hp = 50, att = 0, def = 0 }, [5] = { hp = 100, att = 0, def = 0 } },
	MotherTreant = { [3] = { hp = 25, att = 0, def = 0 }, [4] = { hp = 50, att = 0, def = 0 }, [5] = { hp = 75, att = 0, def = 0 } },
	Faceless = { [3] = { hp = 25, att = 0, def = 0 }, [4] = { hp = 50, att = 0, def = 0 }, [5] = { hp = 75, att = 0, def = 0 } },
	Runestone = { [3] = { hp = 25, att = 0, def = 0 }, [4] = { hp = 50, att = 0, def = 0 }, [5] = { hp = 75, att = 0, def = 0 } },
	HavenCatapult = { [3] = { hp = 866, att = 0, def = 12 }, [4] = { hp = 1733, att = 0, def = 24 }, [5] = { hp = 4333, att = 0, def = 35 } },
	GreatPyramid = { [3] = { hp = 666, att = 0, def = 10 }, [4] = { hp = 1666, att = 0, def = 20 }, [5] = { hp = 3333, att = 0, def = 30 } },
	SpittingSpider = { [3] = { hp = 466, att = 0, def = 7 }, [4] = { hp = 933, att = 0, def = 15 }, [5] = { hp = 2333, att = 0, def = 23 } },
	TamedCyclops = { [3] = { hp = 866, att = 0, def = 12 }, [4] = { hp = 1733, att = 0, def = 24 }, [5] = { hp = 4333, att = 0, def = 35 } },
	GreaterEarthElemental = { [3] = { hp = 466, att = 0, def = 7 }, [4] = { hp = 933, att = 0, def = 15 }, [5] = { hp = 2333, att = 0, def = 23 } },
	CaveWyvern = { [3] = { hp = 666, att = 0, def = 10 }, [4] = { hp = 1666, att = 0, def = 20 }, [5] = { hp = 3666, att = 0, def = 30 } },
	FireCannon = { [3] = { hp = 666, att = 0, def = 12 }, [4] = { hp = 1333, att = 0, def = 24 }, [5] = { hp = 3333, att = 0, def = 35 } },
	Namtaru = { [3] = { hp = 16, att = 8, def = 5, dmin = 1, dmax = 1 }, [4] = { hp = 16, att = 16, def = 10, dmin = 1, dmax = 1 }, [5] = { hp = 33, att = 25, def = 15, dmin = 2, dmax = 3 } },
	Dreamwalker = { [3] = { hp = 16, att = 8, def = 5, dmin = 0, dmax = 1 }, [4] = { hp = 33, att = 16, def = 10, dmin = 1, dmax = 1 }, [5] = { hp = 50, att = 25, def = 15, dmin = 2, dmax = 3 } },
}

-- Healers (engine healing spell, amount = SPECIFIC_SPELL_POWER): healing per level (section 3 of the data sheet, x0.75 rounded)
M.HEAL = {
	HealingSister = { [2] = 38, [3] = 75, [4] = 113, [5] = 188 },
	HealingTent = { [2] = 38, [3] = 75, [4] = 150, [5] = 300 },
	Dreamwalker = { [2] = 30, [3] = 45, [4] = 90, [5] = 225 },
}
M.HEAL_SPELL = { HealingSister = "h7wfSisterHeal", HealingSister5 = "h7wfSisterRevive", HealingTent = "h7wfTentHeal",
	Dreamwalker = "h7wfShamanHeal" }

-- Values per level of the scripted abilities (converted from section 3 of the data sheet)
M.SKILL = {
	renewal = { [2] = 30, [3] = 45, [4] = 90, [5] = 225 },   -- Mother Tree Renewal: heals at the start of each round, 3 rounds
	cloak = { [2] = 34, [3] = 45, [4] = 68, [5] = 90 },      -- Faceless Death Cloak: reflected damage
	cloakBurst = 135,                                         -- Level 5: if the cloak is still there at the end of the round, it explodes on the surrounding enemies
	runeHeal = { [2] = 11, [3] = 13, [4] = 15, [5] = 38 },   -- Runestone: allies in the first three columns
	darkTouch = { [2] = 1, [3] = 1, [4] = 1, [5] = 2 },      -- Namtaru Touch of Darkness: extra Dark damage per creature per hit (not scaled)
	harrowPct = 40, harrowTurns = 2,                          -- Shadow Lurker Terrifying Visions
}

-- Ranged ones: damage as the original Ballista x (hero Attack + K), K see M.ballistaK (5 with the HotA balance in the pack)
M.RANGED = { HavenBallista = true, SylvanBallista = true, DwarvenBallista = true, SmallPyramid = true, ShadowLurker = true,
	Namtaru = true, Dreamwalker = true }

function M.bare(key)
	local i = key:find(":", 1, true)
	return i and key:sub(i + 1) or key
end

function M.creatureKey(u)
	return M.bare(u:getCreature():getJsonKey())
end

--- Short name of the stack's H7 machine (nil if not an H7 machine)
function M.shortKey(u)
	local k = M.creatureKey(u)
	if k:sub(1, #M.PREFIX) ~= M.PREFIX then return nil end
	return k:sub(#M.PREFIX + 1)
end

--- Warfare level of the stack (on G; nil if not an H7 machine)
function M.levelOf(u)
	return M.mark(u, M.LEVEL)
end

--- Value of the first mark with stacking key (marks the hero got more than once count once)
function M.mark(u, key)
	local ok, list = pcall(function()
		return u:getBonuses({ type = M.MARK }):filter(function(b) return b:getStacking() == key end)
	end)
	if not ok or list == nil or list:size() == 0 then return nil end
	-- The same mark may appear several times (Artillery and the Undead Emperor's Reaper both give skill level marks): take the maximum
	local v = list:getBonus(1):getVal()
	for i = 2, list:size() do
		local x = list:getBonus(i):getVal()
		if x > v then v = x end
	end
	return v
end

function M.skill(u, name) return M.mark(u, "h7WfSkill|" .. name) or 0 end

--- Level: nil (no swap) if the matching skill is missing (including forgotten before battle)
function M.levelFor(u, slot)
	local s = M.skill(u, M.SKILL_OF[slot])
	if s <= 0 then return nil end
	if M.skill(u, "artillery") > 0 and M.skill(u, "ballistics") > 0 and M.skill(u, "firstAid") > 0 then return 5 end
	return math.min(4, s + 1)
end

function M.factionOf(u)
	local v = M.mark(u, "h7WfFaction")
	return v and M.FACTIONS[v] or nil
end

function M.isWarfare(u)
	return M.mark(u, M.LEVEL) ~= nil
end

function M.byId(battle, id)
	local list = battle:getUnitsIf(function(x) return x:unitID() == id end)
	return list[1]
end

function M.original(battle, G)
	local id = M.mark(G, M.LINK)
	if id == nil then return nil end
	return M.byId(battle, id)
end

local function hidden(desc)
	desc.hidden = true
	desc.duration = ENUM.BonusDuration.oneBattle
	desc.sourceType = ENUM.BonusSource.other
	desc.valueType = desc.valueType or ENUM.BonusValueType.additiveValue
	return desc
end

local function add(server, battle, u, desc) server:addUnitBonus(battle, u, desc, true) end

--- Hero Attack (as the engine's ballistaDamage: base + artifacts); 0 without a hero
function M.heroAttack(u)
	return u:getBonusesValue({ type = "PRIMARY_SKILL", subtype = "attack", sourceType = ENUM.BonusSource.artifact })
		+ u:getBonusesValue({ type = "PRIMARY_SKILL", subtype = "attack", sourceType = ENUM.BonusSource.heroBaseSkill })
end

--- The number added to hero Attack in the original Ballista damage formula (val of the engine's ballistaDamage: 1 originally; the HotA balance heroAttackDamage changes it to 5).
--- First read ballistaDamage on the original machine O (Ballista slot); if unreadable (Ammo Cart slot, smithy guards) use the H7 machine creature's own mark h7WfBallistaK
--- (written by the generator from the Ballista's actual value in the pack), otherwise 1
function M.ballistaK(O, G)
	for _, u in pairs({ [1] = O or false, [2] = G or false }) do
		if u then
			local ok, list = pcall(function() return u:getBonuses({ type = "COMBAT_EVENT_TRIGGER" }) end)
			if ok and list ~= nil then
				for i = 1, list:size() do
					local b = list:getBonus(i)
					local s = tostring(b:getSubtype())
					if s == "ballistaDamage" or s:sub(-15) == ":ballistaDamage" or s:sub(-15) == ".ballistaDamage" then return b:getVal() end
				end
			end
		end
	end
	local v = G ~= nil and M.mark(G, "h7WfBallistaK") or nil
	return v or 1
end

--- Add level bonuses to G (health, Attack/Defense, damage, healing, level marker for display) and restore full health
function M.applyLevel(server, battle, G, unitKey, level, heroAtk, k0)
	local base = M.bare(unitKey):gsub("5$", "")
	local d = (M.DELTA[base] or {})[level]
	if d then
		if d.hp ~= 0 then add(server, battle, G, hidden({ type = "STACK_HEALTH", val = d.hp })) end
		if d.att ~= 0 then add(server, battle, G, hidden({ type = "PRIMARY_SKILL", subtype = "attack", val = d.att })) end
		if d.def ~= 0 then add(server, battle, G, hidden({ type = "PRIMARY_SKILL", subtype = "defence", val = d.def })) end
		if d.dmin and d.dmin ~= 0 then add(server, battle, G, hidden({ type = "CREATURE_DAMAGE", subtype = "creatureDamageMin", val = d.dmin })) end
		if d.dmax and d.dmax ~= 0 then add(server, battle, G, hidden({ type = "CREATURE_DAMAGE", subtype = "creatureDamageMax", val = d.dmax })) end
	end
	if M.RANGED[base] then
		-- As the original Ballista: damage per creature x (hero Attack + K), K see M.ballistaK (5 with the HotA balance). G does not carry the engine's ballistaDamage (which reads damage during battle setup,
		-- before G is added, so it would miss the level bonuses); it is computed here and fixed with independentMax
		local k = heroAtk + (k0 or M.ballistaK(nil, G))
		local lo, hi = G:getMinDamage(true) * k, G:getMaxDamage(true) * k
		add(server, battle, G, hidden({ type = "CREATURE_DAMAGE", subtype = "creatureDamageMin", val = lo, valueType = ENUM.BonusValueType.independentMax }))
		add(server, battle, G, hidden({ type = "CREATURE_DAMAGE", subtype = "creatureDamageMax", val = hi, valueType = ENUM.BonusValueType.independentMax }))
	end
	local heal = (M.HEAL[base] or {})[level]
	local spell = M.HEAL_SPELL[M.bare(unitKey)]
	if heal and spell then
		add(server, battle, G, hidden({ type = "SPECIFIC_SPELL_POWER", subtype = MOD .. spell, val = heal }))
	end
	add(server, battle, G, hidden({ type = M.MARK, stacking = M.LEVEL, val = level }))
	server:addUnitBonus(battle, G, {
		type = M.SHOW, val = level, duration = ENUM.BonusDuration.oneBattle, sourceType = ENUM.BonusSource.other,
		valueType = ENUM.BonusValueType.additiveValue, stacking = "h7WfShow"
	}, false)
	-- Max health changed, restore to full
	local lost = G:getMaxHealth() - G:getFirstHPleft()
	if G:getCount() == 1 and lost > 0 then
		local st = G:copy(); st:heal(lost, ENUM.HealLevel.heal, ENUM.HealPower.permanent); server:changeUnit(battle, st, lost)
	end
end

function M.hide(server, battle, O)
	local st = O:copy(); st:setGhost(true); st:setHadMorale(true); server:changeUnit(battle, st, 0)
end

function M.unhide(server, battle, O)
	local st = O:copy(); st:setGhost(false); server:changeUnit(battle, st, 0)
end

--- Add the H7 machine unitKey at O's position (part of the hexes original machines stand on is in the edge column of the battlefield, which normal stacks cannot enter, so it is added at the original position first,
--- then at the nearest free hex if that fails); returns G, or nil if it does not fit (O stays as it is)
function M.spawn(server, battle, side, hex, unitKey, count)
	local cr = LIBRARY:getCreatureByName(MOD .. M.PREFIX .. unitKey)
	if cr == nil then return nil end
	local info = { count = count or 1, type = cr, side = side, position = hex, summoned = true }
	if hex ~= nil and hex:isValid() then
		local ok, G = pcall(function() return server:addUnit(battle, info) end)
		if ok and G ~= nil then return G end
	end
	hex = battle:getAvailableHex(cr, side, hex)
	if hex == nil or not hex:isValid() then return nil end
	info.position = hex
	return server:addUnit(battle, info)
end

--- Round 428 (Yu 11-11: every bonus given to original machines must be checked for the H7 machines): from hero specialties, artifacts, spells, buildings, map objects and campaigns,
--- bonuses acting only on "this original machine" (specialties and artifacts limited to Ballista / Tent / Catapult / Ammo Cart, e.g. Ballista specialist Attack/Defense growth, an extra shot from the welding mask,
--- spells after attacking, extra health) that O has and G lacks are copied to G (whole battle, with the values already computed by level on O).
--- Those written by id (manual control, double chance, double power: subtype is the original machine's id) are changed to G's id.
--- Secondary skills are not copied: what Artillery, First Aid and Ballistics give H7 machines is written separately in warfareSkills.json (like the original machines), so copying would double it.
local COPY_SRC = {}
for _, k in ipairs({ "artifact", "artifactInstance", "objectType", "objectInstance", "spellEffect", "townStructure", "heroSpecial", "campaignBonus", "global" }) do
	if ENUM.BonusSource[k] ~= nil then COPY_SRC[ENUM.BonusSource[k]] = true end
end
local BY_SUBTYPE = { MANUAL_CONTROL = true, BONUS_DAMAGE_CHANCE = true, BONUS_DAMAGE_PERCENTAGE = true }
-- Secondary skills: the effects of Artillery, Ballistics and First Aid on H7 machines are written separately in warfareSkills.json of heroes-memorial.h7, not copied;
-- secondary skills of other mods naming the original machines (the Undead Emperor's Reaper: manual control of Catapult and Tent, damage cap etc.) are copied
local CORE_SKILL = { artillery = true, ballistics = true, firstAid = true }
local SEC = ENUM.BonusSource.secondarySkill

local function sig(b)
	return table.concat({ tostring(b:getType()), tostring(b:getSubtype()), tostring(b:getSource()), tostring(b:getSourceID()),
		tostring(b:getValType()), tostring(b:getStacking()) }, "|")   -- Values are not compared: the same bonus varying by level or count counts as already on G
end

function M.transfer(server, battle, O, G)
	local okO, listO = pcall(function() return O:getBonuses({}) end)
	local okG, listG = pcall(function() return G:getBonuses({}) end)
	if not okO or not okG or listO == nil or listG == nil then return 0 end
	local have = {}
	for i = 1, listG:size() do have[sig(listG:getBonus(i))] = true end
	local oKey = O:getCreature():getJsonKey()
	local oBare = M.bare(oKey)
	local gKey = G:getCreature():getJsonKey()
	local n = 0
	for i = 1, listO:size() do
		local b = listO:getBonus(i)
		local src = b:getSource()
		local okSrc = COPY_SRC[src]
		if not okSrc and SEC ~= nil and src == SEC then
			local sk = M.bare(tostring(b:getSourceID() or "")):gsub("^skill%.", "")
			okSrc = sk:match("^%a") ~= nil and not CORE_SKILL[sk]
		end
		if okSrc and not have[sig(b)] then
			local ty = tostring(b:getType())
			local sub = b:getSubtype()
			-- The source id reads back as a string; empty ones (common for hero specialties) are written as "-1", which fails to parse when written back, so it is only included when it looks like an identifier
			local sid = tostring(b:getSourceID() or "")
			local d = { type = ty, val = b:getVal(), valueType = b:getValType(), sourceType = b:getSource(),
				duration = ENUM.BonusDuration.oneBattle, stacking = b:getStacking(), hidden = b:isHidden() }
			if sid ~= "" and sid ~= "-1" and sid:match("^[%a]") then d.sourceID = sid else d.sourceType = ENUM.BonusSource.other end
			if sub ~= nil and sub ~= "" and sub ~= "none" then d.subtype = sub end
			-- Bonuses added as a percentage of a source (creature specialty "Attack/Defense +X% every N levels" is percentToTargetType and only scales the creature's own Attack/Defense):
			-- Lua cannot read the original entry's target source; creature specialties are all creature abilities, so it is written that way
			if b:getValType() == ENUM.BonusValueType.percentToTargetType then d.targetSourceType = ENUM.BonusSource.creatureAbility end
			if BY_SUBTYPE[ty] then
				local s = tostring(sub or "")
				if M.bare(s) == oBare or s == "creature." .. oBare then d.subtype = gKey else d = nil end
			end
			-- First Aid Tent healing bonuses (SPECIFIC_SPELL_POWER on the firstAid spell from specialties and artifacts): H7 healers use their own healing spell, so the same amount is added to it
			if d ~= nil and ty == "SPECIFIC_SPELL_POWER" and M.bare(tostring(sub or "")):gsub("^spell%.", "") == "firstAid" then
				local hs = M.HEAL_SPELL[M.bare(gKey)]
				if hs then d.subtype = MOD .. hs else d = nil end
			end
			if d ~= nil then
				local okP, par = pcall(function() return b:getParametersAsVector() end)
				if okP and par ~= nil and #par > 0 then d.addInfo = par end
				local okA = pcall(function() server:addUnitBonus(battle, G, d, true) end)
				if not okA then
					d.sourceID = nil; d.sourceType = ENUM.BonusSource.other
					okA = pcall(function() server:addUnitBonus(battle, G, d, true) end)
				end
				if okA then n = n + 1 end
			end
		end
	end
	return n
end

--- Original machine O to H7 machine: returns G on success
function M.swap(server, battle, O, unitKey, level)
	local side, hex = O:getSide(), O:getPosition()
	local atk = M.heroAttack(O)
	M.hide(server, battle, O)
	local G = M.spawn(server, battle, side, hex, unitKey, O:getCount())
	if G == nil then
		M.unhide(server, battle, O)
		return nil
	end
	M.transfer(server, battle, O, G)
	M.applyLevel(server, battle, G, unitKey, level, atk, M.ballistaK(O, G))
	add(server, battle, G, hidden({ type = M.MARK, stacking = M.LINK, val = O:unitID() }))
	return G
end

--- G dies: O dies with it (O is hidden, no animation)
function M.killOriginal(server, battle, O)
	if O == nil or not O:isAlive() then return end
	local h = O:getAvailableHealth()
	local st = O:copy(); st:damage(h); server:changeUnit(battle, st, -h)
end

-- ---- Shared by abilities: marks of lasting effects, Dark damage, healing -------------------------------------------------

local function byStacking(u, typeName, key)
	local ok, list = pcall(function()
		return u:getBonuses({ type = typeName }):filter(function(b) return b:getStacking() == key end)
	end)
	if not ok or list == nil then return nil end
	return list
end

--- Remove bonuses of type typeName with stacking key from u
function M.removeKey(server, battle, u, typeName, key)
	local list = byStacking(u, typeName, key)
	if list ~= nil and list:size() > 0 then server:removeUnitBonuses(battle, u, list) end
end

--- Set a mark (M.MARK, stacking key); turns omitted means the whole battle
function M.setMark(server, battle, u, key, val, turns)
	M.removeKey(server, battle, u, M.MARK, key)
	local d = { type = M.MARK, val = val, stacking = key, hidden = true, sourceType = ENUM.BonusSource.other,
		valueType = ENUM.BonusValueType.additiveValue, duration = ENUM.BonusDuration.oneBattle }
	if turns then d.duration = ENUM.BonusDuration.nTurns; d.turns = turns end
	server:addUnitBonus(battle, u, d, false)
end
function M.clearMark(server, battle, u, key) M.removeKey(server, battle, u, M.MARK, key) end

--- Add a lasting effect for display: combat event script script (heroes-memorial.h7:<script>, ${val} in the description = val), whole battle,
--- with the script counting the rounds itself (mark <script>|left). Adding it again only refreshes (the larger value wins)
function M.setEffect(server, battle, u, script, val, left, icon)
	local key = "h7Wf:" .. script
	local old = byStacking(u, "COMBAT_EVENT_TRIGGER", key)
	local oldVal = (old ~= nil and old:size() > 0) and old:getBonus(1):getVal() or 0
	if old ~= nil and old:size() > 0 then server:removeUnitBonuses(battle, u, old) end
	server:addUnitBonus(battle, u, {
		type = "COMBAT_EVENT_TRIGGER", subtype = MOD .. script, val = math.max(val, oldVal), stacking = key,
		duration = ENUM.BonusDuration.oneBattle, sourceType = ENUM.BonusSource.other,
		valueType = ENUM.BonusValueType.additiveValue, icon = icon
	}, false)
	if left ~= nil then M.setMark(server, battle, u, key .. "|left", left) end
end

function M.effectVal(u, script)
	local list = byStacking(u, "COMBAT_EVENT_TRIGGER", "h7Wf:" .. script)
	if list == nil or list:size() == 0 then return nil end
	return list:getBonus(1):getVal()
end

function M.clearEffect(server, battle, u, script)
	M.removeKey(server, battle, u, "COMBAT_EVENT_TRIGGER", "h7Wf:" .. script)
	M.clearMark(server, battle, u, "h7Wf:" .. script .. "|left")
end

--- For round start: remaining rounds -1, returns the value before (1 if no mark)
function M.tickLeft(server, battle, u, script)
	local key = "h7Wf:" .. script .. "|left"
	local left = M.mark(u, key) or 1
	if left - 1 > 0 then M.setMark(server, battle, u, key, left - 1) else M.clearEffect(server, battle, u, script) end
	return left
end

--- School damage (as h7AttackLib of heroes-memorial.h7: 0 with school or magic immunity, school damage reduction applied, invincible skipped); returns the damage dealt
function M.schoolHit(server, battle, target, amount, school, anim)
	if target == nil or not target:isAlive() or target:isGhost() or target:isInvincible() then return 0 end
	local A = require("heroes-memorial.h7:combat/h7AttackLib")
	local hurt = A.schoolDamage(target, math.floor(amount), school)
	if hurt <= 0 then return 0 end
	if anim and server:describeChanges() then
		server:showBattleAnimation(battle, { { unit = target } }, anim, "", 1.0, true)
	end
	local dealt, killed = server:damageUnit(battle, target, hurt)
	if server:describeChanges() then
		local ok, BattleLog = pcall(require, "battleLog")
		if ok and BattleLog and BattleLog.creaturesPerish then BattleLog.creaturesPerish(server, battle, target, killed) end
	end
	return dealt or hurt
end

--- Living allies these abilities can heal: not undead, constructs (NON_LIVING, MECHANICAL), war machines or arrow towers
function M.healable(u, allowUndead)
	if u == nil or not u:isAlive() or u:isGhost() or u:isTurret() then return false end
	if u:hasBonuses({ type = "SIEGE_WEAPON" }) or u:hasBonuses({ type = "NON_LIVING" }) or u:hasBonuses({ type = "MECHANICAL" }) then return false end
	if not allowUndead and u:hasBonuses({ type = "UNDEAD" }) then return false end
	return true
end

--- Normal healing (no resurrection), returns the amount restored
function M.heal(server, battle, u, amount)
	local lost = u:getMaxHealth() - u:getFirstHPleft()
	local h = math.min(math.floor(amount), lost)
	if h <= 0 then return 0 end
	server:healUnit(battle, u, h, ENUM.HealLevel.heal, ENUM.HealPower.permanent)
	return h
end

--- Battle log (valueDescriptions of H7_LOG_W_H7C)
function M.log(server, battle, n, strings, numbers)
	if not server:describeChanges() then return end
	server:appendLog(battle, {
		append = { "core.bonus.H7_LOG_W_H7C.description." .. tostring(n) },
		replaceStrings = strings or {}, replaceNumbers = numbers or {}
	})
end

function M.name(u)
	return u:getCreature():getNameTextID(u:getCount())
end

return M
