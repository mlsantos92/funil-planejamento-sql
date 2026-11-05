import pandas as pd
import pytest

from funil.gerar_dados import criar_banco
from funil.relatorio import rodar


@pytest.fixture(scope="module")
def con(tmp_path_factory):
    return criar_banco(tmp_path_factory.mktemp("db") / "teste.db")


@pytest.fixture(scope="module")
def metricas(con):
    return rodar(con, "03_metricas.sql")


def test_qualidade_sem_falhas(con):
    for nome, df in rodar(con, "04_qualidade.sql").items():
        assert df.empty, f"teste de qualidade falhou: {nome}"


def test_dados_sao_reproduziveis(tmp_path):
    a = criar_banco(tmp_path / "a.db").execute("SELECT SUM(valor) FROM contratos").fetchone()
    b = criar_banco(tmp_path / "b.db").execute("SELECT SUM(valor) FROM contratos").fetchone()
    assert a == b


def test_funil_fecha_com_contratos(con, metricas):
    f = metricas["funil_mensal"]
    total = con.execute("SELECT COUNT(*), SUM(valor) FROM contratos").fetchone()
    assert f["contratos"].sum() == total[0]
    assert f["faturamento"].sum() == pytest.approx(total[1])
    assert (f["contratos"] <= f["realizadas"]).all()


def test_participacao_soma_100(metricas):
    r = metricas["ranking_assessores"]
    assert r["participacao_pct"].sum() == pytest.approx(100, abs=0.5)
    assert r["participacao_acumulada_pct"].iloc[-1] == pytest.approx(100)


def test_cenarios_ordenados(metricas):
    c = metricas["cenarios_proximos_meses"].pivot(index="mes", columns="cenario", values="contratos_esperados")
    assert ((c["pessimista"] <= c["normal"]) & (c["normal"] <= c["otimista"])).all()


def test_coorte_entre_0_e_100(metricas):
    c = metricas["coorte_clientes"][["ate_30d_pct", "ate_60d_pct", "ate_90d_pct"]]
    v = c.stack().dropna()
    assert ((v >= 0) & (v <= 100)).all()
    linhas = c.dropna()
    assert (linhas["ate_30d_pct"] <= linhas["ate_60d_pct"]).all()
    assert (linhas["ate_60d_pct"] <= linhas["ate_90d_pct"]).all()
