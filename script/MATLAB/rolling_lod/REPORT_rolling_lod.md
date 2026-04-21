# LOD Mobile (Rolling LOD) — Report di sviluppo
**Progetto:** ELLONA — Electronic Nose per monitoraggio odori  
**Data:** 21 Aprile 2026  
**Autore:** Marco Calì — PoliMi

---

## 1. Motivazione

Il sistema ELLONA utilizza un modello PCA fisso addestrato sull'intero dataset (9 mesi, marzo–dicembre 2025). Il LOD (Limit of Detection) è definito come:

$$\text{LOD}^\pm = \mu_{BL} \pm k \cdot \sigma_{BL}$$

dove μ e σ sono calcolati una volta sola sul baseline globale (campioni nella banda IQR [P25, P75] dei quattro sensori MOX). Con k=3 e baseline *weekly*:

- LOD = [−3.988, +3.988]
- Tasso eventi (PC1 < LOD⁻): **3.67%**

**Problema identificato:** un LOD fisso non compensa eventuali derive lente del baseline nel tempo (stagionalità termica, invecchiamento sensori). Se il baseline reale deriva di +Δ, la soglia rimane ferma → sensitivity asimmetrica nel tempo.

---

## 2. Prima implementazione: LOD rolling con σ locale (versione errata)

### 2.1 Idea iniziale

Per ogni istante t, ricalcolare sia μ(t) che σ(t) su una finestra causale degli ultimi 7 giorni:

$$\text{LOD}(t) = \mu_{roll}(t) \pm k \cdot \sigma_{roll}(t)$$

### 2.2 Risultato

| Metrica | LOD fisso | LOD rolling σ_locale |
|---|---|---|
| % eventi | 3.67% | **23.04%** ❌ |
| σ medio | 1.3292 | 0.4431 |

### 2.3 Diagnosi del problema

σ_roll (0.44) è circa 3× più piccolo di σ_global (1.33) → la banda LOD è 3× più stretta → quasi tutto viene classificato come evento.

La causa è strutturale, non un bug: σ_roll su 7 giorni cattura solo il **rumore di breve termine** del sensore, mentre σ_global include anche la **variabilità stagionale multi-mese**.

---

## 3. Analisi della struttura di σ: finestre 7d, 14d, 30d

Per capire perché σ_roll è così piccolo, sono state testate tre finestre diverse.

### 3.1 Risultati

| Finestra | σ_roll medio | % di σ_global | % eventi |
|---|---|---|---|
| 7 giorni | 0.4431 | 33% | 3.36% |
| 14 giorni | 0.4759 | 36% | 3.24% |
| 30 giorni | 0.5416 | 41% | 3.33% |
| **globale (9 mesi)** | **1.3292** | **100%** | **3.67%** |

σ_roll cresce lentamente con la finestra ma **non converge a σ_global** nemmeno a 30 giorni. A 30 giorni si raggiunge solo il 41% del valore globale.

### 3.2 Interpretazione

Il sensore ha due tipi di variabilità sovrapposti:

1. **Rumore di breve termine** — fluttuazioni giornaliere casuali del sensore. Presente dentro ogni finestra settimanale. σ ≈ 0.44.

2. **Deriva stagionale** — il baseline di marzo è sistematicamente diverso da quello di agosto (temperatura ambiente, umidità, composizione dell'aria di fondo). Visibile solo su scale di mesi.

Dentro una finestra di 7 (o 14 o 30) giorni, la componente stagionale appare come un **offset costante** — viene assorbita da μ_roll e non entra in σ_roll. Per questo σ_roll rimane piccolo indipendentemente dalla finestra scelta.

La decomposizione della varianza è:

$$\sigma^2_{global} = \underbrace{\sigma^2_{noise}}_{\approx 0.44^2 = 0.19} + \underbrace{\sigma^2_{stagionale}}_{\approx 1.33^2 - 0.19 = 1.58}$$

La componente stagionale vale 1.58, quella di rumore 0.19: **l'89% di σ_global proviene dalla stagionalità**, non dal rumore strumentale.

### 3.3 Implicazione per la soglia LOD

Usare σ_roll per la banda LOD significa dire:

> *"è un evento tutto ciò che esce dalla variabilità di questa settimana"*

Ma la variabilità settimanale non rappresenta il funzionamento normale del sensore sull'intero anno operativo. D'inverno il baseline è sistematicamente più alto, d'estate più basso — quella differenza **non è un evento**, è stagionalità normale. Con σ_roll ristretto verrebbe classificata come evento lo stesso.

Usare σ_global significa dire:

> *"è un evento tutto ciò che esce dalla variabilità dell'intero anno di operatività normale"*

La soglia è calibrata su tutta la gamma di condizioni già osservate → robusta in ogni stagione.

---

## 4. Soluzione finale: LOD rolling con σ globale (Opzione B)

### 4.1 Formulazione

$$\boxed{\text{LOD}(t) = \mu_{roll}(t) \pm k \cdot \sigma_{global}}$$

- **μ_roll(t)**: si adatta lentamente alla deriva del baseline (deriva stagionale, invecchiamento sensore)
- **σ_global**: mantiene la larghezza della banda calibrata sull'intera stagionalità

Questo è esattamente il principio dei grafici **Moving Average in Statistical Process Control (SPC)**: il centro si aggiorna, i limiti di controllo no.

### 4.2 Implementazione

In `ellona_rolling_lod.m`:

```matlab
% Opzione B: solo μ è rolling, σ rimane globale
lod_lo_grid = mu_grid - k * sigma_global;
lod_hi_grid = mu_grid + k * sigma_global;
```

Parametri:
- Finestra μ_roll: **7 giorni** (causal window)
- Step griglia: 1 giorno
- Selezione baseline: IQR [P25, P75] su tutti e 4 i MOX
- Cold start (primi 7 giorni): fallback al LOD globale
- Gap filling: `fillmissing(..., 'previous')` poi `'next'`

### 4.3 Risultati finali

| Metrica | LOD fisso | LOD rolling (σ_global) |
|---|---|---|
| % eventi | 3.67% | **3.36%** |
| LOD⁻ medio | −3.988 | −4.046 |
| μ_BL medio | 0.000 | −0.058 |
| Concordanza | — | **98.5%** |
| Solo LOD fisso | — | 0.90% |
| Solo LOD rolling | — | 0.59% |

La concordanza del 98.5% conferma che i due approcci sono quasi equivalenti su questo dataset di 9 mesi. La differenza residua ha due interpretazioni fisiche:

- **0.90% solo nel fisso**: periodi in cui μ_roll è salito (baseline in deriva positiva) → LOD⁻_roll si alza → eventi borderline non catturati. Il rolling è più conservativo → corretto.
- **0.59% solo nel rolling**: periodi in cui μ_roll era sotto zero → LOD⁻_roll scende → eventi borderline catturati che il fisso perdeva. Questi sono il vero guadagno del rolling.

---

## 5. Analisi di sensibilità al parametro k

La differenza tra LOD fisso e rolling dipende dal rapporto tra la deriva di μ_roll e la larghezza della banda:

$$\text{impatto rolling} \propto \frac{|\mu_{roll}(t) - \mu_{fisso}|}{k \cdot \sigma_{global}}$$

Con deriva tipica ~0.5 e σ_global = 1.33:

| k | Metà banda | Deriva/Banda | Discordanza stimata |
|---|---|---|---|
| 3.0 | 3.99 | 12% | ~1.5% (misurato) |
| 2.0 | 2.66 | 19% | ~4–5% |
| 1.5 | 2.00 | 25% | ~8–10% |
| 1.0 | 1.33 | 38% | ~15–20% |

Il rolling LOD diventa rilevante per **k ≤ 1.5–2.0**. A k=3 il LOD fisso è già solido.

---

## 6. Conclusioni

**σ deve essere globale.** Non è un compromesso pratico, è l'unica scelta fisicamente corretta:

- σ_roll su qualsiasi finestra ≤ 30 giorni cattura solo il rumore strumentale di breve termine
- L'89% di σ_global proviene dalla variabilità stagionale, che nessuna finestra locale può vedere
- Usare σ_roll per la banda LOD significa ignorare la stagionalità → over-triggering sistematico

**Il LOD fisso è robusto su questo dataset** (concordanza 98.5% con il rolling). Il rolling LOD con σ_global è lo strumento corretto per deployment a lungo termine (anni), dove la deriva di μ diventa cumulativa e non trascurabile.

---

## 7. File prodotti

```
rolling_lod/
├── ellona_rolling_lod.m             — funzione helper (rolling μ, LOD con σ_global)
├── ELLONA_11_rolling_lod.m          — script confronto (3 finestre: 7d, 14d, 30d)
└── REPORT_rolling_lod.md            — questo documento

output/rolling_lod/
├── sigma_window_comparison.png      — σ_roll(t) per 7d / 14d / 30d vs σ_global [CHIAVE]
├── mu_window_comparison.png         — μ_roll(t) per 7d / 14d / 30d
├── PC1_fixed_vs_rolling.png         — PC1(t) con LOD fisso vs rolling 30d
├── events_weekly_comparison.png     — % eventi per settimana (4 varianti)
└── comparison_stats.csv             — tabella riepilogativa
```
