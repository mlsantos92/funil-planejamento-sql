-- Camada intermediária: uma linha por reunião, já com tudo que as métricas usam.
-- Separar "fatos limpos" das "métricas" é o mesmo princípio de ferramentas
-- como o dbt: cada métrica fica simples e não repete JOINs.

DROP VIEW IF EXISTS vw_reunioes;
CREATE VIEW vw_reunioes AS
SELECT
    r.reuniao_id,
    r.agendada_para,
    strftime('%Y-%m', r.agendada_para)              AS mes,
    r.status,
    r.resultado,
    r.assessor_id,
    a.nome                                          AS assessor,
    a.equipe,
    c.cliente_id,
    c.origem,
    c.criado_em                                     AS cliente_criado_em,
    k.contrato_id,
    k.fechado_em,
    k.valor,
    CAST(julianday(k.fechado_em) - julianday(r.agendada_para) AS INTEGER) AS dias_ate_fechar,
    (r.status = 'realizada')                        AS realizada,
    (r.status = 'nao_ocorreu')                      AS nao_ocorreu,
    (k.contrato_id IS NOT NULL)                     AS fechou
FROM reunioes r
JOIN clientes   c ON c.cliente_id  = r.cliente_id
JOIN assessores a ON a.assessor_id = r.assessor_id
LEFT JOIN contratos k ON k.reuniao_id = r.reuniao_id;
