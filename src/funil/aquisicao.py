"""Gera a camada de aquisição (FICTÍCIA) por cima do funil já criado.

Regras de geração:
- cada cliente de origem "lead" vira um lead que agendou reunião, numa
  campanha de mídia paga (Meta ou Google);
- para cada lead que agendou, existem vários que não agendaram, conforme a
  taxa de agendamento de cada canal;
- o gasto mensal de cada campanha = leads gerados x custo por lead do mês;
- indicação e base também custam: prêmios do programa de indicação e horas
  de prospecção ativa na carteira.

Os parâmetros foram escolhidos para ficarem ABAIXO das médias de mercado
usadas no plano do estudo de CAC (repositório estudo-cac-aquisicao): é um
cenário de "a campanha rendeu menos que o planejado".

Usa um gerador aleatório próprio, para não alterar os dados do funil.
"""

from __future__ import annotations

import sqlite3
from datetime import date

import numpy as np
import pandas as pd

from .gerar_dados import PASTA_SQL

CANAIS = [(1, "Meta Ads", "midia_paga"), (2, "Google Ads", "midia_paga"),
          (3, "Programa de indicação", "indicacao"), (4, "Relacionamento com a base", "base")]
ORIGEM_CANAL = [("lead", "midia_paga"), ("indicacao", "indicacao"),
                ("base_ativa", "base"), ("base_inativa", "base")]
CAMPANHAS = [(1, 1, "Meta - Reserva de emergência"), (2, 1, "Meta - Aposentadoria"),
             (3, 2, "Google - Planejamento financeiro"),
             (4, 3, "Indique um amigo"), (5, 4, "Prospecção ativa na carteira")]

# Mídia paga: (fatia dos leads que agendaram, taxa de agendamento, CPL médio em R$)
MIDIA = {1: (0.35, 0.085, 70.0), 2: (0.30, 0.085, 74.0), 3: (0.35, 0.160, 118.0)}
CUSTO_FIXO_INDICACAO = 1_500.0      # material e gestão do programa, por mês
PREMIO_INDICACAO = 300.0            # por contrato fechado via indicação
CUSTO_BASE_MES = 4_000.0            # horas do time dedicadas a prospectar a carteira


def _meses(inicio: str, fim: str) -> list[str]:
    return [p.strftime("%Y-%m") for p in pd.period_range(inicio, fim, freq="M")]


def gerar(con: sqlite3.Connection, semente: int = 7) -> dict[str, list[tuple]]:
    rng = np.random.default_rng(semente)
    clientes_lead = pd.read_sql_query(
        "SELECT cliente_id, criado_em FROM clientes WHERE origem = 'lead' ORDER BY cliente_id", con)
    ref = date.fromisoformat(pd.read_sql_query(
        "SELECT date(valor) AS d FROM premissas WHERE chave = 'data_referencia_juliana'", con)["d"][0])

    camp_ids = list(MIDIA)
    fatias = np.array([MIDIA[c][0] for c in camp_ids])
    clientes_lead["campanha_id"] = rng.choice(camp_ids, size=len(clientes_lead), p=fatias / fatias.sum())
    clientes_lead["mes"] = clientes_lead["criado_em"].str[:7]

    leads, lid = [], 0
    for _, r in clientes_lead.iterrows():
        lid += 1
        leads.append((lid, int(r["campanha_id"]), r["criado_em"], int(r["cliente_id"])))

    # leads que não agendaram, distribuídos dentro de cada mês
    contagem = clientes_lead.groupby(["campanha_id", "mes"]).size()
    investimento = []
    for (camp, mes), n_ag in contagem.items():
        taxa = MIDIA[camp][1] * rng.uniform(0.8, 1.2)
        n_total = max(n_ag, int(round(n_ag / taxa)))
        ini = pd.Timestamp(mes + "-01")
        fim = min(ini + pd.offsets.MonthEnd(0), pd.Timestamp(ref))
        dias = (fim - ini).days + 1
        for _ in range(n_total - n_ag):
            lid += 1
            d = (ini + pd.Timedelta(days=int(rng.integers(dias)))).date().isoformat()
            leads.append((lid, int(camp), d, None))
        cpl = MIDIA[camp][2] * rng.uniform(0.85, 1.2)
        investimento.append((int(camp), mes, round(n_total * cpl, 2)))

    # indicação e base: custo fixo mensal + prêmio por contrato fechado via indicação
    meses = _meses(min(m for _, m, _ in investimento), ref.strftime("%Y-%m"))
    fechados = pd.read_sql_query(
        """SELECT strftime('%Y-%m', k.fechado_em) AS mes, COUNT(*) AS n
           FROM contratos k JOIN reunioes r ON r.reuniao_id = k.reuniao_id
           JOIN clientes c ON c.cliente_id = r.cliente_id
           WHERE c.origem = 'indicacao' GROUP BY 1""", con).set_index("mes")["n"]
    for m in meses:
        investimento.append((4, m, CUSTO_FIXO_INDICACAO + PREMIO_INDICACAO * int(fechados.get(m, 0))))
        investimento.append((5, m, CUSTO_BASE_MES))

    return {"canais": CANAIS, "origem_canal": ORIGEM_CANAL, "campanhas": CAMPANHAS,
            "investimento": investimento, "leads": leads}


def criar_camada(con: sqlite3.Connection, semente: int = 7) -> sqlite3.Connection:
    con.executescript((PASTA_SQL / "05_aquisicao.sql").read_text(encoding="utf-8"))
    for tabela, linhas in gerar(con, semente).items():
        marcas = ",".join("?" * len(linhas[0]))
        con.executemany(f"INSERT INTO {tabela} VALUES ({marcas})", linhas)
    con.commit()
    return con
