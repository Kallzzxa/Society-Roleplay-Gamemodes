-- ============================================================
-- Society Roleplay - Skema Database MySQL
-- Server roleplay Indonesia bertema oldschool (SA-MP 0.3.7 R2)
--
-- Cara pakai:
--   1. Buat database:  CREATE DATABASE society_rp;
--   2. Import file ini: mysql -u root -p society_rp < society.sql
--      (atau via phpMyAdmin: pilih database -> Import -> pilih file ini)
--
-- Catatan: kata sandi akun disimpan sebagai hash SHA256 (64 karakter hex).
-- ============================================================

CREATE TABLE IF NOT EXISTS `accounts` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `username` VARCHAR(24) UNIQUE NOT NULL,
    `password` CHAR(64) NOT NULL,
    `email` VARCHAR(64) DEFAULT NULL,
    `register_date` DATETIME DEFAULT CURRENT_TIMESTAMP,
    `last_login` DATETIME DEFAULT NULL,
    `admin` TINYINT DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `characters` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `account_id` INT NOT NULL,
    `name` VARCHAR(24) UNIQUE NOT NULL,
    `age` TINYINT DEFAULT 17,
    `gender` TINYINT DEFAULT 0,
    `skin` INT DEFAULT 0,
    `money` INT DEFAULT 500000,
    `bank` INT DEFAULT 0,
    `level` INT DEFAULT 1,
    `exp` INT DEFAULT 0,
    `pos_x` FLOAT DEFAULT 1481.0,
    `pos_y` FLOAT DEFAULT -1724.0,
    `pos_z` FLOAT DEFAULT 13.5,
    `interior` INT DEFAULT 0,
    `vw` INT DEFAULT 0,
    `health` FLOAT DEFAULT 100.0,
    `armour` FLOAT DEFAULT 0.0,
    `hunger` FLOAT DEFAULT 100.0,
    `thirst` FLOAT DEFAULT 100.0,
    `stress` FLOAT DEFAULT 0.0,
    `created` DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_account_id` (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Untuk database yang sudah ada (dibuat sebelum update ini), jalankan:
-- ALTER TABLE `characters` ADD COLUMN `hunger` FLOAT DEFAULT 100.0;
-- ALTER TABLE `characters` ADD COLUMN `thirst` FLOAT DEFAULT 100.0;
-- ALTER TABLE `characters` ADD COLUMN `stress` FLOAT DEFAULT 0.0;

CREATE TABLE IF NOT EXISTS `businesses` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(32) NOT NULL,
    `owner_char_id` INT DEFAULT 0,
    `type` TINYINT DEFAULT 0,
    `price` INT DEFAULT 0,
    `profit` INT DEFAULT 0,
    `pos_x` FLOAT NOT NULL,
    `pos_y` FLOAT NOT NULL,
    `pos_z` FLOAT NOT NULL,
    `locked` TINYINT DEFAULT 0,
    INDEX `idx_owner_char_id` (`owner_char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Untuk database yang sudah ada (dibuat sebelum update bisnis dinamis), jalankan:
-- (cukup import ulang blok CREATE TABLE `businesses` di atas)
