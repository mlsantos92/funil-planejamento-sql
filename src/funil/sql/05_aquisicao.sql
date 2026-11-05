-- Camada de aquisição: de onde vêm os clientes e quanto custou trazê-los.
-- Liga-se ao funil pelas tabelas clientes (cliente_id) e clientes.origem.
--
--   canais 1──N campanhas 1──N investimento (gasto mensal)
--   campanhas 1──N leads 0..1──1 clientes
--   origem_canal: liga a origem do cliente (indicação, base...) ao canal que a gera

DROP VIEW IF EXISTS vw_leads;
DROP TABLE IF EXISTS leads;
DROP TABLE IF EXISTS investimento;
DROP TABLE IF EXISTS campanhas;
DROP TABLE IF EXISTS origem_canal;
DROP TABLE IF EXISTS canais;

CREATE TABLE canais (
    canal_id  INTEGER PRIMARY KEY,
    nome      TEXT NOT NULL UNIQUE,
    tipo      TEXT NOT NULL CHECK (tipo IN ('midia_paga', 'indicacao', 'base'))
);

CREATE TABLE origem_canal (
    origem    TEXT PRIMARY KEY CHECK (origem IN ('lead', 'base_ativa', 'base_inativa', 'indicacao')),
    tipo      TEXT NOT NULL      -- tipo de canal que gera essa origem
);

CREATE TABLE campanhas (
    campanha_id  INTEGER PRIMARY KEY,
    canal_id     INTEGER NOT NULL REFERENCES canais(canal_id),
    nome         TEXT NOT NULL
);

-- Gasto por campanha e mês (mídia, prêmios de indicação, horas de prospecção na base).
CREATE TABLE investimento (
    campanha_id  INTEGER NOT NULL REFERENCES campanhas(campanha_id),
    mes          TEXT NOT NULL,                  -- AAAA-MM
    valor        REAL NOT NULL CHECK (valor >= 0),
    PRIMARY KEY (campanha_id, mes)
);

-- Um lead de mídia paga. Se agendou reunião, vira cliente (cliente_id preenchido).
CREATE TABLE leads (
    lead_id      INTEGER PRIMARY KEY,
    campanha_id  INTEGER NOT NULL REFERENCES campanhas(campanha_id),
    criado_em    TEXT NOT NULL,
    cliente_id   INTEGER UNIQUE REFERENCES clientes(cliente_id)
);

CREATE INDEX ix_leads_campanha ON leads(campanha_id, criado_em);

-- Lead com o destino no funil: agendou? compareceu? fechou?
CREATE VIEW vw_leads AS
SELECT
    l.lead_id, l.criado_em, strftime('%Y-%m', l.criado_em) AS mes,
    c.campanha_id, c.nome AS campanha, k.nome AS canal,
    l.cliente_id,
    (l.cliente_id IS NOT NULL)                                    AS agendou,
    COALESCE(MAX(r.status = 'realizada'), 0)                      AS compareceu,
    COALESCE(MAX(r.status = 'prevista'), 0)                       AS reuniao_futura,
    COALESCE(MAX(ct.contrato_id IS NOT NULL), 0)                  AS fechou,
    MAX(ct.valor)                                                 AS valor_contrato
FROM leads l
JOIN campanhas c ON c.campanha_id = l.campanha_id
JOIN canais    k ON k.canal_id    = c.canal_id
LEFT JOIN reunioes  r  ON r.cliente_id = l.cliente_id
LEFT JOIN contratos ct ON ct.reuniao_id = r.reuniao_id
GROUP BY l.lead_id;
