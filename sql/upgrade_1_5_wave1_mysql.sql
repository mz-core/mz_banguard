-- MZ BanGuard 1.5 / Wave 1: incidentes persistentes, acoes e LAB.
-- Idempotente: pode ser executado novamente sem destruir dados.

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
