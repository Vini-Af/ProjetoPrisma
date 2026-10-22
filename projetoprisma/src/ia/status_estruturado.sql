-- O texto livre do status semanal vira coluna.
-- ATENÇÃO: a sql_task corta o arquivo em todo ponto e vírgula, então nenhum aparece
-- dentro de texto ou comentário, só no fim de cada comando.

-- a. A tabela acumula: a IA de um status já classificado nunca é refeita.
CREATE TABLE IF NOT EXISTS projetoprisma.gold.status_estruturado (
  projeto_id       STRING    COMMENT 'Projeto do status (PRJ-xxx)',
  data_status      DATE      COMMENT 'Sexta-feira do status semanal',
  farol            STRING    COMMENT 'Farol publicado pelo gerente (verde, amarelo, vermelho)',
  causa_bloqueio   STRING    COMMENT 'change_freeze, falta_sre, dependencia_fornecedor, rotatividade, mudanca_escopo, bug_retrabalho, aprovacao_cliente, sem_bloqueio ou nao_reportado',
  bloqueio         STRING    COMMENT 'O bloqueio em poucas palavras (só quando metodo = ia)',
  quem_destrava    STRING    COMMENT 'Quem precisa agir para destravar (só quando metodo = ia)',
  dias_impacto     DOUBLE    COMMENT 'Impacto declarado no cronograma, em dias (1 semana = 7)',
  metodo           STRING    COMMENT 'Como foi classificado: regra (vazio ou sem bloqueio), ia (últimos 90 dias) ou palavra_chave (histórico)',
  texto_status     STRING    COMMENT 'Texto original do status',
  _classificado_em TIMESTAMP COMMENT 'Quando a linha foi classificada'
)
COMMENT 'Status semanal estruturado: causa do bloqueio, quem destrava e dias de impacto. IA (ai_classify + ai_extract) só nos status com bloqueio dos últimos 90 dias, regra e palavra-chave no resto. Incremental por MERGE.';

-- b. Só os status que ainda não estão na tabela.
MERGE INTO projetoprisma.gold.status_estruturado AS alvo
USING (
  WITH novos AS (
    SELECT s.*,
           lower(coalesce(s.texto_status, '')) AS t,
           CASE
             WHEN s.status_vazio
               OR lower(s.texto_status) RLIKE 'bloqueios: nenhum|sem bloqueios|nada relevante' THEN 'regra'
             WHEN s.data_status >= DATE'2026-07-18' THEN 'ia'
             ELSE 'palavra_chave'
           END AS metodo
    FROM projetoprisma.silver.status_semanal s
    LEFT ANTI JOIN projetoprisma.gold.status_estruturado e
      ON e.projeto_id = s.projeto_id AND e.data_status = s.data_status
  ),
  com_ia AS (
    -- a IA roda só aqui (cerca de 160 textos)
    SELECT *,
           ai_classify(texto_status,
             '["change_freeze","falta_sre","dependencia_fornecedor","rotatividade","mudanca_escopo","bug_retrabalho","aprovacao_cliente","sem_bloqueio"]',
             map('version', '2.0')):response[0]::STRING AS causa_ia,
           ai_extract(texto_status,
             '{"bloqueio":{"type":"string","description":"o bloqueio em poucas palavras"},"quem_destrava":{"type":"string","description":"quem precisa agir para destravar"},"dias_impacto":{"type":"number","description":"impacto no cronograma em dias, 1 semana = 7"}}',
             map('version', '2.0')) AS extraido
    FROM novos
    WHERE metodo = 'ia'
  )
  SELECT projeto_id, data_status, farol,
         causa_ia AS causa_bloqueio,
         extraido:response:bloqueio::STRING AS bloqueio,
         extraido:response:quem_destrava::STRING AS quem_destrava,
         extraido:response:dias_impacto::DOUBLE AS dias_impacto,
         metodo, texto_status, current_timestamp() AS _classificado_em
  FROM com_ia
  UNION ALL
  SELECT projeto_id, data_status, farol,
         CASE
           WHEN status_vazio THEN 'nao_reportado'
           WHEN metodo = 'regra' THEN 'sem_bloqueio'
           WHEN t RLIKE 'freeze|congelamento|janela de deploy' THEN 'change_freeze'
           WHEN t RLIKE 'sre|infraestrutura|ambiente de homologação' THEN 'falta_sre'
           WHEN t RLIKE 'forge|consultoria|fornecedor' THEN 'dependencia_fornecedor'
           WHEN t RLIKE 'saída de|rotatividade|onboarding' THEN 'rotatividade'
           WHEN t RLIKE 'escopo|change request|regra de negócio' THEN 'mudanca_escopo'
           WHEN t RLIKE 'bugs|regressão|refazendo' THEN 'bug_retrabalho'
           WHEN t RLIKE 'aprovação do cliente|homologação do cliente' THEN 'aprovacao_cliente'
         END AS causa_bloqueio,
         CAST(NULL AS STRING) AS bloqueio,
         CAST(NULL AS STRING) AS quem_destrava,
         CASE
           WHEN t RLIKE 'impacto estimado: 1 semana' THEN 7
           ELSE CAST(nullif(regexp_extract(t, 'impacto estimado de ([0-9]+) dias', 1), '') AS DOUBLE)
         END AS dias_impacto,
         metodo, texto_status, current_timestamp() AS _classificado_em
  FROM novos
  WHERE metodo <> 'ia'
) AS novo
ON alvo.projeto_id = novo.projeto_id AND alvo.data_status = novo.data_status
WHEN NOT MATCHED THEN INSERT *;

-- c. Leitura: quantos status por método e causa.
SELECT metodo, causa_bloqueio, count(*) AS status
FROM projetoprisma.gold.status_estruturado
GROUP BY metodo, causa_bloqueio
ORDER BY metodo, status DESC;
