# Análise Comparativa — SDDP vs Políticas Fixas de Admissão (Model v8.3)

**Autor:** Lucas H. — IC USP, Agendamento Rodoviário Porto de Santos
**Data:** 2026-05-20
**Reprodução:** `julia "Model SDDP - 19-05-26/model_v8.jl"` (~2.5 min) + `python "Model SDDP - 19-05-26/plot_v8.py"` (~10 s)

---

## 1. Resumo executivo

Comparação da política dinâmica **SDDP** com **5 políticas fixas de admissão** no Ecopátio do Porto de Santos, em **2 safras** (março e julho), com **`w_proc` fixado pela média do SDDP por dia** (determinístico). 1000 simulações Monte Carlo × 30 dias.

**Definição operacional das políticas fixas (corrigida nesta versão v8.3):**
- Cada política fixa tem `adm_out = X` constante a partir do dia 2 (dia 1 é o estado inicial forçado: `AdmIn=3 000`, `Fila=1 200`).
- **`w_proc[t]` é fixado** como a média dia a dia das 1000 réplicas SDDP. Isso elimina o ruído de amostragem das fixas e isola o efeito da decisão de admissão.
- Processamento é livre: `proc = min(w_proc[t], fila.in + adm.in)`.

A base `X` é a **média de `adm_out` do SDDP nos dias 2..30** (exclui dia 1 distorcido), variando em **±10%, ±5% e 0%**:

| Mês | Base SDDP | X(P_-10) | X(P_-5) | X(P_0) | X(P_+5) | X(P_+10) |
|-----|----------:|---------:|--------:|-------:|--------:|---------:|
| MAR | 2 392 | 2 153 | 2 272 | 2 392 | 2 512 | 2 631 |
| JUL | 1 974 | 1 777 | 1 875 | 1 974 | 2 073 | 2 172 |

**Resultados-chave:**

| | MAR | JUL |
|---|----:|----:|
| SDDP custo médio | R$ 52.0 M | R$ 204 M |
| **Melhor fixa** | **P_0 = R$ 114 M (2.2× SDDP)** | **P_0 = R$ 181 M (0.89× SDDP)** ⚠️ |
| Pior fixa | P_+10 = R$ 1.62 B (31× SDDP) | P_+10 = R$ 1.21 B (5.9× SDDP) |

### 1.1 ATENÇÃO: como interpretar "spillover" (questão de unidade)

Antes de qualquer análise, é fundamental entender o que a métrica de spillover representa neste modelo.

**Spillover NÃO é "caminhões que extravasaram naquele dia"** (isso seria um *fluxo*). Pela definição matemática do v7:

```
spillover[t]  ≥  fila.in[t] + admitidos.in[t] − CAP_ECOPATIO − processados[t]
             =  fila.out[t] − CAP_ECOPATIO    (pelo balanço de fila)
```

Ou seja, spillover[t] = `max(0, fila.out[t] − 1 200)` = **quantos caminhões estão FORA do pátio no fim do dia t** (medido instantaneamente como um estado).

**Implicações:**
- O custo `C_SPILLOVER × spillover[t]` = R$ 16 211 cobrados **por cada caminhão fora do pátio, por dia** (como "diária de estacionamento externo").
- A **soma de 30 dias** é a unidade física **"caminhão-dia em excesso"**, não "caminhões físicos extravasados".
- Por isso a tabela mostra valores como "P_+10 MAR spillover total = 80 463" — não significa 80 mil caminhões físicos, e sim "80 mil caminhão-dias" em excesso ao longo do horizonte. **Equivale a ter ~2 680 caminhões fora do pátio em média, todos os dias dos 30 dias.**

**Validação manual** (P_+10 MAR dia 30): fila_in=5 950 + adm_in=2 631 − proc=2 489 = fila_out=**6 092**. Spillover = max(0, 6 092 − 1 200) = **4 892**. Significa: nesse dia, 4 892 caminhões estão fora do pátio. CSV confere com exatidão.

> **Nota importante:** o modelo v7 NÃO tem restrição física de fila ≤ MAX_VAGAS. Permite filas ilimitadas, mas penaliza pesadamente cada caminhão acima do CAP_ECOPATIO=1 200. Isso é uma escolha de modelagem econômica (não restritiva), herdada do v7 e mantida intencionalmente no v8.

### 1.2 Achado contraintuitivo em JUL: fixa P_0 é melhor que SDDP

Em julho, a fixa **P_0 (R$ 181 M) é melhor que o SDDP (R$ 204 M)**. Política dinâmica deveria sempre ganhar de política fixa — por que isso acontece?

- **SDDP** é simulado em **mundo estocástico**: a cada dia, `w_proc` é amostrado da distribuição Weibull (sd=754). O SDDP precisa lidar com a variabilidade real.
- **Política fixa** usa `w_proc` **médio** do SDDP (sd=0 no input). Opera no "mundo médio idealizado" — sem nenhuma incerteza.

A diferença SDDP − P_0 = R$ 23 M em jul **é o custo da incerteza realmente enfrentada pelo SDDP**, que a fixa determinística não vê.

**Em MAR isso não acontece** porque `w_proc` tem CV baixo (10%) — a variabilidade é pequena demais para a fixa "ganhar de graça". Em JUL (CV=36%), a fixa com `w_proc` médio fica significativamente mais fácil que a realidade.

> **Interpretação correta:** as fixas com `w_proc` médio fixo são um **limite inferior teórico** — assumindo condições idealmente médias. O SDDP fica acima delas em MAR (situação favorável às fixas), mas abaixo em JUL (variância alta valoriza adaptatividade).

---

## 2. Modelo (idêntico ao v7)

**Variáveis (a cada dia t):**

| Símbolo | Tipo | Domínio | Significado |
|---------|------|---------|-------------|
| `fila` | estado | ≥ 0 | caminhões em fila no início do dia |
| `admitidos` | estado | [0, MAX_VAGAS=4 000] | caminhões admitidos para o próximo dia |
| `processados` | decisão | ≥ 0 | caminhões processados no dia |
| `spillover` | decisão | ≥ 0 | caminhões em excesso ao pátio |
| `ocioso` | decisão | ≥ 0 | capacidade não utilizada |
| `w_proc` | aleatório (SDDP) / fixo (fixa) | ~dist(mês) | capacidade aleatória de processamento |

**Restrições e função objetivo:**

```
processados ≤ w_proc
processados ≤ fila.in + admitidos.in
fila.out    = fila.in + admitidos.in − processados
spillover   ≥ fila.in + admitidos.in − CAP_ECOPATIO − processados
ocioso      ≥ w_proc − processados

obj = Σ_t [ C_FILA·(fila.in+fila.out)/2 + C_SPILLOVER·spillover + C_OCIOSO_TOTAL·ocioso ]
```

**Constantes:** `C_FILA=2 790`, `C_SPILLOVER=16 211`, `C_OCIOSO_TOTAL=43 753`, `CAP_ECOPATIO=1 200`, `MAX_VAGAS=4 000`, `FILA_INICIAL=1 200`, `ADMITIDOS_INICIAL=3 000`, `NUM_DIAS=30`.

---

## 3. Dados e distribuições

| Mês | Média (cam./dia) | sd | CV | Dist escolhida | AIC | KS p-value |
|-----|-----------------:|---:|---:|----------------|----:|-----------:|
| **mar** | 2 480.2 | 251.3 | 0.10 | **LogNormal** | 417.5 | 0.55 |
| **jul** | 2 102.1 | 754.6 | 0.36 | **Weibull** | 484.8 | 0.93 |

---

## 4. Políticas avaliadas

### 4.1 SDDP — referência (estocástico)

A cada dia `t`, `w_proc[t]` é **amostrado** da distribuição ajustada → 1000 cenários estocásticos. SDDP decide `(processados[t], admitidos.out[t])` em função do estado.

### 4.2 Cinco políticas fixas P_X (determinísticas)

**Regra operacional:**

```
estado inicial: fila = 1 200, adm_in = 3 000 (igual ao SDDP)
para t = 1..30:
    w_proc[t] = mean_{r=1..1000} w_proc_SDDP[r, t]   ← FIXO, NÃO AMOSTRADO
    processados[t] = min(w_proc[t], fila.in + adm.in)   ← processa o máximo possível
    spillover[t]   = max(0, fila.in + adm.in − 1 200 − processados[t])
    ocioso[t]      = max(0, w_proc[t] − processados[t])
    fila_out       = fila.in + adm.in − processados[t]
    adm_out        = X   ← REGRA FIXA DE ADMISSÃO
```

**Por que `w_proc` médio fixo?** Para isolar o efeito da decisão de admissão. Se a fixa usasse `w_proc` amostrado independente, o custo dela teria componentes de variância que não estão na decisão de política, e a comparação ficaria confundida.

---

## 5. Resultados agregados

### 5.1 Sumário comparativo — MAR (N=1000)

| Política | X | Custo médio | IC 95% | P5 | P50 | P95 | Spill % > 0 | Fila pico médio | Service level |
|----------|--:|------------:|-------:|---:|----:|----:|-----------:|----------------:|--------------:|
| **SDDP** | — | **R$ 52.0 M** | ± 0.46 M | 40.1 M | 51.8 M | 64.7 M | 98.9% | **1 724** | **100.0%** |
| `P_-10` | 2 153 | R$ 368 M | ± 0 | 368 M | 368 M | 368 M | 100% | 1 724 | 100.0% |
| `P_-5` | 2 272 | R$ 227 M | ± 0 | 227 M | 227 M | 227 M | 100% | 1 724 | 100.0% |
| `P_0` | 2 392 | **R$ 114 M** | ± 0 | 114 M | 114 M | 114 M | 100% | **1 724** | **100.0%** |
| `P_+5` | 2 512 | R$ 639 M | ± 0 | 639 M | 639 M | 639 M | 100% | 2 623 | 98.8% |
| `P_+10` | 2 631 | R$ 1.62 B | ± 0 | 1.62 B | 1.62 B | 1.62 B | 100% | 6 092 | 94.3% |

**Razão melhor fixa / SDDP em mar: 2.2× (P_0).** IC=0 nas fixas (determinísticas).

### 5.2 Sumário comparativo — JUL (N=1000)

| Política | X | Custo médio | IC 95% | P5 | P50 | P95 | Spill % > 0 | Fila pico médio | Service level |
|----------|--:|------------:|-------:|---:|----:|----:|-----------:|----------------:|--------------:|
| **SDDP** | — | R$ 204 M | ± 2.75 M | 138 M | 201 M | 281 M | 100% | **2 363** | **100.0%** |
| `P_-10` | 1 777 | R$ 369 M | ± 0 | 369 M | 369 M | 369 M | 100% | 2 105 | 100.0% |
| `P_-5` | 1 875 | R$ 261 M | ± 0 | 261 M | 261 M | 261 M | 100% | 2 105 | 100.0% |
| `P_0` | 1 974 | **R$ 181 M** | ± 0 | 181 M | 181 M | 181 M | 100% | **2 105** | **100.0%** |
| `P_+5` | 2 073 | R$ 397 M | ± 0 | 397 M | 397 M | 397 M | 100% | 2 105 | 100.0% |
| `P_+10` | 2 172 | R$ 1.21 B | ± 0 | 1.21 B | 1.21 B | 1.21 B | 100% | 4 219 | 96.6% |

**P_0 (R$ 181 M) < SDDP (R$ 204 M)!** Razão melhor fixa / SDDP em jul: **0.89× (P_0 ganha)** — vide diagnóstico em §1.2.

### 5.3 Visualizações comparativas

![boxplot mar](outputs/py_v8_mar_boxplot.png)

![boxplot jul](outputs/py_v8_jul_boxplot.png)

![service mar](outputs/py_v8_mar_service_level.png)

![service jul](outputs/py_v8_jul_service_level.png)

![composicao mar](outputs/py_v8_mar_composicao_custo.png)

![composicao jul](outputs/py_v8_jul_composicao_custo.png)

---

## 6. Indicadores em detalhe (catálogo)

### 6.1 — Custo médio total (R$)

**Fórmula:** `(1/N) · Σ_r Σ_t  stage_objective[r,t]`. Em fixas, todas réplicas são idênticas (determinístico).

| Política | MAR | JUL |
|----------|----:|----:|
| **SDDP** | **R$ 52.0 M** | R$ 204 M |
| P_-10 | R$ 368 M | R$ 369 M |
| P_-5 | R$ 227 M | R$ 261 M |
| P_0 | R$ 114 M | **R$ 181 M** |
| P_+5 | R$ 639 M | R$ 397 M |
| P_+10 | R$ 1.62 B | R$ 1.21 B |

### 6.2 — Intervalo de confiança 95%

| Política | IC MAR | IC JUL |
|----------|-------:|-------:|
| SDDP | ± 0.46 M | ± 2.57 M |
| P_-10..P_+10 | ± 0 (determinísticos) | ± 0 (determinísticos) |

### 6.3 — Quantis P5/P50/P95 do custo

Fixas determinísticas → P5 = P50 = P95 = custo único.

| | SDDP MAR | SDDP JUL |
|---|---:|---:|
| P5 | 41.5 M | 139 M |
| P50 | 51.5 M | 200 M |
| P95 | 65.0 M | 275 M |
| Spread (P95-P5) | 23.5 M | 136 M |

### 6.4 — Probabilidade de spillover > 0

| Política | MAR | JUL |
|----------|----:|----:|
| SDDP | 98.8% | 100.0% |
| P_-10 a P_+10 | 100% (todas) | 100% (todas) |

Dia 1 sempre gera spillover (estado inicial: 1 200 + 3 000 > 1 200 + ~2 480). SDDP em mar zera spillover em 1.2% dos cenários favoráveis.

### 6.5 — Spillover total condicional médio (caminhões)

| Política | MAR | JUL |
|----------|----:|----:|
| SDDP | 514 | 4 035 |
| P_-10 | 691 | 1 545 |
| P_-5 | 899 | 1 978 |
| P_0 | 1 691 | 3 150 |
| P_+5 | 28 708 | 15 701 |
| P_+10 | 80 717 | 58 696 |

### 6.6 — Fila pico médio (caminhões)

| Política | MAR | JUL | × MAX_VAGAS (4 000) |
|----------|----:|----:|--------------------:|
| SDDP | 1 707 | 2 331 | 0.43 / 0.58 |
| P_-10..P_0 | 1 707 | 2 068 | 0.43 / 0.52 |
| P_+5 | 2 602 | 2 068 | 0.65 / 0.52 |
| P_+10 | 6 069 | 4 243 | **1.52** / **1.06** |

**Fila pico = pico do dia 1** para a maioria das fixas (estado inicial 1 200 + 3 000 − w_proc).

### 6.7 — Service level (% processado da demanda admitida, dias 2..30)

**Fórmula (NOVA):**
```
service_level = min(1.0,  Σ_t=2..30 processados / Σ_t=2..30 admitidos.in)
```

> **Mudanças nesta versão:** exclui dia 1 (estado inicial distorce); cap em 100% (consumir fila inicial não é defensável para o relatório).

| Política | MAR | JUL |
|----------|----:|----:|
| **SDDP** | **100.0%** | **100.0%** |
| P_-10 | 100.0% | 100.0% |
| P_-5 | 100.0% | 100.0% |
| P_0 | 100.0% | 100.0% |
| P_+5 | 98.8% | 100.0% |
| P_+10 | 94.3% | 96.6% |

Todas com X ≤ X(P_0) atingem 100%. Apenas X alto deixa demanda acumulada.

### 6.8 — Médias diárias

**MAR:**

| Política | entram/dia | proc/dia | ocio/dia | spill/dia |
|----------|----------:|---------:|---------:|----------:|
| SDDP | 2 450 | 2 475 | 5.2 | 16.9 |
| P_-10 | 2 180 | 2 220 | 260.0 | 23.0 |
| P_-5 | 2 296 | 2 336 | 144.4 | 30.0 |
| P_0 | 2 412 | 2 452 | 28.8 | 56.4 |
| P_+5 | 2 527 | 2 480 | 0.0 | 957 |
| P_+10 | 2 643 | 2 480 | 0.0 | 2 691 |

**JUL:**

| Política | entram/dia | proc/dia | ocio/dia | spill/dia |
|----------|----------:|---------:|---------:|----------:|
| SDDP | 2 038 | 2 051 | 49.7 | 134 |
| P_-10 | 1 820 | 1 860 | 240.7 | 51.5 |
| P_-5 | 1 915 | 1 955 | 145.2 | 65.9 |
| P_0 | 2 011 | 2 051 | 49.6 | 105 |
| P_+5 | 2 106 | 2 101 | 0.0 | 523 |
| P_+10 | 2 202 | 2 101 | 0.0 | 1 957 |

### 6.9 — Resumo: qual indicador olhar quando?

| Quando você quer responder... | Indicador | Por quê |
|------|------|------|
| "Quanto custa?" | §6.1 Custo médio | Métrica gerencial principal |
| "É estatisticamente diferente?" | §6.2 IC 95% | Fixas têm IC=0 |
| "E se eu tiver azar (SDDP)?" | §6.3 P95 | Apenas SDDP tem distribuição |
| "Risco de pátio cheio?" | §6.6 Fila pico | Comparar com MAX_VAGAS=4 000 |
| "Toda demanda é processada?" | §6.7 Service level | Cap 100%, dias 2..30 |
| "Operação dia a dia?" | §6.8 Médias diárias | Throughput operacional |

---

## 7. Evolução dia-a-dia (média das 1000 sims)

### 7.1 Painel de 4 variáveis (proc, fila, ocioso log, spillover log)

![painel mar](outputs/py_v8_mar_painel.png)

![painel jul](outputs/py_v8_jul_painel.png)

### 7.2 Custo acumulado (escala log, com anotação)

![custo acumulado mar](outputs/py_v8_mar_custo_acumulado.png)

![custo acumulado jul](outputs/py_v8_jul_custo_acumulado.png)

### 7.3 Comparativo mar vs jul (side-by-side)

![comparativo mar vs jul](outputs/py_v8_mar_jul_comparativo.png)

---

## 8. Análise: o trade-off operacional

### 8.1 Os 3 regimes operacionais (visíveis nas tabelas do Anexo A)

**Regime "esvazia + ocioso" (P_-10, P_-5):**
- `X` baixo → admite pouco → fila esvazia
- Em MAR P_-10: fila chega a zero no dia 7. Depois, ociosidade ~330/dia.
- Em JUL P_-10: fila zera no dia 8. Ociosidade ~310/dia depois.
- Custo dominado por ociosidade × R$ 43 753

**Regime "equilíbrio" (P_0):**
- `X ≈ w_proc médio` → admite ≈ processa
- MAR P_0: fila começa em 1 707 (dia 1), cai gradualmente. Esvazia no dia 21.
- JUL P_0: fila começa em 2 068, cai gradualmente. Esvazia no dia 19.
- Custo balanceado: spillover inicial decrescente + algum ocioso no final.

**Regime "acumula + spillover" (P_+5, P_+10):**
- `X` alto → admite mais do que se processa → fila cresce monotonicamente
- MAR P_+10: fila chega a 6 069 (dia 30). Spillover cresce.
- JUL P_+10: fila chega a 4 243. Estoura MAX_VAGAS.
- Custo dominado por fila + spillover

### 8.2 Por que P_0 fixa vence o SDDP em julho

O SDDP enfrenta `w_proc` Weibull com cauda esquerda longa (CV=36%). Mesmo decidindo otimamente, em alguns dias `w_proc[t]` cai para ~700–1 000, gerando custos altos.

A fixa P_0 usa `w_proc[t]` = média (range 2 058–2 147 em jul). Essa "remoção da incerteza" gera economia que **mais que compensa** o erro de admissão constante.

**Em MAR**, com `w_proc` quase constante (CV=10%), a remoção de incerteza vale pouco — SDDP continua melhor.

**Lição metodológica:** a comparação com `w_proc` fixo é informativa para entender o trade-off, mas **não é a comparação operacional honesta**. Para isso seria necessário:
- (a) `w_proc` amostrado independente nas fixas (com ruído de variância)
- (b) `w_proc` amostrado com CRN entre SDDP e fixas (justo réplica-a-réplica)

Esta versão usa (c) — `w_proc` fixo = média SDDP — para isolar o efeito da decisão de admissão.

### 8.3 O `Smoking gun` — confira no Anexo A

Olhe a tabela `SDDP MAR` (Anexo A, A.1) na linha do dia 1:

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | **3000** | 2493 | 2493 | 1707 | 507.8 | 0.0 | **1150** | 12.29M |
| 2 | 1707 | **1150** | 2476 | 2471 | 386.0 | 0.0 | 4.6 | 2471 | 3.12M |

SDDP entra forçado com `AdmIn = 3 000` mas decide `AdmOut = 1 150` (corta em 62%). A partir do dia 2 mantém `AdmOut ≈ proc ≈ 2 470`.

A fixa `P_0 MAR` admite 2 391 constante em todos os dias 2..30 — fila esvazia consumindo o estoque inicial.

---

## 9. Conclusões e recomendação

1. **Em MAR (baixa variância de w_proc), o SDDP é melhor** que todas as fixas (mínimo P_0 = 2.2× SDDP).
2. **Em JUL (alta variância), a fixa P_0 com w_proc médio fixo é melhor que o SDDP** em 17% (R$ 168 M vs R$ 202 M). Reflete que a fixa opera no "mundo médio" sem variabilidade real.
3. **A vantagem real do SDDP é a adaptatividade ao ruído estocástico.** Comparações justas requerem que tanto SDDP quanto fixas operem no mesmo mundo (mesma realização de `w_proc`).
4. **Service level fica em 100% para X ≤ X(P_0)** em ambos os meses. Apenas X alto (P_+5/P_+10) deixa demanda acumulada.
5. **Fila pico:** todas as políticas com X ≤ X(P_+5) ficam abaixo de MAX_VAGAS=4 000 (operacionalmente viáveis). P_+10 estoura.

**Próximo passo (v9):** rodar as 5 fixas com `w_proc` **amostrado** (CRN entre fixas e SDDP). Esperado: P_0 fica acima do SDDP em ambos os meses (cenário honesto), com razão 1.3×-2×.

---

## 10. Artefatos

| Categoria | Arquivos |
|-----------|----------|
| Código Julia | [model_v8.jl](model_v8.jl) |
| Código Python | [plot_v8.py](plot_v8.py) |
| Docs | [SPEC.md](SPEC.md), [PLAN.md](PLAN.md), [README.md](README.md), este ANALISE.md |
| PNGs Python (publicação) | `py_v8_<mes>_*.png` — 15 PNGs |
| PNGs Julia (baseline) | `v8_<mes>_*.png` — 22 PNGs |
| Sumário | [`outputs/v8_<mes>_sumario.csv`](outputs/) |
| Médias dia-a-dia (completo) | [`outputs/v8_<mes>_dia_a_dia.csv`](outputs/) (30 × 61 cols) |
| Tabelas formato v7 | [`tabelas_v7_md.txt`](tabelas_v7_md.txt) — 12 tabelas, 30 dias cada |

Total em [`outputs/`](outputs/): **37 PNGs + 8 CSVs**.

**Como rodar do zero:**

```
cd "Projeto - IC - Rodoviário"
julia "Model SDDP - 19-05-26/model_v8.jl"     # ~2.5 min
python "Model SDDP - 19-05-26/plot_v8.py"     # ~10 s
```

---

---

## Anexo A — MAR: cenário médio dia-a-dia (1000 sims SDDP + 5 fixas ±10%, ±5%, 0%)

**Base usada nos gráficos e análises do corpo principal.**

> **Nota metodológica (importante):**
> - **Para o SDDP**, esta tabela mostra uma **trajetória reconstruída a partir das médias** das 1000 simulações. Cada coluna (FilaIni, AdmIn, w_proc, Proc, FilaFim, AdmOut) é a média daquela variável no dia t entre as 1000 réplicas. **Spill e Ocioso são RECALCULADOS** pelas fórmulas (`Spill = max(0, FilaFim − 1 200)`, `Ocioso = max(0, w_proc − Proc)`) para que os números fechem linha a linha.
> - **Para as fixas P_-10..P_+10**, a trajetória já é determinística (w_proc fixo, adm_out=X constante), então os valores são exatos.
> - **Importante:** o **custo total Σ da linha SDDP nesta tabela** ≠ **custo médio real do SDDP** (Tabela 5.1/5.2). A diferença é o "custo da variabilidade estocástica" — Jensen.
>   - MAR SDDP: Σ tabela = R$ 51.8 M, real (§5.2) = R$ 52.0 M (diferença ~0%, baixa variância).
>   - JUL SDDP: Σ tabela = **R$ 149.9 M**, real (§5.2) = **R$ 204 M** (diferença ~R$ 54 M = custo da variabilidade alta da Weibull).

#### MAR — Política `SDDP` (média 1000 sims SDDP — Spill/Ocioso/Custo recalculados sobre médias)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2481 | 2481 | 1719 | 518.8 | 0.0 | 1138 | 12.48M |
| 2 | 1719 | 1138 | 2481 | 2475 | 382.5 | 0.0 | 6.2 | 2475 | 3.20M |
| 3 | 382.5 | 2475 | 2473 | 2468 | 388.6 | 0.0 | 4.5 | 2468 | 1.27M |
| 4 | 388.6 | 2468 | 2474 | 2469 | 388.2 | 0.0 | 4.8 | 2469 | 1.29M |
| 5 | 388.2 | 2469 | 2479 | 2475 | 382.4 | 0.0 | 4.9 | 2475 | 1.29M |
| 6 | 382.4 | 2475 | 2492 | 2485 | 371.8 | 0.0 | 6.5 | 2485 | 1.34M |
| 7 | 371.8 | 2485 | 2468 | 2464 | 393.0 | 0.0 | 4.0 | 2464 | 1.24M |
| 8 | 393.0 | 2464 | 2486 | 2481 | 376.4 | 0.0 | 5.2 | 2481 | 1.30M |
| 9 | 376.4 | 2481 | 2485 | 2479 | 377.9 | 0.0 | 5.6 | 2479 | 1.30M |
| 10 | 377.9 | 2479 | 2457 | 2452 | 405.2 | 0.0 | 5.3 | 2452 | 1.32M |
| 11 | 405.2 | 2452 | 2473 | 2469 | 387.7 | 0.0 | 3.7 | 2469 | 1.27M |
| 12 | 387.7 | 2469 | 2468 | 2464 | 393.0 | 0.0 | 3.9 | 2464 | 1.26M |
| 13 | 393.0 | 2464 | 2478 | 2474 | 383.1 | 0.0 | 4.5 | 2474 | 1.28M |
| 14 | 383.1 | 2474 | 2482 | 2476 | 381.5 | 0.0 | 6.8 | 2476 | 1.36M |
| 15 | 381.5 | 2476 | 2476 | 2471 | 386.3 | 0.0 | 5.3 | 2471 | 1.30M |
| 16 | 386.3 | 2471 | 2486 | 2480 | 376.9 | 0.0 | 6.0 | 2480 | 1.33M |
| 17 | 376.9 | 2480 | 2473 | 2468 | 388.6 | 0.0 | 4.6 | 2468 | 1.27M |
| 18 | 388.6 | 2468 | 2482 | 2476 | 381.1 | 0.0 | 6.3 | 2476 | 1.35M |
| 19 | 381.1 | 2476 | 2474 | 2470 | 387.4 | 0.0 | 4.4 | 2470 | 1.27M |
| 20 | 387.4 | 2470 | 2483 | 2477 | 379.9 | 0.0 | 5.4 | 2477 | 1.31M |
| 21 | 379.9 | 2477 | 2474 | 2470 | 387.4 | 0.0 | 4.9 | 2470 | 1.29M |
| 22 | 387.4 | 2470 | 2472 | 2466 | 390.7 | 0.0 | 5.4 | 2466 | 1.32M |
| 23 | 390.7 | 2466 | 2482 | 2476 | 380.9 | 0.0 | 5.6 | 2476 | 1.32M |
| 24 | 380.9 | 2476 | 2475 | 2471 | 386.0 | 0.0 | 4.3 | 2471 | 1.26M |
| 25 | 386.0 | 2471 | 2488 | 2480 | 376.7 | 0.0 | 7.2 | 2480 | 1.38M |
| 26 | 376.7 | 2480 | 2485 | 2480 | 376.9 | 0.0 | 5.0 | 2480 | 1.27M |
| 27 | 376.9 | 2480 | 2467 | 2462 | 394.7 | 0.0 | 4.9 | 2462 | 1.29M |
| 28 | 394.7 | 2462 | 2487 | 2481 | 376.0 | 0.0 | 6.4 | 2481 | 1.36M |
| 29 | 376.0 | 2481 | 2470 | 2465 | 392.1 | 0.0 | 5.3 | 2533 | 1.30M |
| 30 | 392.1 | 2533 | 2475 | 2473 | 452.2 | 0.0 | 2.1 | 0.0 | 1.27M |
| **Σ** | — | — | — | **74177** | — | **518.8** | **148.9** | — | **52.08M** |

#### MAR — Política `P_-10` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2481 | 2481 | 1719 | 518.8 | 0.0 | 2150 | 12.48M |
| 2 | 1719 | 2150 | 2481 | 2481 | 1389 | 188.5 | 0.0 | 2150 | 7.39M |
| 3 | 1389 | 2150 | 2473 | 2473 | 1066 | 0.0 | 0.0 | 2150 | 3.42M |
| 4 | 1066 | 2150 | 2474 | 2474 | 742.8 | 0.0 | 0.0 | 2150 | 2.52M |
| 5 | 742.8 | 2150 | 2479 | 2479 | 413.8 | 0.0 | 0.0 | 2150 | 1.61M |
| 6 | 413.8 | 2150 | 2492 | 2492 | 72.5 | 0.0 | 0.0 | 2150 | 678287 |
| 7 | 72.5 | 2150 | 2468 | 2223 | 0.0 | 0.0 | 245.1 | 2150 | 10.82M |
| 8 | 0.0 | 2150 | 2486 | 2150 | 0.0 | 0.0 | 335.5 | 2150 | 14.68M |
| 9 | 0.0 | 2150 | 2485 | 2150 | 0.0 | 0.0 | 334.3 | 2150 | 14.63M |
| 10 | 0.0 | 2150 | 2457 | 2150 | 0.0 | 0.0 | 306.7 | 2150 | 13.42M |
| 11 | 0.0 | 2150 | 2473 | 2150 | 0.0 | 0.0 | 322.5 | 2150 | 14.11M |
| 12 | 0.0 | 2150 | 2468 | 2150 | 0.0 | 0.0 | 317.5 | 2150 | 13.89M |
| 13 | 0.0 | 2150 | 2478 | 2150 | 0.0 | 0.0 | 328.0 | 2150 | 14.35M |
| 14 | 0.0 | 2150 | 2482 | 2150 | 0.0 | 0.0 | 331.9 | 2150 | 14.52M |
| 15 | 0.0 | 2150 | 2476 | 2150 | 0.0 | 0.0 | 325.6 | 2150 | 14.25M |
| 16 | 0.0 | 2150 | 2486 | 2150 | 0.0 | 0.0 | 335.6 | 2150 | 14.68M |
| 17 | 0.0 | 2150 | 2473 | 2150 | 0.0 | 0.0 | 322.6 | 2150 | 14.11M |
| 18 | 0.0 | 2150 | 2482 | 2150 | 0.0 | 0.0 | 331.8 | 2150 | 14.52M |
| 19 | 0.0 | 2150 | 2474 | 2150 | 0.0 | 0.0 | 323.6 | 2150 | 14.16M |
| 20 | 0.0 | 2150 | 2483 | 2150 | 0.0 | 0.0 | 332.1 | 2150 | 14.53M |
| 21 | 0.0 | 2150 | 2474 | 2150 | 0.0 | 0.0 | 324.1 | 2150 | 14.18M |
| 22 | 0.0 | 2150 | 2472 | 2150 | 0.0 | 0.0 | 321.3 | 2150 | 14.06M |
| 23 | 0.0 | 2150 | 2482 | 2150 | 0.0 | 0.0 | 331.3 | 2150 | 14.49M |
| 24 | 0.0 | 2150 | 2475 | 2150 | 0.0 | 0.0 | 324.9 | 2150 | 14.22M |
| 25 | 0.0 | 2150 | 2488 | 2150 | 0.0 | 0.0 | 337.1 | 2150 | 14.75M |
| 26 | 0.0 | 2150 | 2485 | 2150 | 0.0 | 0.0 | 334.7 | 2150 | 14.64M |
| 27 | 0.0 | 2150 | 2467 | 2150 | 0.0 | 0.0 | 316.7 | 2150 | 13.86M |
| 28 | 0.0 | 2150 | 2487 | 2150 | 0.0 | 0.0 | 337.0 | 2150 | 14.75M |
| 29 | 0.0 | 2150 | 2470 | 2150 | 0.0 | 0.0 | 319.8 | 2150 | 13.99M |
| 30 | 0.0 | 2150 | 2475 | 2150 | 0.0 | 0.0 | 324.5 | 2150 | 14.20M |
| **Σ** | — | — | — | **66562** | — | **707.3** | **7764** | — | **367.91M** |

#### MAR — Política `P_-5` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2481 | 2481 | 1719 | 518.8 | 0.0 | 2270 | 12.48M |
| 2 | 1719 | 2270 | 2481 | 2481 | 1508 | 308.0 | 0.0 | 2270 | 9.49M |
| 3 | 1508 | 2270 | 2473 | 2473 | 1305 | 104.9 | 0.0 | 2270 | 5.63M |
| 4 | 1305 | 2270 | 2474 | 2474 | 1101 | 0.0 | 0.0 | 2270 | 3.36M |
| 5 | 1101 | 2270 | 2479 | 2479 | 891.6 | 0.0 | 0.0 | 2270 | 2.78M |
| 6 | 891.6 | 2270 | 2492 | 2492 | 669.8 | 0.0 | 0.0 | 2270 | 2.18M |
| 7 | 669.8 | 2270 | 2468 | 2468 | 471.7 | 0.0 | 0.0 | 2270 | 1.59M |
| 8 | 471.7 | 2270 | 2486 | 2486 | 255.8 | 0.0 | 0.0 | 2270 | 1.01M |
| 9 | 255.8 | 2270 | 2485 | 2485 | 40.9 | 0.0 | 0.0 | 2270 | 413880 |
| 10 | 40.9 | 2270 | 2457 | 2311 | 0.0 | 0.0 | 146.3 | 2270 | 6.46M |
| 11 | 0.0 | 2270 | 2473 | 2270 | 0.0 | 0.0 | 203.0 | 2270 | 8.88M |
| 12 | 0.0 | 2270 | 2468 | 2270 | 0.0 | 0.0 | 198.0 | 2270 | 8.66M |
| 13 | 0.0 | 2270 | 2478 | 2270 | 0.0 | 0.0 | 208.5 | 2270 | 9.12M |
| 14 | 0.0 | 2270 | 2482 | 2270 | 0.0 | 0.0 | 212.4 | 2270 | 9.29M |
| 15 | 0.0 | 2270 | 2476 | 2270 | 0.0 | 0.0 | 206.1 | 2270 | 9.02M |
| 16 | 0.0 | 2270 | 2486 | 2270 | 0.0 | 0.0 | 216.2 | 2270 | 9.46M |
| 17 | 0.0 | 2270 | 2473 | 2270 | 0.0 | 0.0 | 203.1 | 2270 | 8.89M |
| 18 | 0.0 | 2270 | 2482 | 2270 | 0.0 | 0.0 | 212.3 | 2270 | 9.29M |
| 19 | 0.0 | 2270 | 2474 | 2270 | 0.0 | 0.0 | 204.1 | 2270 | 8.93M |
| 20 | 0.0 | 2270 | 2483 | 2270 | 0.0 | 0.0 | 212.6 | 2270 | 9.30M |
| 21 | 0.0 | 2270 | 2474 | 2270 | 0.0 | 0.0 | 204.6 | 2270 | 8.95M |
| 22 | 0.0 | 2270 | 2472 | 2270 | 0.0 | 0.0 | 201.8 | 2270 | 8.83M |
| 23 | 0.0 | 2270 | 2482 | 2270 | 0.0 | 0.0 | 211.8 | 2270 | 9.27M |
| 24 | 0.0 | 2270 | 2475 | 2270 | 0.0 | 0.0 | 205.4 | 2270 | 8.99M |
| 25 | 0.0 | 2270 | 2488 | 2270 | 0.0 | 0.0 | 217.7 | 2270 | 9.52M |
| 26 | 0.0 | 2270 | 2485 | 2270 | 0.0 | 0.0 | 215.2 | 2270 | 9.42M |
| 27 | 0.0 | 2270 | 2467 | 2270 | 0.0 | 0.0 | 197.3 | 2270 | 8.63M |
| 28 | 0.0 | 2270 | 2487 | 2270 | 0.0 | 0.0 | 217.6 | 2270 | 9.52M |
| 29 | 0.0 | 2270 | 2470 | 2270 | 0.0 | 0.0 | 200.3 | 2270 | 8.76M |
| 30 | 0.0 | 2270 | 2475 | 2270 | 0.0 | 0.0 | 205.0 | 2270 | 8.97M |
| **Σ** | — | — | — | **70027** | — | **931.8** | **4299** | — | **227.11M** |

#### MAR — Política `P_0` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2481 | 2481 | 1719 | 518.8 | 0.0 | 2389 | 12.48M |
| 2 | 1719 | 2389 | 2481 | 2481 | 1627 | 427.5 | 0.0 | 2389 | 11.60M |
| 3 | 1627 | 2389 | 2473 | 2473 | 1544 | 343.9 | 0.0 | 2389 | 10.00M |
| 4 | 1544 | 2389 | 2474 | 2474 | 1460 | 259.6 | 0.0 | 2389 | 8.40M |
| 5 | 1460 | 2389 | 2479 | 2479 | 1370 | 169.5 | 0.0 | 2389 | 6.69M |
| 6 | 1370 | 2389 | 2492 | 2492 | 1267 | 67.1 | 0.0 | 2389 | 4.77M |
| 7 | 1267 | 2389 | 2468 | 2468 | 1189 | 0.0 | 0.0 | 2389 | 3.43M |
| 8 | 1189 | 2389 | 2486 | 2486 | 1092 | 0.0 | 0.0 | 2389 | 3.18M |
| 9 | 1092 | 2389 | 2485 | 2485 | 996.7 | 0.0 | 0.0 | 2389 | 2.91M |
| 10 | 996.7 | 2389 | 2457 | 2457 | 929.0 | 0.0 | 0.0 | 2389 | 2.69M |
| 11 | 929.0 | 2389 | 2473 | 2473 | 845.4 | 0.0 | 0.0 | 2389 | 2.48M |
| 12 | 845.4 | 2389 | 2468 | 2468 | 766.8 | 0.0 | 0.0 | 2389 | 2.25M |
| 13 | 766.8 | 2389 | 2478 | 2478 | 677.7 | 0.0 | 0.0 | 2389 | 2.02M |
| 14 | 677.7 | 2389 | 2482 | 2482 | 584.8 | 0.0 | 0.0 | 2389 | 1.76M |
| 15 | 584.8 | 2389 | 2476 | 2476 | 498.1 | 0.0 | 0.0 | 2389 | 1.51M |
| 16 | 498.1 | 2389 | 2486 | 2486 | 401.4 | 0.0 | 0.0 | 2389 | 1.25M |
| 17 | 401.4 | 2389 | 2473 | 2473 | 317.8 | 0.0 | 0.0 | 2389 | 1.00M |
| 18 | 317.8 | 2389 | 2482 | 2482 | 225.0 | 0.0 | 0.0 | 2389 | 757138 |
| 19 | 225.0 | 2389 | 2474 | 2474 | 140.3 | 0.0 | 0.0 | 2389 | 509550 |
| 20 | 140.3 | 2389 | 2483 | 2483 | 47.1 | 0.0 | 0.0 | 2389 | 261501 |
| 21 | 47.1 | 2389 | 2474 | 2436 | 0.0 | 0.0 | 38.0 | 2389 | 1.73M |
| 22 | 0.0 | 2389 | 2472 | 2389 | 0.0 | 0.0 | 82.4 | 2389 | 3.60M |
| 23 | 0.0 | 2389 | 2482 | 2389 | 0.0 | 0.0 | 92.3 | 2389 | 4.04M |
| 24 | 0.0 | 2389 | 2475 | 2389 | 0.0 | 0.0 | 86.0 | 2389 | 3.76M |
| 25 | 0.0 | 2389 | 2488 | 2389 | 0.0 | 0.0 | 98.2 | 2389 | 4.30M |
| 26 | 0.0 | 2389 | 2485 | 2389 | 0.0 | 0.0 | 95.7 | 2389 | 4.19M |
| 27 | 0.0 | 2389 | 2467 | 2389 | 0.0 | 0.0 | 77.8 | 2389 | 3.40M |
| 28 | 0.0 | 2389 | 2487 | 2389 | 0.0 | 0.0 | 98.1 | 2389 | 4.29M |
| 29 | 0.0 | 2389 | 2470 | 2389 | 0.0 | 0.0 | 80.8 | 2389 | 3.54M |
| 30 | 0.0 | 2389 | 2475 | 2389 | 0.0 | 0.0 | 85.5 | 2389 | 3.74M |
| **Σ** | — | — | — | **73491** | — | **1786** | **834.9** | — | **116.54M** |

#### MAR — Política `P_+5` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2481 | 2481 | 1719 | 518.8 | 0.0 | 2509 | 12.48M |
| 2 | 1719 | 2509 | 2481 | 2481 | 1747 | 546.9 | 0.0 | 2509 | 13.70M |
| 3 | 1747 | 2509 | 2473 | 2473 | 1783 | 582.8 | 0.0 | 2509 | 14.37M |
| 4 | 1783 | 2509 | 2474 | 2474 | 1818 | 618.0 | 0.0 | 2509 | 15.04M |
| 5 | 1818 | 2509 | 2479 | 2479 | 1847 | 647.4 | 0.0 | 2509 | 15.61M |
| 6 | 1847 | 2509 | 2492 | 2492 | 1864 | 664.5 | 0.0 | 2509 | 15.95M |
| 7 | 1864 | 2509 | 2468 | 2468 | 1905 | 705.4 | 0.0 | 2509 | 16.69M |
| 8 | 1905 | 2509 | 2486 | 2486 | 1928 | 728.3 | 0.0 | 2509 | 17.15M |
| 9 | 1928 | 2509 | 2485 | 2485 | 1952 | 752.4 | 0.0 | 2509 | 17.61M |
| 10 | 1952 | 2509 | 2457 | 2457 | 2004 | 804.2 | 0.0 | 2509 | 18.56M |
| 11 | 2004 | 2509 | 2473 | 2473 | 2040 | 840.1 | 0.0 | 2509 | 19.26M |
| 12 | 2040 | 2509 | 2468 | 2468 | 2081 | 881.0 | 0.0 | 2509 | 20.03M |
| 13 | 2081 | 2509 | 2478 | 2478 | 2111 | 911.4 | 0.0 | 2509 | 20.62M |
| 14 | 2111 | 2509 | 2482 | 2482 | 2138 | 937.9 | 0.0 | 2509 | 21.13M |
| 15 | 2138 | 2509 | 2476 | 2476 | 2171 | 970.7 | 0.0 | 2509 | 21.75M |
| 16 | 2171 | 2509 | 2486 | 2486 | 2193 | 993.5 | 0.0 | 2509 | 22.19M |
| 17 | 2193 | 2509 | 2473 | 2473 | 2229 | 1029 | 0.0 | 2509 | 22.86M |
| 18 | 2229 | 2509 | 2482 | 2482 | 2256 | 1056 | 0.0 | 2509 | 23.37M |
| 19 | 2256 | 2509 | 2474 | 2474 | 2291 | 1091 | 0.0 | 2509 | 24.02M |
| 20 | 2291 | 2509 | 2483 | 2483 | 2317 | 1117 | 0.0 | 2509 | 24.54M |
| 21 | 2317 | 2509 | 2474 | 2474 | 2351 | 1151 | 0.0 | 2509 | 25.18M |
| 22 | 2351 | 2509 | 2472 | 2472 | 2388 | 1188 | 0.0 | 2509 | 25.88M |
| 23 | 2388 | 2509 | 2482 | 2482 | 2416 | 1216 | 0.0 | 2509 | 26.41M |
| 24 | 2416 | 2509 | 2475 | 2475 | 2449 | 1249 | 0.0 | 2509 | 27.04M |
| 25 | 2449 | 2509 | 2488 | 2488 | 2470 | 1270 | 0.0 | 2509 | 27.46M |
| 26 | 2470 | 2509 | 2485 | 2485 | 2494 | 1294 | 0.0 | 2509 | 27.90M |
| 27 | 2494 | 2509 | 2467 | 2467 | 2536 | 1336 | 0.0 | 2509 | 28.67M |
| 28 | 2536 | 2509 | 2487 | 2487 | 2557 | 1357 | 0.0 | 2509 | 29.10M |
| 29 | 2557 | 2509 | 2470 | 2470 | 2596 | 1396 | 0.0 | 2509 | 29.81M |
| 30 | 2596 | 2509 | 2475 | 2475 | 2630 | 1430 | 0.0 | 2509 | 30.47M |
| **Σ** | — | — | — | **74326** | — | **29283** | **0.0** | — | **654.86M** |

#### MAR — Política `P_+10` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2481 | 2481 | 1719 | 518.8 | 0.0 | 2628 | 12.48M |
| 2 | 1719 | 2628 | 2481 | 2481 | 1866 | 666.4 | 0.0 | 2628 | 15.80M |
| 3 | 1866 | 2628 | 2473 | 2473 | 2022 | 821.7 | 0.0 | 2628 | 18.75M |
| 4 | 2022 | 2628 | 2474 | 2474 | 2176 | 976.4 | 0.0 | 2628 | 21.69M |
| 5 | 2176 | 2628 | 2479 | 2479 | 2325 | 1125 | 0.0 | 2628 | 24.52M |
| 6 | 2325 | 2628 | 2492 | 2492 | 2462 | 1262 | 0.0 | 2628 | 27.13M |
| 7 | 2462 | 2628 | 2468 | 2468 | 2622 | 1422 | 0.0 | 2628 | 30.15M |
| 8 | 2622 | 2628 | 2486 | 2486 | 2765 | 1565 | 0.0 | 2628 | 32.88M |
| 9 | 2765 | 2628 | 2485 | 2485 | 2908 | 1708 | 0.0 | 2628 | 35.60M |
| 10 | 2908 | 2628 | 2457 | 2457 | 3079 | 1879 | 0.0 | 2628 | 38.82M |
| 11 | 3079 | 2628 | 2473 | 2473 | 3235 | 2035 | 0.0 | 2628 | 41.79M |
| 12 | 3235 | 2628 | 2468 | 2468 | 3395 | 2195 | 0.0 | 2628 | 44.83M |
| 13 | 3395 | 2628 | 2478 | 2478 | 3545 | 2345 | 0.0 | 2628 | 47.70M |
| 14 | 3545 | 2628 | 2482 | 2482 | 3691 | 2491 | 0.0 | 2628 | 50.47M |
| 15 | 3691 | 2628 | 2476 | 2476 | 3843 | 2643 | 0.0 | 2628 | 53.36M |
| 16 | 3843 | 2628 | 2486 | 2486 | 3985 | 2785 | 0.0 | 2628 | 56.08M |
| 17 | 3985 | 2628 | 2473 | 2473 | 4141 | 2941 | 0.0 | 2628 | 59.01M |
| 18 | 4141 | 2628 | 2482 | 2482 | 4287 | 3087 | 0.0 | 2628 | 61.80M |
| 19 | 4287 | 2628 | 2474 | 2474 | 4441 | 3241 | 0.0 | 2628 | 64.72M |
| 20 | 4441 | 2628 | 2483 | 2483 | 4587 | 3387 | 0.0 | 2628 | 67.50M |
| 21 | 4587 | 2628 | 2474 | 2474 | 4741 | 3541 | 0.0 | 2628 | 70.41M |
| 22 | 4741 | 2628 | 2472 | 2472 | 4897 | 3697 | 0.0 | 2628 | 73.38M |
| 23 | 4897 | 2628 | 2482 | 2482 | 5044 | 3844 | 0.0 | 2628 | 76.18M |
| 24 | 5044 | 2628 | 2475 | 2475 | 5197 | 3997 | 0.0 | 2628 | 79.08M |
| 25 | 5197 | 2628 | 2488 | 2488 | 5338 | 4138 | 0.0 | 2628 | 81.77M |
| 26 | 5338 | 2628 | 2485 | 2485 | 5481 | 4281 | 0.0 | 2628 | 84.49M |
| 27 | 5481 | 2628 | 2467 | 2467 | 5642 | 4442 | 0.0 | 2628 | 87.52M |
| 28 | 5642 | 2628 | 2487 | 2487 | 5783 | 4583 | 0.0 | 2628 | 90.23M |
| 29 | 5783 | 2628 | 2470 | 2470 | 5941 | 4741 | 0.0 | 2628 | 93.21M |
| 30 | 5941 | 2628 | 2475 | 2475 | 6094 | 4894 | 0.0 | 2628 | 96.13M |
| **Σ** | — | — | — | **74326** | — | **81252** | **0.0** | — | **1637.47M** |


---

## Anexo B — JUL: cenário médio dia-a-dia (1000 sims SDDP + 5 fixas ±10%, ±5%, 0%)

Idem ao Anexo A, mas para JULHO (alta variabilidade, CV de w_proc = 36%).

> **Nota metodológica (importante):**
> - **Para o SDDP**, esta tabela mostra uma **trajetória reconstruída a partir das médias** das 1000 simulações. Cada coluna (FilaIni, AdmIn, w_proc, Proc, FilaFim, AdmOut) é a média daquela variável no dia t entre as 1000 réplicas. **Spill e Ocioso são RECALCULADOS** pelas fórmulas (`Spill = max(0, FilaFim − 1 200)`, `Ocioso = max(0, w_proc − Proc)`) para que os números fechem linha a linha.
> - **Para as fixas P_-10..P_+10**, a trajetória já é determinística (w_proc fixo, adm_out=X constante), então os valores são exatos.
> - **Importante:** o **custo total Σ da linha SDDP nesta tabela** ≠ **custo médio real do SDDP** (Tabela 5.1/5.2). A diferença é o "custo da variabilidade estocástica" — Jensen.
>   - MAR SDDP: Σ tabela = R$ 51.8 M, real (§5.2) = R$ 52.0 M (diferença ~0%, baixa variância).
>   - JUL SDDP: Σ tabela = **R$ 149.9 M**, real (§5.2) = **R$ 204 M** (diferença ~R$ 54 M = custo da variabilidade alta da Weibull).

#### JUL — Política `SDDP` (média 1000 sims SDDP — Spill/Ocioso/Custo recalculados sobre médias)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2077 | 2077 | 2123 | 922.9 | 0.0 | 769.9 | 19.60M |
| 2 | 2123 | 769.9 | 2080 | 2034 | 859.2 | 0.0 | 46.9 | 1985 | 6.21M |
| 3 | 859.2 | 1985 | 2082 | 2040 | 803.9 | 0.0 | 41.7 | 2040 | 4.14M |
| 4 | 803.9 | 2040 | 2112 | 2061 | 783.2 | 0.0 | 51.2 | 2061 | 4.46M |
| 5 | 783.2 | 2061 | 2118 | 2059 | 785.0 | 0.0 | 58.8 | 2059 | 4.76M |
| 6 | 785.0 | 2059 | 2089 | 2036 | 807.7 | 0.0 | 52.2 | 2036 | 4.51M |
| 7 | 807.7 | 2036 | 2139 | 2079 | 765.2 | 0.0 | 59.8 | 2079 | 4.81M |
| 8 | 765.2 | 2079 | 2085 | 2038 | 806.5 | 0.0 | 47.3 | 2038 | 4.26M |
| 9 | 806.5 | 2038 | 2108 | 2053 | 790.8 | 0.0 | 54.3 | 2053 | 4.60M |
| 10 | 790.8 | 2053 | 2118 | 2059 | 785.3 | 0.0 | 59.0 | 2059 | 4.78M |
| 11 | 785.3 | 2059 | 2115 | 2056 | 787.5 | 0.0 | 58.9 | 2056 | 4.77M |
| 12 | 787.5 | 2056 | 2086 | 2037 | 806.9 | 0.0 | 49.4 | 2037 | 4.38M |
| 13 | 806.9 | 2037 | 2107 | 2051 | 792.9 | 0.0 | 55.7 | 2051 | 4.67M |
| 14 | 792.9 | 2051 | 2137 | 2081 | 762.5 | 0.0 | 55.5 | 2081 | 4.60M |
| 15 | 762.5 | 2081 | 2156 | 2096 | 747.5 | 0.0 | 59.6 | 2096 | 4.71M |
| 16 | 747.5 | 2096 | 2152 | 2094 | 750.4 | 0.0 | 57.9 | 2094 | 4.62M |
| 17 | 750.4 | 2094 | 2119 | 2063 | 781.2 | 0.0 | 56.1 | 2063 | 4.59M |
| 18 | 781.2 | 2063 | 2146 | 2089 | 755.2 | 0.0 | 56.7 | 2089 | 4.62M |
| 19 | 755.2 | 2089 | 2109 | 2052 | 792.3 | 0.0 | 57.0 | 2052 | 4.65M |
| 20 | 792.3 | 2052 | 2085 | 2041 | 803.3 | 0.0 | 44.6 | 2041 | 4.18M |
| 21 | 803.3 | 2041 | 2119 | 2060 | 784.4 | 0.0 | 59.0 | 2060 | 4.80M |
| 22 | 784.4 | 2060 | 2135 | 2078 | 766.4 | 0.0 | 57.9 | 2078 | 4.70M |
| 23 | 766.4 | 2078 | 2114 | 2060 | 783.9 | 0.0 | 53.6 | 2060 | 4.51M |
| 24 | 783.9 | 2060 | 2129 | 2068 | 775.9 | 0.0 | 60.6 | 2068 | 4.83M |
| 25 | 775.9 | 2068 | 2102 | 2048 | 796.0 | 0.0 | 53.7 | 2048 | 4.54M |
| 26 | 796.0 | 2048 | 2098 | 2047 | 796.6 | 0.0 | 50.6 | 2047 | 4.44M |
| 27 | 796.6 | 2047 | 2110 | 2050 | 794.2 | 0.0 | 60.6 | 2050 | 4.87M |
| 28 | 794.2 | 2050 | 2109 | 2054 | 789.8 | 0.0 | 54.6 | 2054 | 4.60M |
| 29 | 789.8 | 2054 | 2101 | 2046 | 797.8 | 0.0 | 54.5 | 2095 | 4.60M |
| 30 | 797.8 | 2095 | 2098 | 2056 | 836.6 | 0.0 | 41.4 | 0.0 | 4.09M |
| **Σ** | — | — | — | **61763** | — | **922.9** | **1569** | — | **153.90M** |

#### JUL — Política `P_-10` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2077 | 2077 | 2123 | 922.9 | 0.0 | 1789 | 19.60M |
| 2 | 2123 | 1789 | 2080 | 2080 | 1831 | 630.9 | 0.0 | 1789 | 15.74M |
| 3 | 1831 | 1789 | 2082 | 2082 | 1538 | 337.7 | 0.0 | 1789 | 10.17M |
| 4 | 1538 | 1789 | 2112 | 2112 | 1214 | 14.1 | 0.0 | 1789 | 4.07M |
| 5 | 1214 | 1789 | 2118 | 2118 | 884.8 | 0.0 | 0.0 | 1789 | 2.93M |
| 6 | 884.8 | 1789 | 2089 | 2089 | 584.7 | 0.0 | 0.0 | 1789 | 2.05M |
| 7 | 584.7 | 1789 | 2139 | 2139 | 234.6 | 0.0 | 0.0 | 1789 | 1.14M |
| 8 | 234.6 | 1789 | 2085 | 2023 | 0.0 | 0.0 | 61.7 | 1789 | 3.03M |
| 9 | 0.0 | 1789 | 2108 | 1789 | 0.0 | 0.0 | 319.0 | 1789 | 13.96M |
| 10 | 0.0 | 1789 | 2118 | 1789 | 0.0 | 0.0 | 329.2 | 1789 | 14.40M |
| 11 | 0.0 | 1789 | 2115 | 1789 | 0.0 | 0.0 | 326.9 | 1789 | 14.30M |
| 12 | 0.0 | 1789 | 2086 | 1789 | 0.0 | 0.0 | 298.0 | 1789 | 13.04M |
| 13 | 0.0 | 1789 | 2107 | 1789 | 0.0 | 0.0 | 318.3 | 1789 | 13.93M |
| 14 | 0.0 | 1789 | 2137 | 1789 | 0.0 | 0.0 | 348.5 | 1789 | 15.25M |
| 15 | 0.0 | 1789 | 2156 | 1789 | 0.0 | 0.0 | 367.5 | 1789 | 16.08M |
| 16 | 0.0 | 1789 | 2152 | 1789 | 0.0 | 0.0 | 363.0 | 1789 | 15.88M |
| 17 | 0.0 | 1789 | 2119 | 1789 | 0.0 | 0.0 | 330.4 | 1789 | 14.46M |
| 18 | 0.0 | 1789 | 2146 | 1789 | 0.0 | 0.0 | 357.0 | 1789 | 15.62M |
| 19 | 0.0 | 1789 | 2109 | 1789 | 0.0 | 0.0 | 320.1 | 1789 | 14.01M |
| 20 | 0.0 | 1789 | 2085 | 1789 | 0.0 | 0.0 | 296.8 | 1789 | 12.98M |
| 21 | 0.0 | 1789 | 2119 | 1789 | 0.0 | 0.0 | 330.1 | 1789 | 14.44M |
| 22 | 0.0 | 1789 | 2135 | 1789 | 0.0 | 0.0 | 347.0 | 1789 | 15.18M |
| 23 | 0.0 | 1789 | 2114 | 1789 | 0.0 | 0.0 | 325.1 | 1789 | 14.22M |
| 24 | 0.0 | 1789 | 2129 | 1789 | 0.0 | 0.0 | 340.2 | 1789 | 14.89M |
| 25 | 0.0 | 1789 | 2102 | 1789 | 0.0 | 0.0 | 313.2 | 1789 | 13.70M |
| 26 | 0.0 | 1789 | 2098 | 1789 | 0.0 | 0.0 | 309.5 | 1789 | 13.54M |
| 27 | 0.0 | 1789 | 2110 | 1789 | 0.0 | 0.0 | 321.9 | 1789 | 14.08M |
| 28 | 0.0 | 1789 | 2109 | 1789 | 0.0 | 0.0 | 320.3 | 1789 | 14.01M |
| 29 | 0.0 | 1789 | 2101 | 1789 | 0.0 | 0.0 | 312.2 | 1789 | 13.66M |
| 30 | 0.0 | 1789 | 2098 | 1789 | 0.0 | 0.0 | 309.3 | 1789 | 13.53M |
| **Σ** | — | — | — | **56067** | — | **1906** | **7265** | — | **373.91M** |

#### JUL — Política `P_-5` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2077 | 2077 | 2123 | 922.9 | 0.0 | 1888 | 19.60M |
| 2 | 2123 | 1888 | 2080 | 2080 | 1930 | 730.3 | 0.0 | 1888 | 17.49M |
| 3 | 1930 | 1888 | 2082 | 2082 | 1736 | 536.4 | 0.0 | 1888 | 13.81M |
| 4 | 1736 | 1888 | 2112 | 2112 | 1512 | 312.2 | 0.0 | 1888 | 9.59M |
| 5 | 1512 | 1888 | 2118 | 2118 | 1282 | 82.2 | 0.0 | 1888 | 5.23M |
| 6 | 1282 | 1888 | 2089 | 2089 | 1082 | 0.0 | 0.0 | 1888 | 3.30M |
| 7 | 1082 | 1888 | 2139 | 2139 | 830.8 | 0.0 | 0.0 | 1888 | 2.67M |
| 8 | 830.8 | 1888 | 2085 | 2085 | 633.9 | 0.0 | 0.0 | 1888 | 2.04M |
| 9 | 633.9 | 1888 | 2108 | 2108 | 414.2 | 0.0 | 0.0 | 1888 | 1.46M |
| 10 | 414.2 | 1888 | 2118 | 2118 | 184.3 | 0.0 | 0.0 | 1888 | 834968 |
| 11 | 184.3 | 1888 | 2115 | 2072 | 0.0 | 0.0 | 43.2 | 1888 | 2.15M |
| 12 | 0.0 | 1888 | 2086 | 1888 | 0.0 | 0.0 | 198.6 | 1888 | 8.69M |
| 13 | 0.0 | 1888 | 2107 | 1888 | 0.0 | 0.0 | 218.9 | 1888 | 9.58M |
| 14 | 0.0 | 1888 | 2137 | 1888 | 0.0 | 0.0 | 249.1 | 1888 | 10.90M |
| 15 | 0.0 | 1888 | 2156 | 1888 | 0.0 | 0.0 | 268.2 | 1888 | 11.73M |
| 16 | 0.0 | 1888 | 2152 | 1888 | 0.0 | 0.0 | 263.7 | 1888 | 11.54M |
| 17 | 0.0 | 1888 | 2119 | 1888 | 0.0 | 0.0 | 231.0 | 1888 | 10.11M |
| 18 | 0.0 | 1888 | 2146 | 1888 | 0.0 | 0.0 | 257.7 | 1888 | 11.27M |
| 19 | 0.0 | 1888 | 2109 | 1888 | 0.0 | 0.0 | 220.8 | 1888 | 9.66M |
| 20 | 0.0 | 1888 | 2085 | 1888 | 0.0 | 0.0 | 197.4 | 1888 | 8.64M |
| 21 | 0.0 | 1888 | 2119 | 1888 | 0.0 | 0.0 | 230.8 | 1888 | 10.10M |
| 22 | 0.0 | 1888 | 2135 | 1888 | 0.0 | 0.0 | 247.6 | 1888 | 10.83M |
| 23 | 0.0 | 1888 | 2114 | 1888 | 0.0 | 0.0 | 225.8 | 1888 | 9.88M |
| 24 | 0.0 | 1888 | 2129 | 1888 | 0.0 | 0.0 | 240.9 | 1888 | 10.54M |
| 25 | 0.0 | 1888 | 2102 | 1888 | 0.0 | 0.0 | 213.8 | 1888 | 9.35M |
| 26 | 0.0 | 1888 | 2098 | 1888 | 0.0 | 0.0 | 210.2 | 1888 | 9.20M |
| 27 | 0.0 | 1888 | 2110 | 1888 | 0.0 | 0.0 | 222.5 | 1888 | 9.74M |
| 28 | 0.0 | 1888 | 2109 | 1888 | 0.0 | 0.0 | 221.0 | 1888 | 9.67M |
| 29 | 0.0 | 1888 | 2101 | 1888 | 0.0 | 0.0 | 212.9 | 1888 | 9.31M |
| 30 | 0.0 | 1888 | 2098 | 1888 | 0.0 | 0.0 | 210.0 | 1888 | 9.19M |
| **Σ** | — | — | — | **58948** | — | **2584** | **4384** | — | **268.09M** |

#### JUL — Política `P_0` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2077 | 2077 | 2123 | 922.9 | 0.0 | 1987 | 19.60M |
| 2 | 2123 | 1987 | 2080 | 2080 | 2030 | 829.7 | 0.0 | 1987 | 19.24M |
| 3 | 2030 | 1987 | 2082 | 2082 | 1935 | 735.1 | 0.0 | 1987 | 17.45M |
| 4 | 1935 | 1987 | 2112 | 2112 | 1810 | 610.3 | 0.0 | 1987 | 15.12M |
| 5 | 1810 | 1987 | 2118 | 2118 | 1680 | 479.7 | 0.0 | 1987 | 12.64M |
| 6 | 1680 | 1987 | 2089 | 2089 | 1578 | 378.3 | 0.0 | 1987 | 10.68M |
| 7 | 1578 | 1987 | 2139 | 2139 | 1427 | 227.0 | 0.0 | 1987 | 7.87M |
| 8 | 1427 | 1987 | 2085 | 2085 | 1329 | 129.4 | 0.0 | 1987 | 5.94M |
| 9 | 1329 | 1987 | 2108 | 2108 | 1209 | 9.1 | 0.0 | 1987 | 3.69M |
| 10 | 1209 | 1987 | 2118 | 2118 | 1079 | 0.0 | 0.0 | 1987 | 3.19M |
| 11 | 1079 | 1987 | 2115 | 2115 | 950.4 | 0.0 | 0.0 | 1987 | 2.83M |
| 12 | 950.4 | 1987 | 2086 | 2086 | 851.1 | 0.0 | 0.0 | 1987 | 2.51M |
| 13 | 851.1 | 1987 | 2107 | 2107 | 731.6 | 0.0 | 0.0 | 1987 | 2.21M |
| 14 | 731.6 | 1987 | 2137 | 2137 | 581.8 | 0.0 | 0.0 | 1987 | 1.83M |
| 15 | 581.8 | 1987 | 2156 | 2156 | 413.0 | 0.0 | 0.0 | 1987 | 1.39M |
| 16 | 413.0 | 1987 | 2152 | 2152 | 248.7 | 0.0 | 0.0 | 1987 | 923090 |
| 17 | 248.7 | 1987 | 2119 | 2119 | 117.0 | 0.0 | 0.0 | 1987 | 510233 |
| 18 | 117.0 | 1987 | 2146 | 2104 | 0.0 | 0.0 | 41.2 | 1987 | 1.97M |
| 19 | 0.0 | 1987 | 2109 | 1987 | 0.0 | 0.0 | 121.4 | 1987 | 5.31M |
| 20 | 0.0 | 1987 | 2085 | 1987 | 0.0 | 0.0 | 98.0 | 1987 | 4.29M |
| 21 | 0.0 | 1987 | 2119 | 1987 | 0.0 | 0.0 | 131.4 | 1987 | 5.75M |
| 22 | 0.0 | 1987 | 2135 | 1987 | 0.0 | 0.0 | 148.3 | 1987 | 6.49M |
| 23 | 0.0 | 1987 | 2114 | 1987 | 0.0 | 0.0 | 126.4 | 1987 | 5.53M |
| 24 | 0.0 | 1987 | 2129 | 1987 | 0.0 | 0.0 | 141.5 | 1987 | 6.19M |
| 25 | 0.0 | 1987 | 2102 | 1987 | 0.0 | 0.0 | 114.4 | 1987 | 5.01M |
| 26 | 0.0 | 1987 | 2098 | 1987 | 0.0 | 0.0 | 110.8 | 1987 | 4.85M |
| 27 | 0.0 | 1987 | 2110 | 1987 | 0.0 | 0.0 | 123.2 | 1987 | 5.39M |
| 28 | 0.0 | 1987 | 2109 | 1987 | 0.0 | 0.0 | 121.6 | 1987 | 5.32M |
| 29 | 0.0 | 1987 | 2101 | 1987 | 0.0 | 0.0 | 113.5 | 1987 | 4.97M |
| 30 | 0.0 | 1987 | 2098 | 1987 | 0.0 | 0.0 | 110.6 | 1987 | 4.84M |
| **Σ** | — | — | — | **61829** | — | **4321** | **1502** | — | **193.52M** |

#### JUL — Política `P_+5` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2077 | 2077 | 2123 | 922.9 | 0.0 | 2087 | 19.60M |
| 2 | 2123 | 2087 | 2080 | 2080 | 2129 | 929.0 | 0.0 | 2087 | 20.99M |
| 3 | 2129 | 2087 | 2082 | 2082 | 2134 | 933.8 | 0.0 | 2087 | 21.09M |
| 4 | 2134 | 2087 | 2112 | 2112 | 2108 | 908.4 | 0.0 | 2087 | 20.64M |
| 5 | 2108 | 2087 | 2118 | 2118 | 2077 | 877.1 | 0.0 | 2087 | 20.06M |
| 6 | 2077 | 2087 | 2089 | 2089 | 2075 | 875.1 | 0.0 | 2087 | 19.98M |
| 7 | 2075 | 2087 | 2139 | 2139 | 2023 | 823.1 | 0.0 | 2087 | 19.06M |
| 8 | 2023 | 2087 | 2085 | 2085 | 2025 | 824.9 | 0.0 | 2087 | 19.02M |
| 9 | 2025 | 2087 | 2108 | 2108 | 2004 | 804.0 | 0.0 | 2087 | 18.65M |
| 10 | 2004 | 2087 | 2118 | 2118 | 1973 | 772.8 | 0.0 | 2087 | 18.08M |
| 11 | 1973 | 2087 | 2115 | 2115 | 1944 | 744.0 | 0.0 | 2087 | 17.53M |
| 12 | 1944 | 2087 | 2086 | 2086 | 1944 | 744.1 | 0.0 | 2087 | 17.49M |
| 13 | 1944 | 2087 | 2107 | 2107 | 1924 | 723.9 | 0.0 | 2087 | 17.13M |
| 14 | 1924 | 2087 | 2137 | 2137 | 1873 | 673.5 | 0.0 | 2087 | 16.22M |
| 15 | 1873 | 2087 | 2156 | 2156 | 1804 | 604.1 | 0.0 | 2087 | 14.92M |
| 16 | 1804 | 2087 | 2152 | 2152 | 1739 | 539.1 | 0.0 | 2087 | 13.68M |
| 17 | 1739 | 2087 | 2119 | 2119 | 1707 | 506.8 | 0.0 | 2087 | 13.02M |
| 18 | 1707 | 2087 | 2146 | 2146 | 1648 | 447.9 | 0.0 | 2087 | 11.94M |
| 19 | 1648 | 2087 | 2109 | 2109 | 1626 | 425.8 | 0.0 | 2087 | 11.47M |
| 20 | 1626 | 2087 | 2085 | 2085 | 1627 | 427.2 | 0.0 | 2087 | 11.46M |
| 21 | 1627 | 2087 | 2119 | 2119 | 1595 | 395.1 | 0.0 | 2087 | 10.90M |
| 22 | 1595 | 2087 | 2135 | 2135 | 1546 | 346.2 | 0.0 | 2087 | 10.00M |
| 23 | 1546 | 2087 | 2114 | 2114 | 1519 | 319.2 | 0.0 | 2087 | 9.45M |
| 24 | 1519 | 2087 | 2129 | 2129 | 1477 | 277.1 | 0.0 | 2087 | 8.67M |
| 25 | 1477 | 2087 | 2102 | 2102 | 1462 | 262.0 | 0.0 | 2087 | 8.35M |
| 26 | 1462 | 2087 | 2098 | 2098 | 1451 | 250.5 | 0.0 | 2087 | 8.12M |
| 27 | 1451 | 2087 | 2110 | 2110 | 1427 | 226.7 | 0.0 | 2087 | 7.69M |
| 28 | 1427 | 2087 | 2109 | 2109 | 1404 | 204.5 | 0.0 | 2087 | 7.26M |
| 29 | 1404 | 2087 | 2101 | 2101 | 1390 | 190.3 | 0.0 | 2087 | 6.98M |
| 30 | 1390 | 2087 | 2098 | 2098 | 1379 | 179.1 | 0.0 | 2087 | 6.77M |
| **Σ** | — | — | — | **63332** | — | **17159** | **0.0** | — | **426.22M** |

#### JUL — Política `P_+10` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2077 | 2077 | 2123 | 922.9 | 0.0 | 2186 | 19.60M |
| 2 | 2123 | 2186 | 2080 | 2080 | 2228 | 1028 | 0.0 | 2186 | 22.74M |
| 3 | 2228 | 2186 | 2082 | 2082 | 2333 | 1133 | 0.0 | 2186 | 24.72M |
| 4 | 2333 | 2186 | 2112 | 2112 | 2406 | 1206 | 0.0 | 2186 | 26.17M |
| 5 | 2406 | 2186 | 2118 | 2118 | 2475 | 1275 | 0.0 | 2186 | 27.47M |
| 6 | 2475 | 2186 | 2089 | 2089 | 2572 | 1372 | 0.0 | 2186 | 29.28M |
| 7 | 2572 | 2186 | 2139 | 2139 | 2619 | 1419 | 0.0 | 2186 | 30.25M |
| 8 | 2619 | 2186 | 2085 | 2085 | 2720 | 1520 | 0.0 | 2186 | 32.10M |
| 9 | 2720 | 2186 | 2108 | 2108 | 2799 | 1599 | 0.0 | 2186 | 33.62M |
| 10 | 2799 | 2186 | 2118 | 2118 | 2867 | 1667 | 0.0 | 2186 | 34.93M |
| 11 | 2867 | 2186 | 2115 | 2115 | 2938 | 1738 | 0.0 | 2186 | 36.27M |
| 12 | 2938 | 2186 | 2086 | 2086 | 3037 | 1837 | 0.0 | 2186 | 38.12M |
| 13 | 3037 | 2186 | 2107 | 2107 | 3116 | 1916 | 0.0 | 2186 | 39.65M |
| 14 | 3116 | 2186 | 2137 | 2137 | 3165 | 1965 | 0.0 | 2186 | 40.62M |
| 15 | 3165 | 2186 | 2156 | 2156 | 3195 | 1995 | 0.0 | 2186 | 41.22M |
| 16 | 3195 | 2186 | 2152 | 2152 | 3230 | 2030 | 0.0 | 2186 | 41.86M |
| 17 | 3230 | 2186 | 2119 | 2119 | 3297 | 2097 | 0.0 | 2186 | 43.09M |
| 18 | 3297 | 2186 | 2146 | 2146 | 3337 | 2137 | 0.0 | 2186 | 43.90M |
| 19 | 3337 | 2186 | 2109 | 2109 | 3414 | 2214 | 0.0 | 2186 | 45.31M |
| 20 | 3414 | 2186 | 2085 | 2085 | 3515 | 2315 | 0.0 | 2186 | 47.20M |
| 21 | 3515 | 2186 | 2119 | 2119 | 3582 | 2382 | 0.0 | 2186 | 48.52M |
| 22 | 3582 | 2186 | 2135 | 2135 | 3633 | 2433 | 0.0 | 2186 | 49.50M |
| 23 | 3633 | 2186 | 2114 | 2114 | 3705 | 2505 | 0.0 | 2186 | 50.85M |
| 24 | 3705 | 2186 | 2129 | 2129 | 3762 | 2562 | 0.0 | 2186 | 51.96M |
| 25 | 3762 | 2186 | 2102 | 2102 | 3847 | 2647 | 0.0 | 2186 | 53.52M |
| 26 | 3847 | 2186 | 2098 | 2098 | 3935 | 2735 | 0.0 | 2186 | 55.18M |
| 27 | 3935 | 2186 | 2110 | 2110 | 4010 | 2810 | 0.0 | 2186 | 56.64M |
| 28 | 4010 | 2186 | 2109 | 2109 | 4087 | 2887 | 0.0 | 2186 | 58.10M |
| 29 | 4087 | 2186 | 2101 | 2101 | 4172 | 2972 | 0.0 | 2186 | 59.71M |
| 30 | 4172 | 2186 | 2098 | 2098 | 4261 | 3061 | 0.0 | 2186 | 61.38M |
| **Σ** | — | — | — | **63332** | — | **60381** | **0.0** | — | **1243.46M** |


---

## Anexo C — MAR: uma réplica qualquer do SDDP (idx=42)

Trajetória individual do SDDP em MAR (uma das 1000 réplicas, índice arbitrário 42). **Números coerentes linha a linha**: `Spill = max(0, FilaFim − 1 200)` bate exato.

> Use isto para "sentir" como é uma execução real do SDDP em março. Para a média entre 1000 sims, ver Anexo A.

#### MAR — SDDP, réplica qualquer (idx=42, trajetória individual)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2459 | 2459 | 1741 | 541.0 | 0.0 | 1116 | 12.87M |
| 2 | 1741 | 1116 | 2209 | 2209 | 648.0 | 0.0 | -0.0 | 2209 | 3.33M |
| 3 | 648.0 | 2209 | 2561 | 2561 | 296.0 | 0.0 | 0.0 | 2561 | 1.32M |
| 4 | 296.0 | 2561 | 2368 | 2368 | 489.0 | 0.0 | -0.0 | 2368 | 1.10M |
| 5 | 489.0 | 2368 | 2573 | 2573 | 284.0 | 0.0 | 0.0 | 2573 | 1.08M |
| 6 | 284.0 | 2573 | 2675 | 2675 | 182.0 | 0.0 | -0.0 | 2675 | 650070 |
| 7 | 182.0 | 2675 | 2550 | 2550 | 307.0 | 0.0 | 0.0 | 2550 | 682155 |
| 8 | 307.0 | 2550 | 2323 | 2323 | 534.0 | 0.0 | 0.0 | 2323 | 1.17M |
| 9 | 534.0 | 2323 | 2527 | 2527 | 330.0 | 0.0 | 0.0 | 2527 | 1.21M |
| 10 | 330.0 | 2527 | 2743 | 2743 | 114.0 | 0.0 | -0.0 | 2743 | 619380 |
| 11 | 114.0 | 2743 | 2709 | 2709 | 148.0 | 0.0 | -0.0 | 2709 | 365490 |
| 12 | 148.0 | 2709 | 2425 | 2425 | 432.0 | 0.0 | 0.0 | 2425 | 809100 |
| 13 | 432.0 | 2425 | 2277 | 2277 | 580.0 | 0.0 | 0.0 | 2277 | 1.41M |
| 14 | 580.0 | 2277 | 2311 | 2311 | 546.0 | 0.0 | -0.0 | 2311 | 1.57M |
| 15 | 546.0 | 2311 | 2596 | 2596 | 261.0 | 0.0 | -0.0 | 2596 | 1.13M |
| 16 | 261.0 | 2596 | 2516 | 2516 | 341.0 | 0.0 | 0.0 | 2516 | 839790 |
| 17 | 341.0 | 2516 | 2573 | 2573 | 284.0 | 0.0 | 0.0 | 2573 | 871875 |
| 18 | 284.0 | 2573 | 2243 | 2243 | 614.0 | 0.0 | 0.0 | 2243 | 1.25M |
| 19 | 614.0 | 2243 | 2368 | 2368 | 489.0 | 0.0 | 0.0 | 2368 | 1.54M |
| 20 | 489.0 | 2368 | 2482 | 2482 | 375.0 | 0.0 | -0.0 | 2482 | 1.21M |
| 21 | 375.0 | 2482 | 2743 | 2743 | 114.0 | 0.0 | 0.0 | 2743 | 682155 |
| 22 | 114.0 | 2743 | 2152 | 2152 | 705.0 | 0.0 | 0.0 | 2152 | 1.14M |
| 23 | 705.0 | 2152 | 2505 | 2505 | 352.0 | 0.0 | -0.0 | 2505 | 1.47M |
| 24 | 352.0 | 2505 | 2129 | 2129 | 728.0 | 0.0 | 0.0 | 2129 | 1.51M |
| 25 | 728.0 | 2129 | 2732 | 2732 | 125.0 | 0.0 | -0.0 | 2732 | 1.19M |
| 26 | 125.0 | 2732 | 2732 | 2732 | 125.0 | 0.0 | 0.0 | 2732 | 348750 |
| 27 | 125.0 | 2732 | 2357 | 2357 | 500.0 | 0.0 | -0.0 | 2357 | 871875 |
| 28 | 500.0 | 2357 | 2266 | 2266 | 591.0 | 0.0 | -0.0 | 2266 | 1.52M |
| 29 | 591.0 | 2266 | 2527 | 2527 | 330.0 | 0.0 | 0.0 | 2595 | 1.28M |
| 30 | 330.0 | 2595 | 2243 | 2243 | 682.0 | 0.0 | 0.0 | 0.0 | 1.41M |
| **Σ** | — | — | — | **73874** | — | **541.0** | **0.0** | — | **46.45M** |


---

## Anexo D — JUL: uma réplica qualquer do SDDP (idx=42)

Trajetória individual do SDDP em JUL. **Números coerentes linha a linha**. Observe a alta variabilidade de `w_proc` (varia de ~1 050 a ~3 250 entre dias) — característica do mês de julho (Weibull com CV=36%).

#### JUL — SDDP, réplica qualquer (idx=42, trajetória individual)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2893 | 2893 | 1307 | 107.0 | 0.0 | 1537 | 5.23M |
| 2 | 1307 | 1537 | 2663 | 2663 | 181.0 | 0.0 | 0.0 | 2663 | 2.08M |
| 3 | 181.0 | 2663 | 2729 | 2729 | 115.0 | 0.0 | -0.0 | 2729 | 412920 |
| 4 | 115.0 | 2729 | 1020 | 1020 | 1824 | 624.0 | 0.0 | 1020 | 12.82M |
| 5 | 1824 | 1020 | 1677 | 1677 | 1167 | 0.0 | 0.0 | 1677 | 4.17M |
| 6 | 1167 | 1677 | 1480 | 1480 | 1364 | 164.0 | -0.0 | 1480 | 6.19M |
| 7 | 1364 | 1480 | 1776 | 1776 | 1068 | 0.0 | 0.0 | 1776 | 3.39M |
| 8 | 1068 | 1776 | 1776 | 1776 | 1068 | 0.0 | -0.0 | 1776 | 2.98M |
| 9 | 1068 | 1776 | 1250 | 1250 | 1594 | 394.0 | 0.0 | 1250 | 10.10M |
| 10 | 1594 | 1250 | 1184 | 1184 | 1660 | 460.0 | 0.0 | 1184 | 12.00M |
| 11 | 1660 | 1184 | 1414 | 1414 | 1430 | 230.0 | 0.0 | 1414 | 8.04M |
| 12 | 1430 | 1414 | 2630 | 2630 | 214.0 | 0.0 | 0.0 | 2630 | 2.29M |
| 13 | 214.0 | 2630 | 3386 | 2844 | -0.0 | 0.0 | 542.0 | 2844 | 24.01M |
| 14 | -0.0 | 2844 | 2696 | 2696 | 148.0 | 0.0 | -0.0 | 2696 | 206460 |
| 15 | 148.0 | 2696 | 691.0 | 691.0 | 2153 | 953.0 | 0.0 | 691.0 | 18.66M |
| 16 | 2153 | 691.0 | 1710 | 1710 | 1134 | 0.0 | 0.0 | 1710 | 4.59M |
| 17 | 1134 | 1710 | 1973 | 1973 | 871.0 | 0.0 | 0.0 | 1973 | 2.80M |
| 18 | 871.0 | 1973 | 1612 | 1612 | 1232 | 32.0 | 0.0 | 1612 | 3.45M |
| 19 | 1232 | 1612 | 1316 | 1316 | 1528 | 328.0 | 0.0 | 1316 | 9.17M |
| 20 | 1528 | 1316 | 1414 | 1414 | 1430 | 230.0 | -0.0 | 1414 | 7.85M |
| 21 | 1430 | 1414 | 1086 | 1086 | 1758 | 558.0 | -0.0 | 1086 | 13.49M |
| 22 | 1758 | 1086 | 1842 | 1842 | 1002 | 0.0 | 0.0 | 1842 | 3.85M |
| 23 | 1002 | 1842 | 3156 | 2844 | -0.0 | 0.0 | 312.0 | 2844 | 15.05M |
| 24 | -0.0 | 2844 | 1776 | 1776 | 1068 | 0.0 | -0.0 | 1776 | 1.49M |
| 25 | 1068 | 1776 | 2762 | 2762 | 82.0 | 0.0 | 0.0 | 2762 | 1.60M |
| 26 | 82.0 | 2762 | 2203 | 2203 | 641.0 | 0.0 | -0.0 | 2203 | 1.01M |
| 27 | 641.0 | 2203 | 3058 | 2844 | 0.0 | 0.0 | 214.0 | 2844 | 10.26M |
| 28 | 0.0 | 2844 | 1875 | 1875 | 969.0 | 0.0 | 0.0 | 1875 | 1.35M |
| 29 | 969.0 | 1875 | 1710 | 1710 | 1134 | 0.0 | 0.0 | 1759 | 2.93M |
| 30 | 1134 | 1759 | 2400 | 2400 | 493.0 | 0.0 | -0.0 | 0.0 | 2.27M |
| **Σ** | — | — | — | **58090** | — | **4080** | **1068** | — | **193.75M** |


---

## Anexo E — Validações e reprodutibilidade

- **V1 (vs v7):** SDDP mar do v8 (R$ 52.0 M) compatível com v7 a menos de ±5%.
- **V2 (não-monotonicidade fixas):** com a nova regra, o ótimo entre fixas é interno (P_0 em ambos os meses) — padrão em U.
- **V3 (determinismo das fixas):** rodar `julia model_v8.jl` duas vezes → custos das fixas são bit-idênticos (IC=0).
- **V4 (bound SDDP):** bound calculado por `SDDP.calculate_bound(model)` ≤ custo médio simulado.

**Sistema:** Windows 11, Julia 1.12.4, Python 3.11.9.

**Como rodar do zero:**

```
cd "Projeto - IC - Rodoviário"
julia "Model SDDP - 19-05-26/model_v8.jl"     # ~2.5 min
python "Model SDDP - 19-05-26/plot_v8.py"     # ~10 s
```

---
