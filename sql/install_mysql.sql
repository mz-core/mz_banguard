CREATE TABLE IF NOT EXISTS mz_bans (
  id VARCHAR(36) NOT NULL,
  public_id VARCHAR(32) NOT NULL,
  player_name VARCHAR(120) NULL,
  reason TEXT NOT NULL,
  banned_by VARCHAR(120) NULL,
  banned_by_identifier VARCHAR(180) NULL,
  identifiers LONGTEXT NOT NULL,
  tokens LONGTEXT NULL,
  expires_at BIGINT NULL,
  active TINYINT(1) NOT NULL DEFAULT 1,
  cloud_ban_id VARCHAR(64) NULL,
  evidence LONGTEXT NULL,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL,
  revoked_at BIGINT NULL,
  revoked_by VARCHAR(120) NULL,
  revoke_reason TEXT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_mz_bans_public_id (public_id),
  KEY idx_mz_bans_active (active),
  KEY idx_mz_bans_expires_at (expires_at),
  KEY idx_mz_bans_cloud_ban_id (cloud_ban_id)
);

CREATE TABLE IF NOT EXISTS mz_ban_identifiers (
  id BIGINT NOT NULL AUTO_INCREMENT,
  ban_id VARCHAR(36) NOT NULL,
  identifier_type VARCHAR(32) NOT NULL,
  identifier_value VARCHAR(255) NOT NULL,
  active TINYINT(1) NOT NULL DEFAULT 1,
  created_at BIGINT NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_mz_ban_identifier (ban_id, identifier_type, identifier_value),
  KEY idx_mz_ban_identifier_lookup (identifier_type, identifier_value, active),
  KEY idx_mz_ban_identifier_ban (ban_id)
);

CREATE TABLE IF NOT EXISTS mz_ban_tokens (
  id BIGINT NOT NULL AUTO_INCREMENT,
  ban_id VARCHAR(36) NOT NULL,
  token_value VARCHAR(255) NOT NULL,
  active TINYINT(1) NOT NULL DEFAULT 1,
  created_at BIGINT NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_mz_ban_token (ban_id, token_value),
  KEY idx_mz_ban_token_lookup (token_value, active),
  KEY idx_mz_ban_token_ban (ban_id)
);

CREATE TABLE IF NOT EXISTS mz_ban_seen (
  id BIGINT NOT NULL AUTO_INCREMENT,
  player_name VARCHAR(120) NULL,
  primary_identifier VARCHAR(255) NULL,
  identifiers LONGTEXT NOT NULL,
  tokens LONGTEXT NULL,
  first_seen_at BIGINT NOT NULL,
  last_seen_at BIGINT NOT NULL,
  last_source INT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_mz_ban_seen_primary (primary_identifier),
  KEY idx_mz_ban_seen_primary (primary_identifier),
  KEY idx_mz_ban_seen_last_seen (last_seen_at)
);

CREATE TABLE IF NOT EXISTS mz_ban_audit (
  id BIGINT NOT NULL AUTO_INCREMENT,
  action VARCHAR(80) NOT NULL,
  actor_source INT NULL,
  actor_name VARCHAR(120) NULL,
  target_source INT NULL,
  target_name VARCHAR(120) NULL,
  ban_public_id VARCHAR(32) NULL,
  meta LONGTEXT NULL,
  created_at BIGINT NOT NULL,
  PRIMARY KEY (id),
  KEY idx_mz_ban_audit_action (action),
  KEY idx_mz_ban_audit_created (created_at),
  KEY idx_mz_ban_audit_public_id (ban_public_id)
);

CREATE TABLE IF NOT EXISTS mz_ban_flags (
  id BIGINT NOT NULL AUTO_INCREMENT,
  player_name VARCHAR(120) NULL,
  primary_identifier VARCHAR(255) NULL,
  reason VARCHAR(80) NOT NULL,
  points INT NOT NULL DEFAULT 0,
  score_after INT NOT NULL DEFAULT 0,
  evidence LONGTEXT NULL,
  created_by_resource VARCHAR(80) NULL,
  created_at BIGINT NOT NULL,
  PRIMARY KEY (id),
  KEY idx_mz_ban_flags_primary (primary_identifier),
  KEY idx_mz_ban_flags_reason (reason),
  KEY idx_mz_ban_flags_created (created_at),
  KEY idx_mz_ban_flags_score (score_after)
);
