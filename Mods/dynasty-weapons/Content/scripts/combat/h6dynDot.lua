--- H6 Dynasty Weapons: damage over time (Void Bane, Lightning Lash, Deadly Toxin...), attached by the dot parameter of the active ability h6dynAct.
--- At the start of each round (from round 2, the engine's onRoundStart) the stack carrying it takes val damage (through Heavenly Armor / Frost Armor first).
--- At the start of a round the engine decrements N_TURNS before triggering onRoundStart, so when attaching, turns = the count in the description + 1.
--- bonuses: bonuses attached again after each damage; status: original H6 statuses cast after each damage (Lightning Lash's daze, since round 316t)
--- Parameters: spread (chance % to spread to adjacent stacks of the same side at the start of each round), spreadTurns (turns of the spread copies, also count + 1),
---       anim (hit effect), spell (spell used for the battle log, description and icon), tag (stacking, to check whether the other already has it)
--- Not settled in the round it spreads: the infected stack gets a hidden mark H6DYN_FRESH (stacking group = tag) lasting until the start of next round, and is skipped once while it has it.
---       raw (damage per round not adjusted for the target; review B7, 2026-11-08): at cast time val is already converted for the original target's school reduction / immunity (spells/h6dynAct),
---       and the spread copy is converted again for the new target (spell adjustDamage, with any living stack of the opposite side as the caster, through which the hero's spell damage bonus is found);
---       no spreading if the new target's converted value is 0 (immune). Old saves without raw copy val as before.
local Base = require("combat/combatScript")
local Lib = require("spells/h6dynLib")
local BattleLog = require("battleLog")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Display bonuses attached at runtime get a description and icon (spell name + the spell's status icon)
local function shown(spellKey)
	local spell = spellKey and LIBRARY:getSpellByName(spellKey) or nil
	if not spell then return {} end
	local key = spellKey:match(":(.+)$") or spellKey
	return { description = "@" .. spell:getNameTextID(), icon = "h6dyn/spells/" .. key .. "/Effect" }
end

--- Damage per round spread to o: converted again for o when raw is present
function Script:spreadValue(battle, unit, o)
	local v = self.val or 0
	if self.raw == nil or self.spell == nil then return v end
	local spell = LIBRARY:getSpellByName(self.spell)
	if not spell then return v end
	local side = Lib.opposite(unit:getSide())
	local actor = nil
	for _, x in ipairs(battle:getUnitsIf(function(x) return x:getSide() == side and x:isAlive() and not x:isTurret() end)) do actor = x; break end
	if not actor then return self.raw end
	local ok, adj = pcall(function() return spell:adjustDamage(battle, actor, o, self.raw) end)
	if ok and type(adj) == "number" then return math.floor(adj) end
	return v
end

function Script:onRoundStart(server, battle, unit)
	if not unit:isAlive() or unit:isInvincible() then return end
	local v = self.val or 0
	if v <= 0 then return end
	if self.tag and Lib.byStacking(unit, { type = "H6DYN_FRESH" }, self.tag):size() > 0 then return end
	local extra = shown(self.spell)
	-- Spread first (by positions at the start of the round), then deal damage
	if (self.spread or 0) > 0 and self.tag then
		local around = unit:getSurroundingHexes()
		for i = 1, around:size() do
			local o = battle:getUnitByPos(around:at(i), true)
			if o and o:unitID() ~= unit:unitID() and o:getSide() == unit:getSide() and o:isAlive() and not o:isTurret()
				and Lib.byStacking(o, { type = "COMBAT_EVENT_TRIGGER" }, self.tag):size() == 0
				and server:rngInt(1, 100) <= self.spread then
				local ov = self:spreadValue(battle, unit, o)
				if ov > 0 then
					Lib.addBonus(server, battle, o, {
						type = "COMBAT_EVENT_TRIGGER", subtype = Lib.MOD .. ":h6dynDot", val = ov,
						duration = "N_TURNS", turns = math.max(1, self.spreadTurns or 1), sourceType = "SPELL_EFFECT",
						sourceID = self.spell, stacking = self.tag,
						addInfo = { spread = self.spread, spreadTurns = self.spreadTurns, anim = self.anim, spell = self.spell, tag = self.tag, bonuses = self.bonuses, status = self.status, raw = self.raw }
					}, "SPELL_EFFECT", self.spell, false, extra)
					server:addUnitBonus(battle, o, {
						type = "H6DYN_FRESH", val = 1, duration = "N_TURNS", turns = 1, sourceType = "OTHER", stacking = self.tag, hidden = true
					}, false)
				end
			end
		end
	end
	if self.anim and self.anim ~= "" then
		server:showBattleAnimation(battle, { { unit = unit } }, self.anim, "", 1.0, true)
	end
	local dmg, killed = Lib.damage(server, battle, unit, v)
	if unit:isAlive() then
		for _, b in pairs(self.bonuses or {}) do Lib.addBonus(server, battle, unit, b, "SPELL_EFFECT", self.spell, false, extra) end
		Lib.statuses(server, battle, unit, self.status)
	end
	local spell = self.spell and LIBRARY:getSpellByName(self.spell) or nil
	if spell and dmg and dmg > 0 then
		BattleLog.spellDamage(server, battle, spell, unit, dmg, killed or 0)
	end
	if (not dmg or dmg <= 0) and self.anim and self.anim ~= "" then server:refreshBattleUnits(battle) end
end

return Script
