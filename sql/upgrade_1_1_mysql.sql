-- Upgrade MZ BanGuard Resource 1.0 -> 1.1
-- Rode apenas se você já tinha a versão antiga instalada.

ALTER TABLE mz_bans ADD COLUMN evidence LONGTEXT NULL;
ALTER TABLE mz_bans ADD KEY idx_mz_bans_cloud_ban_id (cloud_ban_id);

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

-- Opcional. Pode falhar se já existirem duplicados antigos.
ALTER TABLE mz_ban_seen ADD UNIQUE KEY uniq_mz_ban_seen_primary (primary_identifier);
