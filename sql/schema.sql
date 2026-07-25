-- Whestone EMS – Datenbankschema (MariaDB, Datenbank: whestone_ems)

CREATE TABLE IF NOT EXISTS `players` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `license` VARCHAR(64) NOT NULL,
    `name` VARCHAR(64) NOT NULL DEFAULT 'Unbekannt',
    `job` VARCHAR(32) NOT NULL DEFAULT 'police',
    `rank` TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `xp` INT UNSIGNED NOT NULL DEFAULT 0,
    `stats` LONGTEXT NOT NULL DEFAULT '{}',
    `skills` LONGTEXT NOT NULL DEFAULT '{}',
    `skillpoints` INT UNSIGNED NOT NULL DEFAULT 0,
    `jobdata` LONGTEXT NOT NULL DEFAULT '{}',
    `position` VARCHAR(255) DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `last_seen` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `license` (`license`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;
