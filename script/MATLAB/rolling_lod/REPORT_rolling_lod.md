# LOD Mobile (Rolling LOD) — Report di sviluppo
**Progetto:** ELLONA — Electronic Nose per monitoraggio odori  
**Data:** 20 Aprile 2026  
**Autore:** Marco Calì — PoliMi

---

## 1. Motivazione

Il sistema ELLONA utilizza un modello PCA fisso addestrato sull'intero dataset (9 mesi, marzo–dicembre 2025). Il LOD (Limit of Detection) è definito come:

$$\text{LOD}^\pm = \mu_{BL} \pm k \cdot \sigma_{BL}$$

dove μ e σ sono calcolati una volta sola sul **baseline globale** (campioni nella banda IQR [P25, P75] dei quattro sensori MOX). Con k=3 e baseline *weekly* (finestra 7 giorni scorrevole per la selezione, ma parametri fissi):

- LOD = [−3.988, +3.988]
- Tasso eventi (PC1 < LOD⁻): **3.67%**

**Problema identificato:** un LOD fisso non compensa eventuali derive lente del baseline nel tempo (stagionalità termica, invecchiamento sensori, variazioni ambientali). Se il baseline reale deriva di +Δ, la soglia inferiore rimane ferma → sensitivity asimmetrica nel tempo.

---

## 2. Approccio: Rolling LOD

### 2.1 Idea

Per ogni istante t, ricalcolare μ(t) e σ(t) su una **finestra causale** degli ultimi N giorni, così che la banda LOD si adatti lentamente alla deriva del baseline.

### 2.2 Parametri scelti

| Parametro | Valore | Motivazione |
|---|---|---|
| Finestra | 7 giorni | Una settimana: abbastanza lunga da filtrare eventi episodici, abbastanza corta da seguire la deriva mensile |
| Step griglia | 1 giorno | Risoluzione giornaliera |
| Selezione baseline | IQR [P25, P75] su tutti e 4 i MOX | Stessa logica del LOD fisso |
| minPts | 100 punti | Soglia minima per validare una finestra (frequenza 10s → 7d = ~60480 punti, quindi molto permissiva) |
| Cold start | primi 7 giorni | Fallback al LOD globale |

### 2.3 Implementazione

File: `ellona_rolling_lod.m` (funzione helper)  
File: `ELLONA_11_rolling_lod.m` (script di confronto)

Algoritmo:
1. Costruire una griglia giornaliera da `t(1) + 7d` a `t(end)`
2. Per ogni giorno t_i: estrarre la finestra [t_i − 7d, t_i), applicare filtro IQR su X_mox, calcolare μ_grid(i) e σ_grid(i) sul PC1 dei punti in banda
3. Gap filling: `fillmissing(..., 'previous')` poi `'next'`
4. Interpolazione lineare alla risoluzione originale (10s)
5. Cold start: LOD globale per i primi 7 giorni

---

## 3. Problema: Over-triggering con σ locale

### 3.1 Prima versione (errata)

Nella prima implementazione, sia μ che σ erano rolling:

$$\text{LOD}(t) = \mu_{roll}(t) \pm k \cdot \sigma_{roll}(t)$$

**Risultato:**

| Metrica | LOD fisso | LOD rolling (v1) |
|---|---|---|
| % eventi | 3.67% | **23.04%** ❌ |
| σ medio | 1.3292 | 0.4431 |

### 3.2 Diagnosi

Il problema ha due cause:

**a) σ_locale << σ_globale (fattore ~3×)**  
σ_globale = 1.33 è calcolato su 9 mesi → include variabilità stagionale, deriva lenta, fluttuazioni mensili.  
σ_locale (7 giorni) = 0.44 in media → include solo il rumore di breve termine.  
La banda risultante è 3× più stretta → quasi tutto cade fuori → 23% eventi.

**b) Contaminazione di μ_roll durante eventi prolungati**  
Se una settimana ha molti eventi intensi, il filtro IQR non li esclude tutti → μ_roll si alza fino a +3.6 → LOD⁻_roll sale verso 0 → quasi tutto viene classificato come evento.

### 3.3 Fix: Opzione B — σ fisso, μ rolling

Ispirato ai grafici SPC (Statistical Process Control) con moving average:

$$\boxed{\text{LOD}(t) = \mu_{roll}(t) \pm k \cdot \sigma_{global}}$$

- **μ_roll**: adatta il *centro* alla deriva lenta del baseline ✓  
- **σ_global**: mantiene la *larghezza* della banda fissa, coerente con il noise-floor fisico del sensore ✓

Modifica in `ellona_rolling_lod.m`:
```matlab
% Opzione B: solo μ è rolling, σ rimane globale
lod_lo_grid = mu_grid - k * sigma_global;
lod_hi_grid = mu_grid + k * sigma_global;
```

---

## 4. Risultati finali

### 4.1 Confronto quantitativo

| Metrica | LOD fisso | LOD rolling (v2) |
|---|---|---|
| % eventi (LOD⁻) | 3.67% | **3.36%** ✅ |
| LOD⁻ medio | −3.988 | −4.046 |
| LOD⁺ medio | +3.988 | +3.930 |
| μ_BL medio | 0.000 | −0.058 |
| σ_BL medio | 1.329 | 0.443 (solo diagnostico) |
| Concordanza totale | — | **98.50%** |
| Solo LOD fisso | — | 0.90% |
| Solo LOD rolling | — | 0.59% |

### 4.2 Interpretazione della discordanza

- **0.90% solo nel fisso** (eventi persi dal rolling): periodi in cui μ_roll è salito (baseline in deriva positiva) → LOD⁻_roll si alza → eventi borderline non catturati. Comportamento *corretto*: il sensore stava operando in un regime diverso da quello di addestramento.

- **0.59% solo nel rolling** (nuovi eventi): periodi in cui μ_roll era sotto lo zero → LOD⁻_roll scende → eventi borderline catturati che il fisso perdeva. Questi sono il *vero guadagno* del rolling LOD.

### 4.3 Deriva del baseline

μ_BL medio rolling = −0.058 → lieve deriva negativa nell'arco dei 9 mesi.  
LOD⁻ rolling range: [−6.09, −0.33] → in alcuni periodi il baseline è salito fino a μ_roll ≈ +3.65 (verosimilmente agosto-settembre, picco attività biologica + temperatura).

---

## 5. Analisi della sensibilità al parametro k

### 5.1 Ragionamento

La differenza tra LOD fisso e rolling dipende dal rapporto:

$$\frac{|\mu_{roll}(t) - \mu_{fisso}|}{k \cdot \sigma_{global}}$$

Con deriva tipica ~0.5 e σ_global = 1.33:

| k | Metà banda | Deriva / Banda | Discordanza stimata |
|---|---|---|---|
| 3.0 | 3.99 | 12% | ~1.5% (misurato) |
| 2.0 | 2.66 | 19% | ~4–5% |
| 1.5 | 2.00 | 25% | ~8–10% |
| 1.0 | 1.33 | 38% | ~15–20% |

### 5.2 Conclusione sulla scelta di k

Il rolling LOD diventa rilevante per **k ≤ 1.5–2.0**. Tuttavia, a k < 2 il tasso eventi globale esplode (>20–30%), rendendo il rilevatore poco discriminante. Il valore k=3 è un buon compromesso: sensibilità ragionevole (3.67% eventi), LOD fisso robusto, rolling LOD che non aggiunge valore significativo su questo dataset.

Il rolling LOD sarebbe determinante in scenari a lungo termine (anni di deployment) o in presenza di:
- Ricalibrazioni / sostituzioni del sensore (salti di baseline)
- Deriva stagionale marcata (variazione temperatura ambiente > 20°C)
- Sostituzione del substrato chimico nei sensori

---

## 6. File prodotti

```
rolling_lod/
├── ellona_rolling_lod.m          — funzione helper (rolling μ, σ, LOD)
├── ELLONA_11_rolling_lod.m       — script di confronto fisso vs rolling
└── REPORT_rolling_lod.md         — questo documento

output/rolling_lod/
├── PC1_fixed_vs_rolling.png      — PC1(t) con entrambe le bande LOD
├── rolling_mu_sigma.png          — evoluzione μ(t) e σ(t) nel tempo
├── events_weekly_comparison.png  — confronto eventi per settimana
├── lod_disagreement.png          — periodi di discordanza
└── comparison_stats.csv          — tabella riepilogativa
```

---

## 7. Conclusione

> Il LOD fisso (μ_globale ± k·σ_globale) è **sufficientemente robusto** per questo dataset di 9 mesi. La concordanza del 98.5% con il rolling LOD dimostra che la deriva del baseline è contenuta e non pregiudica la detection con k=3.
>
> Il rolling LOD (μ_roll ± k·σ_globale) è lo strumento corretto per un **deployment a lungo termine**, dove la deriva diventa cumulativa. La chiave è mantenere σ_globale fisso (noise-floor fisico del sensore) e lasciare che solo il centro μ_roll si adatti: questo è esattamente il principio dei grafici Moving Average in Statistical Process Control.
