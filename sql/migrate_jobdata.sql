-- Migration: Progression je Job (jobdata) - bestehende Werte wandern zur Polizei-Laufbahn
ALTER TABLE players ADD COLUMN IF NOT EXISTS jobdata LONGTEXT NOT NULL DEFAULT '{}';
UPDATE players
SET jobdata = CONCAT(
    '{"police":{"rank":', `rank`,
    ',"xp":', xp,
    ',"skillpoints":', skillpoints,
    ',"skills":', IF(skills IS NULL OR skills = '', '{}', skills),
    '}}')
WHERE jobdata = '{}' OR jobdata IS NULL;
SELECT name, jobdata FROM players;
