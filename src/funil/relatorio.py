"""Gera o banco fictício, roda todas as métricas e testes de qualidade, e salva em outputs/.

Uso:  python -m funil.relatorio
"""

from __future__ import annotations

import re
import sqlite3
from pathlib import Path

import pandas as pd

from .gerar_dados import RAIZ, criar_banco

SAIDAS = RAIZ / "outputs"


def consultas(arquivo: str) -> dict[str, str]:
    texto = (RAIZ / "sql" / arquivo).read_text(encoding="utf-8")
    partes = re.split(r"^-- name: (\w+)\s*$", texto, flags=re.M)
    return {partes[i]: partes[i + 1].strip() for i in range(1, len(partes), 2)}


def rodar(con: sqlite3.Connection, arquivo: str) -> dict[str, pd.DataFrame]:
    return {nome: pd.read_sql_query(sql, con) for nome, sql in consultas(arquivo).items()}


def main() -> None:
    SAIDAS.mkdir(exist_ok=True)
    con = criar_banco()

    falhas = {n: len(df) for n, df in rodar(con, "04_qualidade.sql").items() if len(df)}
    print("Qualidade dos dados:", "OK" if not falhas else f"FALHAS {falhas}")

    resultados = rodar(con, "03_metricas.sql")
    for nome, df in resultados.items():
        df.to_csv(SAIDAS / f"{nome}.csv", index=False)
        print(f"\n== {nome}\n{df.head(12).to_string(index=False)}")
    grafico(resultados, SAIDAS / "funil.png")


def grafico(r: dict[str, pd.DataFrame], caminho: Path) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    tinta, tinta2, grade, azul, neutro = "#0b0b0b", "#52514e", "#e4e3df", "#2a78d6", "#b9b8b2"
    nomes = {"indicacao": "Indicação", "base_ativa": "Base ativa", "base_inativa": "Base inativa", "lead": "Lead frio"}
    o = r["conversao_por_origem"].sort_values("conversao_pct")
    t = r["tendencia_conversao"]
    t = t[t["realizadas"] >= 15]  # meses com amostra mínima

    fig, (a1, a2) = plt.subplots(1, 2, figsize=(11, 4), facecolor="#fcfcfb")
    for ax in (a1, a2):
        ax.set_facecolor("#fcfcfb")
        for lado in ("top", "right"):
            ax.spines[lado].set_visible(False)
        ax.tick_params(colors=tinta2, labelsize=9)
        ax.set_axisbelow(True)
    a1.barh(o["origem"].map(nomes), o["conversao_pct"], color=azul, height=0.6)
    for y, v in enumerate(o["conversao_pct"]):
        a1.annotate(f"{v:.0f}%", (v, y), xytext=(4, 0), textcoords="offset points", va="center", fontsize=9, color=tinta)
    a1.grid(axis="x", color=grade)
    a1.set_title("Conversão por origem do cliente", loc="left", color=tinta, fontweight="bold")
    a1.margins(x=0.15)

    x = range(len(t))
    a2.plot(x, t["conversao_pct"], color=neutro, linewidth=1.4, marker="o", markersize=4, label="mês")
    a2.plot(x, t["media_movel_3m_pct"], color=azul, linewidth=2.2, label="média móvel 3 meses")
    a2.set_xticks(list(x), [m[5:] + "/" + m[2:4] for m in t["mes"]])
    a2.set_ylim(0, None)
    a2.grid(axis="y", color=grade)
    a2.set_ylabel("conversão (%)", color=tinta2)
    a2.set_title("Conversão ao longo do ano", loc="left", color=tinta, fontweight="bold")
    a2.legend(frameon=False, fontsize=9)
    fig.text(0.01, 0.01, "Dados fictícios.", fontsize=8, color=tinta2)
    fig.tight_layout(rect=(0, 0.03, 1, 1))
    fig.savefig(caminho, dpi=150, facecolor="#fcfcfb")
    plt.close(fig)


if __name__ == "__main__":
    main()
