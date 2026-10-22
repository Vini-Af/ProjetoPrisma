-- A fotografia de hoje (2026-10-16): cadastro + KPIs pelo % das ferramentas (silver.tarefas).
CREATE OR REFRESH MATERIALIZED VIEW projetoprisma.gold.projeto_situacao_atual
COMMENT 'Uma linha por projeto (60) com o cadastro e os KPIs de 2026-10-16 calculados sobre as tarefas das ferramentas: PV, EV, AC, SPI, CPI, EAC, estouro previsto, margem, atraso projetado, situação (ok/atenção/crítico/concluído), farol do gerente × farol calculado e melancia.'
AS
WITH hoje AS (
  SELECT
    projeto_id,
    sum(horas) AS horas_totais,
    sum(horas * greatest(0, least(1, coalesce(
          try_divide(datediff(DATE'2026-10-16', inicio_baseline), datediff(fim_baseline, inicio_baseline)),
          IF(DATE'2026-10-16' >= fim_baseline, 1, 0))))) AS horas_planejadas,
    sum(horas * pct_concluido / 100) AS horas_agregadas
  FROM tarefas
  GROUP BY projeto_id
),
custo AS (
  SELECT projeto_id, sum(valor) AS ac
  FROM custos
  WHERE data <= DATE'2026-10-16'
  GROUP BY projeto_id
),
farol AS (
  SELECT projeto_id, max_by(farol, data_status) AS farol_do_gerente
  FROM status_semanal
  WHERE data_status <= DATE'2026-10-16'
  GROUP BY projeto_id
),
kpi AS (
  SELECT
    p.projeto_id,
    p.nome_projeto,
    p.cliente,
    p.segmento,
    p.tipo_projeto,
    p.ferramenta,
    p.gerente_projeto,
    p.valor_contrato,
    p.orcamento_custo AS orcamento,
    p.data_inicio,
    p.data_fim_baseline,
    datediff(p.data_fim_baseline, p.data_inicio) AS duracao_baseline_dias,
    p.status,
    round(p.orcamento_custo * try_divide(h.horas_planejadas, h.horas_totais), 2) AS pv,
    round(p.orcamento_custo * try_divide(h.horas_agregadas, h.horas_totais), 2) AS ev,
    coalesce(c.ac, 0) AS ac,
    f.farol_do_gerente
  FROM projetos p
  LEFT JOIN hoje h USING (projeto_id)
  LEFT JOIN custo c USING (projeto_id)
  LEFT JOIN farol f USING (projeto_id)
),
indices AS (
  SELECT
    *,
    round(try_divide(ev, pv), 4) AS spi,
    round(try_divide(ev, ac), 4) AS cpi,
    round(try_divide(orcamento * ac, ev), 2) AS eac   -- orçamento ÷ CPI
  FROM kpi
)
SELECT
  projeto_id,
  concat(projeto_id, ' · ', nome_projeto) AS projeto,
  nome_projeto,
  cliente,
  segmento,
  tipo_projeto,
  ferramenta,
  gerente_projeto,
  valor_contrato,
  orcamento,
  data_inicio,
  data_fim_baseline,
  duracao_baseline_dias,
  status,
  pv,
  ev,
  ac,
  spi,
  cpi,
  eac,
  greatest(eac - orcamento, 0) AS estouro_previsto,
  round(try_divide(valor_contrato - eac, valor_contrato), 4) AS margem_projetada,
  round(try_divide(duracao_baseline_dias, spi) - duracao_baseline_dias) AS atraso_projetado_dias,
  date_add(data_inicio, CAST(round(try_divide(duracao_baseline_dias, spi)) AS INT)) AS termino_projetado,
  CASE
    WHEN status <> 'em_andamento' THEN 'concluído'
    WHEN spi < 0.8 OR cpi < 0.8 THEN 'crítico'
    WHEN spi < 0.9 OR cpi < 0.9 THEN 'atenção'
    ELSE 'ok'
  END AS situacao,
  farol_do_gerente,
  CASE WHEN spi >= 0.95 THEN 'verde' WHEN spi >= 0.90 THEN 'amarelo' ELSE 'vermelho' END AS farol_calculado,
  coalesce(status = 'em_andamento' AND farol_do_gerente = 'verde' AND spi < 0.9, false) AS melancia
FROM indices;

-- Pessoa × projeto × semana: quem está parado, quanto custa e como estava o projeto.
CREATE OR REFRESH MATERIALIZED VIEW projetoprisma.gold.utilizacao_pessoa_semana
COMMENT 'Timesheet por pessoa, projeto e semana (sexta) com nome, papel e senioridade: horas disponíveis, apontadas e ociosas, utilização (apontadas ÷ disponíveis), custo da hora parada (ociosas × custo_hora) e o SPI do projeto naquela semana.'
AS SELECT
  a.colaborador_id,
  c.nome,
  c.papel,
  c.senioridade,
  a.projeto_id,
  a.semana,
  a.horas_disponiveis,
  a.horas_apontadas,
  greatest(a.horas_disponiveis - a.horas_apontadas, 0) AS horas_ociosas,
  round(try_divide(a.horas_apontadas, a.horas_disponiveis), 4) AS utilizacao,
  round(greatest(a.horas_disponiveis - a.horas_apontadas, 0) * c.custo_hora, 2) AS custo_ocioso,
  f.spi AS spi_do_projeto
FROM apontamentos a
LEFT JOIN colaboradores c USING (colaborador_id)
LEFT JOIN projetoprisma.gold.fato_projeto_semana f ON f.projeto_id = a.projeto_id AND f.semana = a.semana;
