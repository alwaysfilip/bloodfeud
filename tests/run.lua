-- Offline test runner for the pure core (no WoW client needed).
-- Usage, from the repository root:  luajit tests/run.lua [filter]
local root = (arg and arg[0] or ""):match("^(.*)/tests/run%.lua$") or "."
package.path = root .. "/tests/?.lua;" .. package.path

bit = bit or require("bit") -- luacheck: ignore

local filter = arg and arg[1]

local T = { passed = 0, failed = 0, failures = {}, root = root }

--- A fresh addon namespace with the pure core modules loaded, exactly the way
--- the game loads them: each file is called with (addonName, namespace).
function T.load()
	local ns = {}
	for _, name in ipairs({ "Util", "Codec", "Store", "Permissions", "Sync" }) do
		local chunk = assert(loadfile(root .. "/Core/" .. name .. ".lua"))
		chunk("BusinessMeeting", ns)
	end
	return ns
end

function T.test(name, fn)
	if filter and not name:find(filter, 1, true) then return end
	local started = os.clock()
	local ok, err = xpcall(fn, debug.traceback)
	local took = os.clock() - started
	if ok then
		T.passed = T.passed + 1
		io.write(string.format("  ok    %-62s %6.2fs\n", name, took))
	else
		T.failed = T.failed + 1
		T.failures[#T.failures + 1] = name .. "\n" .. tostring(err)
		io.write(string.format("  FAIL  %s\n", name))
	end
end

function T.eq(got, want, msg)
	if got ~= want then
		error(string.format("%s: expected %s, got %s", msg or "values differ", tostring(want), tostring(got)), 2)
	end
end

function T.ok(value, msg)
	if not value then error(msg or "assertion failed", 2) end
	return value
end

for _, file in ipairs({ "test_util", "test_codec", "test_store", "test_sync", "test_progress", "test_game" }) do
	io.write(file .. "\n")
	local chunk = assert(loadfile(root .. "/tests/" .. file .. ".lua"))
	chunk(T)
end

io.write(string.format("\n%d passed, %d failed\n", T.passed, T.failed))
for _, f in ipairs(T.failures) do
	io.write("\n--- " .. f .. "\n")
end
os.exit(T.failed == 0 and 0 or 1)
