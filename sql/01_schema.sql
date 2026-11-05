-- Modelo de dados do funil comercial de uma consultoria de planejamento
-- financeiro FICTÍCIA. Todos os nomes e valores são inventados.
--
--   assessores 1──N clientes 1──N reunioes 1──0..1 contratos
--   premissas: parâmetros de negócio (ticket, repasse, metas de cenário)

PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS contratos;
DROP TABLE IF EXISTS reunioes;
DROP TABLE IF EXISTS clientes;
DROP TABLE IF EXISTS assessores;
DROP TABLE IF EXISTS premissas;

CREATE TABLE assessores (
    assessor_id  INTEGER PRIMARY KEY,
    nome         TEXT NOT NULL,
    equipe       TEXT NOT NULL,
    entrada_em   TEXT NOT NULL                    -- AAAA-MM-DD
);

CREATE TABLE clientes (
    cliente_id   INTEGER PRIMARY KEY,
    assessor_id  INTEGER NOT NULL REFERENCES assessores(assessor_id),
    origem       TEXT NOT NULL CHECK (origem IN ('lead', 'base_ativa', 'base_inativa', 'indicacao')),
    criado_em    TEXT NOT NULL
);

CREATE TABLE reunioes (
    reuniao_id     INTEGER PRIMARY KEY,
    cliente_id     INTEGER NOT NULL REFERENCES clientes(cliente_id),
    assessor_id    INTEGER NOT NULL REFERENCES assessores(assessor_id),
    agendada_para  TEXT NOT NULL,
    status         TEXT NOT NULL CHECK (status IN ('prevista', 'realizada', 'nao_ocorreu')),
    resultado      TEXT CHECK (resultado IN ('fechado', 'em_negociacao', 'nao_fechado')),
    -- resultado só existe para reunião realizada
    CHECK ((status = 'realizada') = (resultado IS NOT NULL))
);

CREATE TABLE contratos (
    contrato_id      INTEGER PRIMARY KEY,
    reuniao_id       INTEGER NOT NULL UNIQUE REFERENCES reunioes(reuniao_id),
    fechado_em       TEXT NOT NULL,
    valor            REAL NOT NULL CHECK (valor > 0)
);

CREATE TABLE premissas (
    chave  TEXT PRIMARY KEY,
    valor  REAL NOT NULL,
    descricao TEXT
);

CREATE INDEX ix_reunioes_data ON reunioes(agendada_para);
CREATE INDEX ix_clientes_assessor ON clientes(assessor_id);
