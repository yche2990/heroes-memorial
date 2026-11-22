--- Heroes VII creatures and spells (heroes-memorial.h7) batch A: helpers shared by adjacent auras, marks and hex distances.
--- Only loaded with require("heroes-memorial.h7:combat/h7AuraLib"), not registered as a script.
---
--- Adjacent ally auras (Cleansing Aura, Pure Aura, Light Resistance of Heart of Darkness, Raise Shields, Soul Fire, Treant Symbiosis, Inspiring Presence, Fire Aura):
---   JSON auras (BATTLE_WIDE + UNIT_ADJACENT + ["noneOf","OPPOSITE_SIDE"]) reach no ally at all in this engine (checklist section 10, "friend or foe direction"),
---   so as h5AllyAura of the H5 mod, the script decides with battle:isHostile (hypnotized stacks count for their controller), adds temporary bonuses to adjacent allies and removes them when no longer adjacent.
---   Recalculated at battle start, at the start of each round, when an aura creature dies (the aura creature's own script), and after any stack's action (battle-wide hidden script combat/h7AuraZone).
---   The same aura does not stack (however many aura creatures are adjacent, only the largest value counts).
---   Kinds are told apart by the COMBAT_EVENT_TRIGGER subtype (script name) on the aura creature; the value is that bonus's val.

local Proxy = require("lib/kadAiProxy")   -- Round 352: precise bonus removal (removal ignores the stacking group, see removeExact)
local Imm = require("heroes-memorial.h7:combat/h7ImmuneLib")

local M = {}

M.MOD = "heroes-memorial.h7"
M.MARK = "H7_AURA_MARK_H7C"
M.LOG = "H7_LOG_A_H7C"
M.ZONE = "h7AuraZone"

local D = ENUM.BonusDuration

-- ---- Hex distance (same as the engine's BattleHex::getDistance) --------------------------------------------------

function M.hexDistance(a, b)
	local y1, y2 = a:getY(), b:getY()
	local x1 = a:getX() + math.floor(y1 / 2)
	local x2 = b:getX() + math.floor(y2 / 2)
	local dx, dy = x2 - x1, y2 - y1
	if (dx >= 0 and dy >= 0) or (dx < 0 and dy < 0) then
		return math.max(math.abs(dx), math.abs(dy))
	end
	return math.abs(dx) + math.abs(dy)
end

--- Shortest distance between two stacks (over every hex they occupy; both hexes for two-hex creatures)
function M.unitDistance(a, b)
	local ha, hb = a:getHexes(), b:getHexes()
	local best = 1000
	for i = 1, ha:size() do
		for j = 1, hb:size() do
			local d = M.hexDistance(ha:at(i), hb:at(j))
			if d < best then best = d end
		end
	end
	return best
end

function M.adjacent(a, b)
	return a:unitID() ~= b:unitID() and M.unitDistance(a, b) == 1
end

-- ---- Stacks and bonuses ---------------------------------------------------------------------------------

function M.real(u)
	return u ~= nil and u:isAlive() and not u:isGhost() and not u:isTurret()
end

function M.friendly(battle, a, b)
	return not battle:isHostile(a, b)
end

--- A scripted ability on the creature (COMBAT_EVENT_TRIGGER whose subtype is name or ends with ":name"); returns the one with the largest value
function M.ability(unit, name)
	local best = nil
	local list = unit:getBonuses({ type = "COMBAT_EVENT_TRIGGER" })
	for i = 1, list:size() do
		local b = list:getBonus(i)
		local sub = b:getSubtype() or ""
		if sub == name or sub:sub(-(#name + 1)) == ":" .. name then
			if best == nil or b:getVal() > best:getVal() then best = b end
		end
	end
	return best
end

function M.byStacking(unit, typeName, key)
	return unit:getBonuses({ type = typeName }):filter(function(b) return b:getStacking() == key end)
end

function M.removeByStacking(server, battle, unit, typeName, key)
	local list = M.byStacking(unit, typeName, key)
	if list:size() > 0 then Proxy.removeExact(server, battle, unit, list) end
end

function M.markValue(unit, key)
	local list = M.byStacking(unit, M.MARK, key)
	if list:size() == 0 then return nil end
	return list:getBonus(1):getVal()
end

function M.clearMark(server, battle, unit, key)
	M.removeByStacking(server, battle, unit, M.MARK, key)
end

--- turns = nil: whole battle; otherwise N rounds (this round counts as 1)
function M.setMark(server, battle, unit, key, val, turns)
	M.clearMark(server, battle, unit, key)
	local d = {
		type = M.MARK, val = val, hidden = true, stacking = key,
		sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey()
	}
	if turns then d.duration = D.nTurns; d.turns = turns else d.duration = D.oneBattle end
	server:addUnitBonus(battle, unit, d, true)
end

function M.name(unit)
	return unit:getCreature():getNameTextID(unit:getCount())
end

--- Battle log (texts in the valueDescriptions of H7_LOG_A_H7C)
function M.log(server, battle, n, strings, numbers)
	server:appendLog(battle, {
		append = { "core.bonus." .. M.LOG .. ".description." .. n },
		replaceStrings = strings or {},
		replaceNumbers = numbers or {}
	})
end

--- Dispel one random negative spell effect (source is a spell, the spell is negative, not permanent). Returns whether something was dispelled
function M.dispelOneNegative(server, battle, unit)
	local list = unit:getBonuses({ sourceType = ENUM.BonusSource.spellEffect })
	local keys, seen = {}, {}
	for i = 1, list:size() do
		local b = list:getBonus(i)
		local sid = b:getSourceID()
		if sid ~= nil and not seen[sid] then
			seen[sid] = true
			local sp = Imm.resolve(sid)
			if sp ~= nil and sp:isNegative() and not sp:isPersistent() and not sp:isAdventure() then
				table.insert(keys, sid)
			end
		end
	end
	if #keys == 0 then return false end
	local pick = keys[server:rngInt(1, #keys)]
	local rm = list:filter(function(b) return b:getSourceID() == pick end)
	if rm:size() > 0 then server:removeUnitBonuses(battle, unit, rm) end
	return true
end

-- ---- Adjacent ally auras -------------------------------------------------------------------------------
--- self: the aura creature benefits too; sticky: not removed when no longer adjacent (Soul Fire: lasts until the end of that stack's own next action);
--- eff(v): the actual effect (hidden); show: bonus type for display (icon and description registered in bonuses.json, ${val} is the shown value);
--- immune: temporarily adds a set of SPELL_IMMUNITY (h7ImmuneLib's list, filtered by school); onApply: extra work when first added
M.KINDS = {
	h7AuraOfCleansing = {
		self = true, show = "H7_AURA_CLEANSING_H7C",
		eff = function(v) return { { type = "PRIMARY_SKILL", subtype = "primarySkill.defence", val = v } } end
	},
	h7AuraOfPurity = {
		self = true, show = "H7_AURA_PURITY_H7C", immune = "any",
		eff = function(v) return {} end
	},
	h7HeartOfDarkness = {
		self = true, show = "H7_AURA_HEARTDARK_H7C",
		eff = function(v) return { { type = "SPELL_DAMAGE_REDUCTION", subtype = "tears-of-ashan:spellSchool.01lightSchool", val = v } } end
	},
	h7SHIELDING = {
		self = false, show = "H7_AURA_SHIELD_H7C",
		eff = function(v) return { { type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll", val = v } } end
	},
	h7Soulfire = {
		self = false, sticky = true, show = "H7_AURA_SOULFIRE_H7C",
		eff = function(v) return { { type = "MORALE", val = 1 }, { type = "STACKS_SPEED", val = v } } end
	},
	h7TreantSynergy = {
		self = true, show = "H7_AURA_TREANT_H7C",
		eff = function(v) return { { type = "PRIMARY_SKILL", subtype = "primarySkill.defence", val = v } } end
	},
	h7InspiringPresence = {
		self = true, show = "H7_AURA_INSPIRE_H7C",
		eff = function(v) return { { type = "MORALE", val = v }, { type = "LUCK", val = v } } end
	},
	h7AuraOfFire = {
		self = true, show = "H7_AURA_FIRE_H7C",
		eff = function(v) return { { type = "NEGATIVE_EFFECTS_IMMUNITY", subtype = "spellSchool.earth" } } end,
		onApply = function(server, battle, u) Imm.stripSchool(server, battle, u, "earth") end
	},
}
M.ORDER = { "h7AuraOfCleansing", "h7AuraOfPurity", "h7HeartOfDarkness", "h7SHIELDING", "h7Soulfire",
	"h7TreantSynergy", "h7InspiringPresence", "h7AuraOfFire" }

local function stackKey(kind) return "h7Aura|" .. kind end
M.stackKey = stackKey

--- Currently shown value (nil if none)
function M.auraValue(u, kind)
	local list = M.byStacking(u, M.KINDS[kind].show, stackKey(kind))
	if list:size() == 0 then return nil end
	return list:getBonus(1):getVal()
end

function M.removeAura(server, battle, u, kind)
	local K = M.KINDS[kind]
	local key = stackKey(kind)
	local types = { [K.show] = true }
	for _, e in ipairs(K.eff(1)) do types[e.type] = true end
	for t, _ in pairs(types) do M.removeByStacking(server, battle, u, t, key) end
	if K.immune then Imm.clear(server, battle, u, key) end
end

local function addAura(server, battle, u, kind, v, src)
	local K = M.KINDS[kind]
	local key = stackKey(kind)
	for _, e in ipairs(K.eff(v)) do
		local d = {
			type = e.type, val = e.val or 0, duration = D.oneBattle,
			sourceType = ENUM.BonusSource.other, sourceID = src, stacking = key, hidden = true
		}
		if e.subtype then d.subtype = e.subtype end
		server:addUnitBonus(battle, u, d, true)
	end
	server:addUnitBonus(battle, u, {
		type = K.show, val = v, duration = D.oneBattle,
		sourceType = ENUM.BonusSource.other, sourceID = src, stacking = key
	}, true)
	if K.immune then Imm.ensure(server, battle, u, key, Imm.debuffs(K.immune), src) end
	if K.onApply then K.onApply(server, battle, u) end
end

--- Stacks with auras on the field: { [kind] = { {unit=u, val=v}, ... } }
function M.bearers(battle)
	local out = {}
	local list = battle:getUnitsIf(function(u) return M.real(u) end)
	for _, u in ipairs(list) do
		local cl = u:getBonuses({ type = "COMBAT_EVENT_TRIGGER" })
		for i = 1, cl:size() do
			local b = cl:getBonus(i)
			local sub = b:getSubtype() or ""
			local kind = string.match(sub, "([^:]+)$")
			if kind ~= nil and M.KINDS[kind] ~= nil then
				out[kind] = out[kind] or {}
				table.insert(out[kind], { unit = u, val = b:getVal() })
			end
		end
	end
	return out
end

--- Aura value a stack should get (nil if none) and the source creature
function M.bestFor(battle, by, kind, u)
	local K = M.KINDS[kind]
	local best, src = nil, nil
	for _, e in ipairs(by[kind] or {}) do
		local c = e.unit
		local ok
		if c:unitID() == u:unitID() then
			ok = K.self
		else
			ok = M.friendly(battle, c, u) and M.unitDistance(c, u) == 1
		end
		if ok and (best == nil or e.val > best) then best, src = e.val, c:getCreature():getJsonKey() end
	end
	return best, src
end

function M.refresh(server, battle)
	if battle:getTacticDistance() > 0 then return end
	local by = M.bearers(battle)
	local units = battle:getUnitsIf(function(u) return M.real(u) end)
	for _, kind in ipairs(M.ORDER) do
		local K = M.KINDS[kind]
		local has = by[kind] ~= nil
		for _, u in ipairs(units) do
			local cur = M.auraValue(u, kind)
			if has or cur ~= nil then
				local best, src = nil, nil
				if has then best, src = M.bestFor(battle, by, kind, u) end
				if best ~= nil and cur ~= best then
					if cur ~= nil then M.removeAura(server, battle, u, kind) end
					addAura(server, battle, u, kind, best, src)
				elseif best == nil and cur ~= nil and not K.sticky then
					M.removeAura(server, battle, u, kind)
				end
			end
		end
	end
end

--- End of the stack's own action: Soul Fire (sticky) is removed if it is no longer next to a Fire Spirit
function M.actorDone(server, battle, actor)
	if not actor:isAlive() then return end
	if M.auraValue(actor, "h7Soulfire") == nil then return end
	local by = M.bearers(battle)
	local best = M.bestFor(battle, by, "h7Soulfire", actor)
	if best == nil then M.removeAura(server, battle, actor, "h7Soulfire") end
end

--- Whether a (living) stack with a given ability is on the field
function M.present(battle, name)
	local found = battle:getUnitsIf(function(u) return M.real(u) and M.ability(u, name) ~= nil end)
	return #found > 0
end

return M
