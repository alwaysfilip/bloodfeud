-- Blood Feud was renamed Business Meeting - PvP in 0.4.0. The game keeps an
-- addon's saved data in a file named after the addon's folder, so the new
-- addon cannot read the old one's file. This stand-in, under the old name,
-- can: the game loads the old data for it, and Business Meeting - PvP (which
-- loads after it) takes the data over and then switches this off.
--
-- Unpacking the new version over an old Blood Feud folder also replaces its
-- list of files with this one, so the old code no longer runs.
BloodFeudLegacy = true -- luacheck: ignore
