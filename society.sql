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
    `faction_id` INT DEFAULT 0,
    `faction_rank` TINYINT DEFAULT 0,
    `family_id` INT DEFAULT 0,
    `family_rank` TINYINT DEFAULT 0,
    `created` DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_account_id` (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Untuk database yang sudah ada (dibuat sebelum update ini), jalankan:
-- ALTER TABLE `characters` ADD COLUMN `hunger` FLOAT DEFAULT 100.0;
-- ALTER TABLE `characters` ADD COLUMN `thirst` FLOAT DEFAULT 100.0;
-- ALTER TABLE `characters` ADD COLUMN `stress` FLOAT DEFAULT 0.0;
-- ALTER TABLE `characters` ADD COLUMN `faction_id` INT DEFAULT 0;
-- ALTER TABLE `characters` ADD COLUMN `faction_rank` TINYINT DEFAULT 0;
-- ALTER TABLE `characters` ADD COLUMN `family_id` INT DEFAULT 0;
-- ALTER TABLE `characters` ADD COLUMN `family_rank` TINYINT DEFAULT 0;

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

CREATE TABLE IF NOT EXISTS `houses` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `owner_char_id` INT DEFAULT 0,
    `price` INT DEFAULT 0,
    `ent_x` FLOAT NOT NULL,
    `ent_y` FLOAT NOT NULL,
    `ent_z` FLOAT NOT NULL,
    `ent_int` INT DEFAULT 0,
    `ent_vw` INT DEFAULT 0,
    `exit_x` FLOAT NOT NULL,
    `exit_y` FLOAT NOT NULL,
    `exit_z` FLOAT NOT NULL,
    `exit_int` INT DEFAULT 0,
    `locked` TINYINT DEFAULT 0,
    INDEX `idx_house_owner` (`owner_char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Untuk database yang sudah ada (dibuat sebelum update rumah dinamis), jalankan:
-- (cukup import ulang blok CREATE TABLE `houses` di atas)

CREATE TABLE IF NOT EXISTS `player_vehicles` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `char_id` INT NOT NULL,
    `model` INT NOT NULL,
    `pos_x` FLOAT NOT NULL,
    `pos_y` FLOAT NOT NULL,
    `pos_z` FLOAT NOT NULL,
    `angle` FLOAT DEFAULT 0.0,
    `color1` INT DEFAULT 0,
    `color2` INT DEFAULT 0,
    `plate` VARCHAR(16) NOT NULL,
    `locked` TINYINT DEFAULT 0,
    `fuel` FLOAT DEFAULT 100.0,
    `garage_id` INT DEFAULT 0,
    INDEX `idx_vehicle_char` (`char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Untuk database yang sudah ada (dibuat sebelum update kendaraan pribadi), jalankan:
-- (cukup import ulang blok CREATE TABLE `player_vehicles` di atas)

-- Skema fraksi dinamis (update 2026-10-14).
-- type: 0=LSPD, 1=EMS, 2=Pemerintah, 3=Montir, 4=News.
-- leader_char_id: id karakter ketua (0 = belum ada ketua).
-- cash: kas fraksi (disetor via /fdeposit, diambil ketua via /fwithdraw).
CREATE TABLE IF NOT EXISTS `factions` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(32) NOT NULL,
    `type` TINYINT DEFAULT 0,
    `color` INT DEFAULT 0,
    `spawn_x` FLOAT NOT NULL,
    `spawn_y` FLOAT NOT NULL,
    `spawn_z` FLOAT NOT NULL,
    `spawn_angle` FLOAT DEFAULT 0.0,
    `leader_char_id` INT DEFAULT 0,
    `cash` INT DEFAULT 0,
    INDEX `idx_faction_leader` (`leader_char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Untuk database yang sudah ada (dibuat sebelum update fraksi dinamis), jalankan:
-- (cukup import ulang blok CREATE TABLE `factions` di atas)

-- Skema bengkel dinamis (update 2026-10-14).
-- owner_char_id: id karakter pemilik (0 = belum ada pemilik / masih dijual).
-- profit: keuntungan dari jasa pelanggan (/repair & /mod), diambil via /wswithdraw.
CREATE TABLE IF NOT EXISTS `workshops` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(32) NOT NULL,
    `owner_char_id` INT DEFAULT 0,
    `price` INT DEFAULT 0,
    `profit` INT DEFAULT 0,
    `pos_x` FLOAT NOT NULL,
    `pos_y` FLOAT NOT NULL,
    `pos_z` FLOAT NOT NULL,
    INDEX `idx_workshop_owner` (`owner_char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Untuk database yang sudah ada (dibuat sebelum update bengkel dinamis), jalankan:
-- (cukup import ulang blok CREATE TABLE `workshops` di atas)

-- Skema garasi kota dinamis (update 2026-10-14).
-- fee: biaya titip per kendaraan, dibayar pemain saat menyimpan kendaraan.
-- Kendaraan yang dititipkan tercatat di player_vehicles.garage_id
-- (0 = di jalanan, >0 = id garasi tempat kendaraan tersimpan).
CREATE TABLE IF NOT EXISTS `garages` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(32) NOT NULL,
    `pos_x` FLOAT NOT NULL,
    `pos_y` FLOAT NOT NULL,
    `pos_z` FLOAT NOT NULL,
    `fee` INT DEFAULT 0,
    INDEX `idx_garage_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Untuk database yang sudah ada (dibuat sebelum update garasi kota), jalankan:
-- ALTER TABLE `player_vehicles` ADD COLUMN `garage_id` INT DEFAULT 0 AFTER `fuel`;
-- (cukup import ulang blok CREATE TABLE `garages` di atas)

-- Skema keluarga/gangster dinamis (update 2026-10-14).
-- name: nama keluarga. color: warna identitas (0xRRGGBB) untuk nama
-- anggota & chat. leader_char_id: id karakter ketua (0 = belum ada).
-- cash: kas keluarga (setor via /famdeposit, ambil ketua via /famwithdraw).
-- Keanggotaan tersimpan di kolom characters (family_id, family_rank).
CREATE TABLE IF NOT EXISTS `families` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(32) NOT NULL,
    `color` INT DEFAULT 0,
    `leader_char_id` INT DEFAULT 0,
    `cash` INT DEFAULT 0,
    INDEX `idx_family_leader` (`leader_char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Untuk database yang sudah ada (dibuat sebelum update keluarga dinamis), jalankan:
-- (cukup import ulang blok CREATE TABLE `families` di atas)

-- Skema zona dinamis (update 2026-10-14).
-- type: 0 = Greenzone (damage & tembakan dinonaktifkan di dalam area),
--       1 = Zona Bahaya (penanda area berbahaya, damage tetap jalan).
-- Area berbentuk persegi dari (min_x, min_y) ke (max_x, max_y).
CREATE TABLE IF NOT EXISTS `zones` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(32) NOT NULL,
    `type` INT DEFAULT 0,
    `min_x` FLOAT NOT NULL,
    `min_y` FLOAT NOT NULL,
    `max_x` FLOAT NOT NULL,
    `max_y` FLOAT NOT NULL,
    INDEX `idx_zone_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Untuk database yang sudah ada (dibuat sebelum update zona dinamis), jalankan:
-- (cukup import ulang blok CREATE TABLE `zones` di atas)
