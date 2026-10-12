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

CREATE TABLE IF NOT EXISTS mz_security_incidents (
  incident_id VARCHAR(64) NOT NULL,
  code VARCHAR(64) NOT NULL,
  category VARCHAR(32) NOT NULL,
  status VARCHAR(32) NOT NULL,
  severity VARCHAR(16) NOT NULL,
  confidence VARCHAR(16) NOT NULL,
  risk_score INT NOT NULL DEFAULT 0,
  player_name VARCHAR(120) NULL,
  citizenid VARCHAR(64) NULL,
  account_id BIGINT NULL,
  session_id BIGINT NULL,
  first_seen_at BIGINT NOT NULL,
  last_seen_at BIGINT NOT NULL,
  count INT NOT NULL DEFAULT 1,
  suppressed_count INT NOT NULL DEFAULT 0,
  source_at_first_seen INT NULL,
  source_at_last_seen INT NULL,
  summary_json LONGTEXT NULL,
  evidence_json LONGTEXT NULL,
  timeline_snapshot_json LONGTEXT NULL,
  mitigation_json LONGTEXT NULL,
  lab TINYINT(1) NOT NULL DEFAULT 0,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL,
  resolved_at BIGINT NULL,
  resolved_by VARCHAR(128) NULL,
  false_positive_at BIGINT NULL,
  false_positive_by VARCHAR(128) NULL,
  PRIMARY KEY (incident_id),
  KEY idx_mz_security_incidents_status_updated (status, updated_at),
  KEY idx_mz_security_incidents_citizen (citizenid, last_seen_at),
  KEY idx_mz_security_incidents_account (account_id, last_seen_at),
  KEY idx_mz_security_incidents_code_last_seen (code, last_seen_at),
  KEY idx_mz_security_incidents_severity (severity, updated_at)
);

CREATE TABLE IF NOT EXISTS mz_security_signals (
  id BIGINT NOT NULL AUTO_INCREMENT,
  signal_id VARCHAR(64) NOT NULL,
  incident_id VARCHAR(64) NULL,
  code VARCHAR(80) NOT NULL,
  origin VARCHAR(32) NOT NULL,
  confidence VARCHAR(16) NOT NULL,
  culpability VARCHAR(16) NOT NULL,
  citizenid VARCHAR(64) NULL,
  account_id BIGINT NULL,
  session_id BIGINT NULL,
  source_id INT NULL,
  occurred_at BIGINT NOT NULL,
  evidence_json LONGTEXT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_mz_security_signal_id (signal_id),
  KEY idx_mz_security_signals_incident (incident_id, occurred_at),
  KEY idx_mz_security_signals_session (session_id, occurred_at),
  KEY idx_mz_security_signals_citizen (citizenid, occurred_at),
  KEY idx_mz_security_signals_account (account_id, occurred_at),
  KEY idx_mz_security_signals_code_time (code, occurred_at)
);

CREATE TABLE IF NOT EXISTS mz_security_incident_actions (
  id BIGINT NOT NULL AUTO_INCREMENT,
  incident_id VARCHAR(64) NOT NULL,
  action VARCHAR(80) NOT NULL,
  actor_citizenid VARCHAR(64) NULL,
  actor_name VARCHAR(120) NULL,
  note TEXT NULL,
  meta_json LONGTEXT NULL,
  created_at BIGINT NOT NULL,
  PRIMARY KEY (id),
  KEY idx_mz_security_actions_incident (incident_id, created_at),
  KEY idx_mz_security_actions_created (created_at)
);

CREATE TABLE IF NOT EXISTS mz_security_lab_subjects (
  id BIGINT NOT NULL AUTO_INCREMENT,
  citizenid VARCHAR(64) NULL,
  account_id BIGINT NULL,
  session_id BIGINT NULL,
  enabled TINYINT(1) NOT NULL DEFAULT 1,
  started_at BIGINT NOT NULL,
  expires_at BIGINT NULL,
  reason VARCHAR(256) NULL,
  authorized_by VARCHAR(128) NULL,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_mz_security_lab_session (session_id),
  KEY idx_mz_security_lab_citizen (citizenid, enabled),
  KEY idx_mz_security_lab_account (account_id, enabled),
  KEY idx_mz_security_lab_active_expiry (enabled, expires_at)
);
