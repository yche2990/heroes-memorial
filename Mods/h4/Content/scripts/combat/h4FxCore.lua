--- Heroes IV Memorial: Heroes IV effects for the engine's own combat scripts (Fire Shield, Life Drain, Rebirth, Death Stare).
--- Rules all follow the engine's scripts (called directly); only the animations they play are replaced, so engine rule changes carry over automatically.
--- How: server is wrapped, and when the original script calls showBattleAnimation / castSpell the Heroes IV effect is used instead.
local M = {}

--- Proxy for server: fx(battle, targets, anim, sound, transparency, deferred) replaces the animation; other methods are passed to server unchanged
function M.proxy(server, fx, cast)
	return setmetatable({}, { __index = function(_, k)
		if k == "showBattleAnimation" and fx then
			return function(_, battle, targets, anim, sound, transparency, deferred)
				return fx(battle, targets, anim, sound, transparency, deferred)
			end
		end
		if k == "castSpell" and cast then
			return function(_, battle, caster, spell, targets, value) return cast(battle, caster, spell, targets, value) end
		end
		local f = server[k]
		if type(f) == "function" then return function(_, ...) return f(server, ...) end end
		return f
	end })
end

return M
