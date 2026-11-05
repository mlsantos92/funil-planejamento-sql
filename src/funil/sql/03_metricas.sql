-- Métricas do funil. Cada consulta começa com "-- name: <nome>".
-- Convenção: conversão = contratos ÷ reuniões REALIZADAS (quem não apareceu
-- não teve chance de fechar); no-show = não ocorreu ÷ (realizadas + não ocorreu).

-- name: funil_mensal
-- Visão mês a mês: agenda, comparecimento, conversão e receita.
WITH p AS (SELECT valor AS repasse FROM premissas WHERE chave = 'repasse_setor')
SELECT
    mes,
    COUNT(*)                                                       AS agendadas,
    SUM(realizada)                                                 AS realizadas,
    SUM(nao_ocorreu)                                               AS nao_ocorreram,
    SUM(status = 'prevista')                                       AS ainda_previstas,
    ROUND(100.0 * SUM(nao_ocorreu) / NULLIF(SUM(realizada) + SUM(nao_ocorreu), 0), 1) AS no_show_pct,
    SUM(fechou)                                                    AS contratos,
    ROUND(100.0 * SUM(fechou) / NULLIF(SUM(realizada), 0), 1)      AS conversao_pct,
    ROUND(SUM(COALESCE(valor, 0)), 0)                              AS faturamento,
    ROUND(SUM(COALESCE(valor, 0)) * (SELECT repasse FROM p), 0)    AS receita_setor
FROM vw_reunioes
GROUP BY mes
ORDER BY mes;

-- name: conversao_por_origem
-- De onde vêm os melhores clientes? Inclui ticket médio e tempo até fechar.
SELECT
    origem,
    SUM(realizada)                                                 AS realizadas,
    SUM(fechou)                                                    AS contratos,
    ROUND(100.0 * SUM(fechou) / NULLIF(SUM(realizada), 0), 1)      AS conversao_pct,
    ROUND(AVG(valor), 0)                                           AS ticket_medio,
    ROUND(AVG(dias_ate_fechar), 1)                                 AS dias_medios_ate_fechar
FROM vw_reunioes
WHERE status <> 'prevista'
GROUP BY origem
ORDER BY conversao_pct DESC;

-- name: ranking_assessores
-- Ranking com funções de janela; participação de cada um no faturamento total.
WITH base AS (
    SELECT assessor, equipe,
           SUM(realizada)                                          AS realizadas,
           SUM(fechou)                                             AS contratos,
           ROUND(100.0 * SUM(fechou) / NULLIF(SUM(realizada), 0), 1) AS conversao_pct,
           SUM(COALESCE(valor, 0))                                 AS faturamento
    FROM vw_reunioes
    GROUP BY assessor, equipe
)
SELECT
    RANK() OVER (ORDER BY faturamento DESC)                        AS posicao,
    assessor, equipe, realizadas, contratos, conversao_pct,
    ROUND(faturamento, 0)                                          AS faturamento,
    ROUND(100.0 * faturamento / SUM(faturamento) OVER (), 1)       AS participacao_pct,
    ROUND(100.0 * SUM(faturamento) OVER (ORDER BY faturamento DESC
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
          / SUM(faturamento) OVER (), 1)                           AS participacao_acumulada_pct
FROM base
ORDER BY posicao;

-- name: conversao_por_equipe_e_origem
-- Tabela cruzada (pivot) feita com agregação condicional.
SELECT
    equipe,
    ROUND(100.0 * SUM(fechou * (origem = 'lead'))         / NULLIF(SUM(realizada * (origem = 'lead')), 0), 1)         AS lead,
    ROUND(100.0 * SUM(fechou * (origem = 'base_ativa'))   / NULLIF(SUM(realizada * (origem = 'base_ativa')), 0), 1)   AS base_ativa,
    ROUND(100.0 * SUM(fechou * (origem = 'base_inativa')) / NULLIF(SUM(realizada * (origem = 'base_inativa')), 0), 1) AS base_inativa,
    ROUND(100.0 * SUM(fechou * (origem = 'indicacao'))    / NULLIF(SUM(realizada * (origem = 'indicacao')), 0), 1)    AS indicacao
FROM vw_reunioes
GROUP BY equipe
ORDER BY equipe;

-- name: tendencia_conversao
-- Conversão do mês e média móvel de 3 meses (suaviza o ruído de amostras pequenas).
WITH m AS (
    SELECT mes, SUM(realizada) AS realizadas, SUM(fechou) AS contratos
    FROM vw_reunioes WHERE status <> 'prevista'
    GROUP BY mes
)
SELECT
    mes, realizadas, contratos,
    ROUND(100.0 * contratos / NULLIF(realizadas, 0), 1)            AS conversao_pct,
    ROUND(100.0 * SUM(contratos) OVER w / NULLIF(SUM(realizadas) OVER w, 0), 1) AS media_movel_3m_pct
FROM m
WINDOW w AS (ORDER BY mes ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
ORDER BY mes;

-- name: em_negociacao
-- Pipeline aberto: quem está em negociação e há quantos dias (data de referência na premissa).
SELECT
    reuniao_id, assessor, origem, agendada_para,
    CAST(julianday(date((SELECT valor FROM premissas WHERE chave = 'data_referencia_juliana')))
         - julianday(agendada_para) AS INTEGER)                    AS dias_em_aberto
FROM vw_reunioes
WHERE resultado = 'em_negociacao'
ORDER BY dias_em_aberto DESC;

-- name: cenarios_proximos_meses
-- Projeção para as reuniões ainda previstas: comparecimento histórico ×
-- conversão de cada cenário × ticket. Pessimista/normal/otimista vêm de premissas.
WITH hist AS (
    SELECT 1.0 * SUM(realizada) / NULLIF(SUM(realizada) + SUM(nao_ocorreu), 0) AS comparecimento,
           AVG(valor) AS ticket
    FROM vw_reunioes WHERE status <> 'prevista'
),
prev AS (
    SELECT mes, COUNT(*) AS previstas FROM vw_reunioes WHERE status = 'prevista' GROUP BY mes
),
cen AS (
    SELECT 'pessimista' AS cenario, valor AS conv FROM premissas WHERE chave = 'conv_pessimista'
    UNION ALL SELECT 'normal',     valor FROM premissas WHERE chave = 'conv_normal'
    UNION ALL SELECT 'otimista',   valor FROM premissas WHERE chave = 'conv_otimista'
)
SELECT
    prev.mes, cen.cenario, prev.previstas,
    ROUND(prev.previstas * hist.comparecimento, 1)                          AS realizadas_esperadas,
    ROUND(prev.previstas * hist.comparecimento * cen.conv, 1)               AS contratos_esperados,
    ROUND(prev.previstas * hist.comparecimento * cen.conv * hist.ticket, 0) AS faturamento_esperado,
    ROUND(prev.previstas * hist.comparecimento * cen.conv * hist.ticket
          * (SELECT valor FROM premissas WHERE chave = 'repasse_setor'), 0) AS receita_setor_esperada
FROM prev CROSS JOIN cen CROSS JOIN hist
ORDER BY prev.mes, CASE cen.cenario WHEN 'pessimista' THEN 1 WHEN 'normal' THEN 2 ELSE 3 END;

-- name: coorte_clientes
-- Coorte por mês de cadastro: % de clientes que viraram contrato em até 30, 60 e 90 dias.
-- Cliente sem contrato conta como 0 (não some da média). Uma janela que ainda
-- não terminou para a coorte inteira fica em branco, para não subestimar coortes recentes.
WITH ref AS (SELECT date(valor) AS hoje FROM premissas WHERE chave = 'data_referencia_juliana'),
primeira AS (
    SELECT c.cliente_id, strftime('%Y-%m', c.criado_em) AS coorte, c.criado_em,
           MIN(k.fechado_em) AS primeiro_contrato
    FROM clientes c
    LEFT JOIN reunioes r ON r.cliente_id = c.cliente_id
    LEFT JOIN contratos k ON k.reuniao_id = r.reuniao_id
    GROUP BY c.cliente_id
),
marcado AS (
    SELECT coorte, criado_em,
           julianday(primeiro_contrato) - julianday(criado_em) AS dias
    FROM primeira
)
SELECT
    coorte,
    COUNT(*) AS clientes,
    CASE WHEN julianday((SELECT hoje FROM ref)) - julianday(MAX(criado_em)) >= 30
         THEN ROUND(100.0 * AVG(COALESCE(dias <= 30, 0)), 1) END AS ate_30d_pct,
    CASE WHEN julianday((SELECT hoje FROM ref)) - julianday(MAX(criado_em)) >= 60
         THEN ROUND(100.0 * AVG(COALESCE(dias <= 60, 0)), 1) END AS ate_60d_pct,
    CASE WHEN julianday((SELECT hoje FROM ref)) - julianday(MAX(criado_em)) >= 90
         THEN ROUND(100.0 * AVG(COALESCE(dias <= 90, 0)), 1) END AS ate_90d_pct
FROM marcado
GROUP BY coorte
HAVING COUNT(*) >= 10
ORDER BY coorte;

-- name: funil_midia_paga
-- Cada campanha paga, do lead ao contrato: CPL, taxas de cada etapa e CAC.
WITH gasto AS (SELECT campanha_id, SUM(valor) AS investimento FROM investimento GROUP BY campanha_id)
SELECT
    v.canal, v.campanha,
    COUNT(*)                                                       AS leads,
    ROUND(g.investimento / COUNT(*), 2)                            AS cpl,
    ROUND(100.0 * AVG(v.agendou), 1)                               AS agendamento_pct,
    ROUND(100.0 * SUM(v.compareceu) / NULLIF(SUM(v.agendou) - SUM(v.reuniao_futura), 0), 1) AS comparecimento_pct,
    ROUND(100.0 * SUM(v.fechou) / NULLIF(SUM(v.compareceu), 0), 1) AS conversao_reuniao_pct,
    SUM(v.fechou)                                                  AS contratos,
    ROUND(g.investimento, 0)                                       AS investimento,
    ROUND(g.investimento / NULLIF(SUM(v.fechou), 0), 0)            AS cac
FROM vw_leads v JOIN gasto g ON g.campanha_id = v.campanha_id
GROUP BY v.canal, v.campanha
ORDER BY cac;

-- name: cac_por_canal
-- Custo de aquisição por tipo de canal: investimento total ÷ contratos daquela origem.
WITH gasto AS (
    SELECT k.tipo, SUM(i.valor) AS investimento
    FROM investimento i JOIN campanhas c ON c.campanha_id = i.campanha_id
    JOIN canais k ON k.canal_id = c.canal_id GROUP BY k.tipo
),
contratos_tipo AS (
    SELECT oc.tipo, COUNT(*) AS contratos, SUM(v.valor) AS faturamento
    FROM vw_reunioes v JOIN origem_canal oc ON oc.origem = v.origem
    WHERE v.fechou = 1 GROUP BY oc.tipo
)
SELECT g.tipo AS canal, ROUND(g.investimento, 0) AS investimento, ct.contratos,
       ROUND(g.investimento / NULLIF(ct.contratos, 0), 0)            AS cac,
       ROUND(ct.faturamento / NULLIF(ct.contratos, 0), 0)            AS ticket_medio,
       ROUND(ct.faturamento / NULLIF(g.investimento, 0), 2)          AS faturamento_por_real_investido
FROM gasto g LEFT JOIN contratos_tipo ct ON ct.tipo = g.tipo
ORDER BY cac;
