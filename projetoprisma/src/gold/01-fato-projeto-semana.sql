-- Uma linha por projeto e semana (sexta), da semana do início até hoje (2026-10-16).
-- O avanço de cada semana vem do status semanal (as ferramentas só guardam o % de hoje).
-- As janelas ficam em CTEs separados das agregações (o pipeline não aceita janela dentro de agregação).
CREATE OR REFRESH MATERIALIZED VIEW projetoprisma.gold.fato_projeto_semana (
  CONSTRAINT pv_nao_negativo EXPECT (pv >= 0) ON VIOLATION FAIL UPDATE,
  CONSTRAINT ev_ate_orcamento EXPECT (ev <= orcamento) ON VIOLATION FAIL UPDATE
)
COMMENT 'Projeto × semana (sexta) desde o início até 2026-10-16: PV, EV (pelo % do status semanal), AC acumulado, SPI, CPI, EAC, farol do gerente e horas do timesheet.'
AS
WITH semanas AS (
  SELECT
    projeto_id,
    orcamento_custo AS orcamento,
    explode(sequence(date_add(date_trunc('WEEK', data_inicio), 4), DATE'2026-10-16', INTERVAL 1 WEEK)) AS semana
  FROM projetos
),
planejado AS (
  -- fração do baseline de cada tarefa decorrida até a semana, ponderada pelas horas
  SELECT
    s.projeto_id,
    s.semana,
    sum(t.horas * greatest(0, least(1, coalesce(
          try_divide(datediff(s.semana, t.inicio_baseline), datediff(t.fim_baseline, t.inicio_baseline)),
          IF(s.semana >= t.fim_baseline, 1, 0))))) AS horas_planejadas,
    sum(t.horas) AS horas_totais
  FROM semanas s
  JOIN tarefas t ON t.projeto_id = s.projeto_id
  GROUP BY s.projeto_id, s.semana
),
status AS (
  -- projeto concluído não publica mais: vale o último % e o último farol
  SELECT
    s.projeto_id,
    s.semana,
    last_value(st.pct_concluido, true) OVER w AS pct_status,
    last_value(st.farol, true) OVER w AS farol_do_gerente
  FROM semanas s
  LEFT JOIN status_semanal st ON st.projeto_id = s.projeto_id AND st.data_status = s.semana
  WINDOW w AS (PARTITION BY s.projeto_id ORDER BY s.semana)
),
custo_semana AS (
  SELECT projeto_id, semana, sum(valor) AS valor
  FROM custos
  GROUP BY projeto_id, semana
),
custo_acumulado AS (
  SELECT s.projeto_id, s.semana, coalesce(sum(c.valor), 0) AS ac
  FROM semanas s
  LEFT JOIN custo_semana c ON c.projeto_id = s.projeto_id AND c.semana <= s.semana
  GROUP BY s.projeto_id, s.semana
),
horas AS (
  SELECT projeto_id, semana,
         sum(horas_disponiveis) AS horas_disponiveis,
         sum(horas_apontadas) AS horas_apontadas
  FROM apontamentos
  GROUP BY projeto_id, semana
),
base AS (
  SELECT
    s.projeto_id,
    s.semana,
    s.orcamento,
    round(s.orcamento * try_divide(p.horas_planejadas, p.horas_totais), 2) AS pv,
    round(s.orcamento * coalesce(st.pct_status, 0) / 100, 2) AS ev,
    a.ac,
    st.farol_do_gerente,
    coalesce(h.horas_disponiveis, 0) AS horas_disponiveis,
    coalesce(h.horas_apontadas, 0) AS horas_apontadas
  FROM semanas s
  JOIN planejado p USING (projeto_id, semana)
  JOIN status st USING (projeto_id, semana)
  JOIN custo_acumulado a USING (projeto_id, semana)
  LEFT JOIN horas h USING (projeto_id, semana)
)
SELECT
  projeto_id,
  semana,
  orcamento,
  pv,
  ev,
  ac,
  round(try_divide(ev, pv), 4) AS spi,
  round(try_divide(ev, ac), 4) AS cpi,
  round(try_divide(orcamento * ac, ev), 2) AS eac,   -- orçamento ÷ CPI
  farol_do_gerente,
  horas_disponiveis,
  horas_apontadas,
  greatest(horas_disponiveis - horas_apontadas, 0) AS horas_ociosas
FROM base;
