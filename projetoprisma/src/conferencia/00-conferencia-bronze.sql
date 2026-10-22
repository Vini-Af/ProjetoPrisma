-- Conferência da bronze: as 9 tabelas contra a contagem esperada (seed 42).
-- bronze.feriados fica de fora: cresce a cada execução.
WITH esperado (tabela, esperado) AS (
  VALUES ('projetos', 60), ('status_semanal', 3911), ('excel_tarefas', 1663),
         ('clickup_tarefas', 2119), ('msproject_tarefas', 1260), ('colaboradores', 523),
         ('apontamentos', 30883), ('custos', 23640), ('entregas_fornecedor', 640)
),
obtido AS (
            SELECT 'projetos' AS tabela, COUNT(*) AS obtido FROM projetoprisma.bronze.projetos
  UNION ALL SELECT 'status_semanal', COUNT(*) FROM projetoprisma.bronze.status_semanal
  UNION ALL SELECT 'excel_tarefas', COUNT(*) FROM projetoprisma.bronze.excel_tarefas
  UNION ALL SELECT 'clickup_tarefas', COUNT(*) FROM projetoprisma.bronze.clickup_tarefas
  UNION ALL SELECT 'msproject_tarefas', COUNT(*) FROM projetoprisma.bronze.msproject_tarefas
  UNION ALL SELECT 'colaboradores', COUNT(*) FROM projetoprisma.bronze.colaboradores
  UNION ALL SELECT 'apontamentos', COUNT(*) FROM projetoprisma.bronze.apontamentos
  UNION ALL SELECT 'custos', COUNT(*) FROM projetoprisma.bronze.custos
  UNION ALL SELECT 'entregas_fornecedor', COUNT(*) FROM projetoprisma.bronze.entregas_fornecedor
)
SELECT e.tabela, e.esperado, o.obtido,
       CASE WHEN o.obtido = e.esperado THEN 'ok'
            ELSE raise_error(concat('bronze.', e.tabela, ': esperado ', e.esperado, ', obtido ', o.obtido,
                                    '. Veja a saída da tarefa ingestao_data_lake.'))
       END AS resultado
FROM esperado e JOIN obtido o USING (tabela)
ORDER BY e.tabela;
