"""Gera dados FICTÍCIOS e reproduzíveis para o funil.

Nenhum dado real é usado: nomes, empresa, valores e taxas são inventados.
As regras de geração imitam padrões comuns de um funil comercial de
serviços financeiros, para que as consultas tenham algo interessante a mostrar:

- indicações convertem mais que leads frios;
- leads faltam mais às reuniões (no-show);
- o volume cresce ao longo do ano (setor novo ganhando tração);
- cada assessor tem um "talento" de conversão próprio.
"""

from __future__ import annotations

import sqlite3
from datetime import date, timedelta
from pathlib import Path

import numpy as np

RAIZ = Path(__file__).resolve().parents[2]
PASTA_SQL = Path(__file__).resolve().parent / "sql"  # vai junto com o pacote
BANCO = RAIZ / "data" / "funil.db"
DATA_REFERENCIA = date(2026, 11, 5)  # "hoje" para o conjunto de dados

ASSESSORES = [  # nomes inventados
    ("Ana Ribeiro", "Equipe Norte"), ("Bruno Teixeira", "Equipe Norte"),
    ("Carla Mendes", "Equipe Norte"), ("Diego Farias", "Equipe Norte"),
    ("Elisa Prado", "Equipe Sul"), ("Fábio Nunes", "Equipe Sul"),
    ("Gabriela Lopes", "Equipe Sul"), ("Henrique Sales", "Equipe Sul"),
]

ORIGENS = ["lead", "base_ativa", "base_inativa", "indicacao"]
PESO_ORIGEM = [0.35, 0.30, 0.15, 0.20]
CONVERSAO = {"lead": 0.10, "base_ativa": 0.24, "base_inativa": 0.15, "indicacao": 0.38}
NO_SHOW = {"lead": 0.25, "base_ativa": 0.10, "base_inativa": 0.18, "indicacao": 0.08}

PREMISSAS = [
    ("ticket_padrao", 3500.0, "valor de tabela do contrato (fictício)"),
    ("repasse_setor", 0.70, "fatia do faturamento que fica com o setor (fictício)"),
    ("conv_pessimista", 0.15, "conversão do cenário pessimista"),
    ("conv_normal", 0.20, "conversão do cenário normal"),
    ("conv_otimista", 0.25, "conversão do cenário otimista"),
]


def gerar(semente: int = 2026) -> dict[str, list[tuple]]:
    rng = np.random.default_rng(semente)
    assessores = [(i + 1, n, e, "2025-12-01") for i, (n, e) in enumerate(ASSESSORES)]
    talento = rng.normal(1.0, 0.25, len(ASSESSORES)).clip(0.55, 1.5)

    clientes, reunioes, contratos = [], [], []
    cid = rid = kid = 0
    for mes in range(1, 13):
        n_mes = int(rng.poisson(18 + 4.5 * mes))  # volume crescendo no ano
        for _ in range(n_mes):
            a = int(rng.integers(len(ASSESSORES)))
            origem = str(rng.choice(ORIGENS, p=PESO_ORIGEM))
            dia = date(2026, mes, int(rng.integers(1, 29)))
            if dia.weekday() >= 5:  # sem reuniões no fim de semana
                dia += timedelta(days=7 - dia.weekday())
            criado = dia - timedelta(days=int(rng.integers(2, 45)))
            # ninguém é cadastrado no futuro: reunião marcada para dezembro
            # tem cliente cadastrado até a data de referência
            criado = min(criado, DATA_REFERENCIA - timedelta(days=1))
            cid += 1
            rid += 1
            clientes.append((cid, a + 1, origem, criado.isoformat()))

            if dia >= DATA_REFERENCIA:
                reunioes.append((rid, cid, a + 1, dia.isoformat(), "prevista", None))
                continue
            if rng.random() < NO_SHOW[origem]:
                reunioes.append((rid, cid, a + 1, dia.isoformat(), "nao_ocorreu", None))
                continue

            p_fecha = min(0.9, CONVERSAO[origem] * talento[a])
            dias_fechar = int(rng.gamma(2.0, 6.0))
            fechamento = dia + timedelta(days=dias_fechar)
            if rng.random() < p_fecha and fechamento <= DATA_REFERENCIA:
                resultado = "fechado"
                kid += 1
                # desconto ocasional; indicação às vezes ganha condição especial
                desconto = rng.choice([0, 0, 0, 250, 500]) + (250 if origem == "indicacao" and rng.random() < 0.3 else 0)
                contratos.append((kid, rid, fechamento.isoformat(), float(3500 - desconto)))
            elif rng.random() < p_fecha and (DATA_REFERENCIA - dia).days < 45:
                resultado = "em_negociacao"
            else:
                resultado = "nao_fechado"
            reunioes.append((rid, cid, a + 1, dia.isoformat(), "realizada", resultado))

    julian_ref = (DATA_REFERENCIA - date(1858, 11, 17)).days + 2400000.5  # dia juliano
    premissas = PREMISSAS + [("data_referencia_juliana", julian_ref, f"data de referência: {DATA_REFERENCIA}")]
    return {"assessores": assessores, "clientes": clientes, "reunioes": reunioes,
            "contratos": contratos, "premissas": premissas}


def criar_banco(caminho: Path = BANCO, semente: int = 2026, aquisicao: bool = True) -> sqlite3.Connection:
    """Cria o banco do funil; com ``aquisicao=True`` inclui canais, leads e investimento."""
    caminho.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(caminho)
    con.executescript((PASTA_SQL / "01_schema.sql").read_text(encoding="utf-8"))
    dados = gerar(semente)
    for tabela, linhas in dados.items():
        marcas = ",".join("?" * len(linhas[0]))
        con.executemany(f"INSERT INTO {tabela} VALUES ({marcas})", linhas)
    con.executescript((PASTA_SQL / "02_views.sql").read_text(encoding="utf-8"))
    con.commit()
    if aquisicao:
        from .aquisicao import criar_camada
        criar_camada(con)
    return con


if __name__ == "__main__":
    con = criar_banco()
    for t in ("assessores", "clientes", "reunioes", "contratos"):
        print(t, con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0])
