-- Testes de qualidade da silver e da gold. Uma linha por teste; o primeiro que falhar
-- para a tarefa com raise_error dizendo qual foi.
WITH testes (n, teste, ok) AS (
  SELECT 1, 'os 60 projetos têm cronograma na silver.tarefas',
         (SELECT count(DISTINCT projeto_id) FROM projetoprisma.silver.tarefas) = 60
  UNION ALL
  SELECT 2, 'cada projeto veio de UMA ferramenta, a do cadastro do PMO',
         (SELECT count(*) FROM (
            SELECT t.projeto_id
            FROM projetoprisma.silver.tarefas t
            JOIN projetoprisma.silver.projetos p USING (projeto_id)
            GROUP BY t.projeto_id
            HAVING count(DISTINCT t.ferramenta) <> 1 OR max(t.ferramenta) <> max(p.ferramenta))) = 0
  UNION ALL
  SELECT 3, 'as horas do Excel na silver = a soma das linhas de TOTAL das planilhas',
         abs((SELECT sum(horas) FROM projetoprisma.silver.tarefas WHERE ferramenta = 'excel')
           - (SELECT sum(CAST(replace(horas_previstas, 'h', '') AS DOUBLE))
              FROM projetoprisma.bronze.excel_tarefas WHERE tarefa = 'TOTAL')) < 0.01
  UNION ALL
  SELECT 4, 'uma linha por pessoa na silver',
         (SELECT count(*) = count(DISTINCT colaborador_id) FROM projetoprisma.silver.colaboradores)
  UNION ALL
  SELECT 5, 'a CodeForge virou um fornecedor só',
         (SELECT count(DISTINCT fornecedor) FROM projetoprisma.silver.entregas_fornecedor
          WHERE replace(lower(fornecedor), ' ', '') LIKE '%codeforge%') = 1
  UNION ALL
  SELECT 6, 'a limpeza não mudou o custo total (bronze com replace = silver)',
         (SELECT sum(CAST(replace(valor, ',', '.') AS DECIMAL(18, 2))) FROM projetoprisma.bronze.custos)
       = (SELECT sum(valor) FROM projetoprisma.silver.custos)
  UNION ALL
  SELECT 7, 'os 60 projetos têm fotografia de hoje',
         (SELECT count(DISTINCT projeto_id) FROM projetoprisma.gold.projeto_situacao_atual) = 60
  UNION ALL
  SELECT 8, 'todo projeto em andamento tem SPI e CPI',
         (SELECT count(*) FROM projetoprisma.gold.projeto_situacao_atual
          WHERE status = 'em_andamento' AND (spi IS NULL OR cpi IS NULL)) = 0
  UNION ALL
  SELECT 9, 'o EV de hoje do status semanal bate com o das ferramentas (diferença < 1%)',
         abs((SELECT sum(ev) FROM projetoprisma.gold.fato_projeto_semana WHERE semana = DATE'2026-10-16')
           / (SELECT sum(ev) FROM projetoprisma.gold.projeto_situacao_atual) - 1) < 0.01
  UNION ALL
  SELECT 10, 'AC de hoje no fato = soma dos lançamentos até hoje',
         (SELECT sum(ac) FROM projetoprisma.gold.fato_projeto_semana WHERE semana = DATE'2026-10-16')
       = (SELECT sum(valor) FROM projetoprisma.silver.custos WHERE data <= DATE'2026-10-16')
)
SELECT n, teste,
       CASE WHEN ok THEN 'ok' ELSE raise_error(concat('teste ', n, ' falhou: ', teste)) END AS resultado
FROM testes
ORDER BY n;
