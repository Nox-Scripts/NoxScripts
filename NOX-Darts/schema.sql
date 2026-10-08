CREATE TABLE IF NOT EXISTS `prp_dartboards` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `x` FLOAT NOT NULL,
    `y` FLOAT NOT NULL,
    `z` FLOAT NOT NULL,
    `rot_x` FLOAT NOT NULL,
    `rot_y` FLOAT NOT NULL,
    `rot_z` FLOAT NOT NULL,
    PRIMARY KEY (`id`)
);

CREATE TABLE IF NOT EXISTS `prp_dartboard_payouts` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(128) NOT NULL,
    `amount` BIGINT UNSIGNED NOT NULL,
    `money_type` VARCHAR(32) NOT NULL,
    `reason` VARCHAR(255) NULL,
    `status` VARCHAR(16) NOT NULL DEFAULT 'pending',
    `delivery_token` VARCHAR(128) NULL,
    `processing_at` TIMESTAMP NULL,
    `settlement_key` VARCHAR(191) NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_prp_dartboard_payouts_identifier` (`identifier`),
    KEY `idx_prp_dartboard_payouts_pending` (`identifier`, `status`),
    UNIQUE KEY `uq_prp_dartboard_payouts_settlement` (`settlement_key`)
);

CREATE TABLE IF NOT EXISTS `prp_dartboard_active_games` (
    `game_uuid` VARCHAR(64) NOT NULL,
    `board_id` INT UNSIGNED NULL,
    `player_one_identifier` VARCHAR(128) NOT NULL,
    `player_two_identifier` VARCHAR(128) NOT NULL,
    `wager` BIGINT UNSIGNED NOT NULL,
    `money_type` VARCHAR(32) NOT NULL,
    `outcome` VARCHAR(16) NOT NULL DEFAULT 'active',
    `winner_identifier` VARCHAR(128) NULL,
    `settlement_reason` VARCHAR(255) NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`game_uuid`)
);
