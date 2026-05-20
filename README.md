# Model SDDP - 19-05-26 (v8)

Comparação da política **SDDP** vs **3 políticas fixas** para agendamento rodoviário no Ecopátio do Porto de Santos. Roda 2 meses (março + julho), 1000 simulações por política × mês, gera tabelas, PNGs e CSVs.

## Como rodar

A partir da raiz do projeto (`Projeto - IC - Rodoviário/`):

```
julia "Model SDDP - 19-05-26/model_v8.jl"
```

Primeira execução: instala pacotes (~5-10 min). Demais execuções: ~2 min.

## Estrutura

```
Model SDDP - 19-05-26/
├── SPEC.md            ← design do modelo (12 seções)
├── PLAN.md            ← plano de implementação (15 tasks)
├── README.md          ← este arquivo
├── model_v8.jl        ← código (~500 linhas)
└── outputs/           ← gerado automaticamente
    ├── v8_<mes>_fit_histograma.png         (2)
    ├── v8_<mes>_fit_ecdf.png               (2)
    ├── v8_<mes>_custo_boxplot.png          (2, escala log)
    ├── v8_<mes>_custo_ecdf.png             (2)
    ├── v8_<mes>_indicadores_bar.png        (2)
    ├── v8_<mes>_resultados.csv             (2, 4000 linhas cada)
    ├── v8_<mes>_sumario.csv                (2, 4 linhas cada)
    └── v8_<mes>_replica_repr.csv           (2, 30 linhas × 32 colunas)
```

## Resultado-chave (1000 sims)

| Mês | SDDP custo médio | Melhor fixa (P_X3) | Razão |
|-----|---|---|---|
| Março | R$ 51.8 M | R$ 4.86 B | 94× |
| Julho | R$ 203 M | R$ 9.93 B | 49× |

A diferença abissal reflete o fato de o SDDP controlar dinamicamente a **admissão** (admitidos.out variável a cada estágio), enquanto as políticas fixas usam admissão constante em 3000 caminhões/dia (regra D7 do SPEC). Veja seção 6 do SPEC.md para a discussão da assimetria.

## Indicador mais discriminante

**Service level** (% dias com fila < 2000):

| Pol | Mar | Jul |
|---|---|---|
| SDDP | 99.6% | 95.4% |
| P_X3 | 3.5% | 1.5% |
| P_X2 | 2.9% | 0.0% |
| P_X1 | 2.9% | 0.0% |

Política fixa não consegue regular a fila ao longo de 30 dias — fila pico das fixas chega a **24.640 caminhões em março** e **40.122 em julho**, contra **1.716 e 2.351** do SDDP.
