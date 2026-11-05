-- Testes de qualidade de dados: cada consulta deve devolver ZERO linhas.
-- (mesma ideia dos "tests" do dbt). O pytest roda todas.

-- name: contrato_sem_reuniao_realizada
SELECT k.contrato_id
FROM contratos k JOIN reunioes r ON r.reuniao_id = k.reuniao_id
WHERE r.status <> 'realizada' OR r.resultado <> 'fechado';

-- name: fechado_sem_contrato
SELECT r.reuniao_id
FROM reunioes r LEFT JOIN contratos k ON k.reuniao_id = r.reuniao_id
WHERE r.resultado = 'fechado' AND k.contrato_id IS NULL;

-- name: contrato_antes_da_reuniao
SELECT k.contrato_id
FROM contratos k JOIN reunioes r ON r.reuniao_id = k.reuniao_id
WHERE k.fechado_em < r.agendada_para;

-- name: reuniao_antes_do_cadastro
SELECT r.reuniao_id
FROM reunioes r JOIN clientes c ON c.cliente_id = r.cliente_id
WHERE r.agendada_para < c.criado_em;

-- name: assessor_divergente
-- A reunião deve ser do mesmo assessor responsável pelo cliente.
SELECT r.reuniao_id
FROM reunioes r JOIN clientes c ON c.cliente_id = r.cliente_id
WHERE r.assessor_id <> c.assessor_id;

-- name: prevista_no_passado
-- Reunião ainda "prevista" com data anterior à data de referência = status desatualizado.
SELECT reuniao_id
FROM reunioes
WHERE status = 'prevista'
  AND agendada_para < date((SELECT valor FROM premissas WHERE chave = 'data_referencia_juliana'));

-- name: cliente_criado_no_futuro
SELECT cliente_id
FROM clientes
WHERE criado_em > date((SELECT valor FROM premissas WHERE chave = 'data_referencia_juliana'));

-- name: lead_ligado_a_cliente_de_outra_origem
SELECT l.lead_id
FROM leads l JOIN clientes c ON c.cliente_id = l.cliente_id
WHERE c.origem <> 'lead';

-- name: cliente_de_lead_sem_lead
SELECT c.cliente_id
FROM clientes c LEFT JOIN leads l ON l.cliente_id = c.cliente_id
WHERE c.origem = 'lead' AND l.lead_id IS NULL;

-- name: lead_depois_do_cadastro_do_cliente
SELECT l.lead_id
FROM leads l JOIN clientes c ON c.cliente_id = l.cliente_id
WHERE l.criado_em > c.criado_em;

-- name: lead_no_futuro
SELECT lead_id FROM leads
WHERE criado_em > date((SELECT valor FROM premissas WHERE chave = 'data_referencia_juliana'));

-- name: midia_sem_investimento
-- Todo mês com leads de uma campanha precisa ter gasto registrado.
SELECT DISTINCT l.campanha_id, strftime('%Y-%m', l.criado_em) AS mes
FROM leads l
LEFT JOIN investimento i ON i.campanha_id = l.campanha_id AND i.mes = strftime('%Y-%m', l.criado_em)
WHERE i.valor IS NULL;
