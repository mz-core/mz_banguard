-- MZ BanGuard 1.6 / Incident V3: sinais brutos sanitizados por sessao.
-- Idempotente: pode ser executado novamente sem destruir dados.

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
