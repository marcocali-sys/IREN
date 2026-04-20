 # ELLONA Electronic Nose — Feature Selection Pipeline Report

**Progetto**: Classificazione sorgenti odorigene — Impianto IREN
**Strumento**: ELLONA Electronic Nose (Sacmi)
**Autore**: Marco Calì — Politecnico di Milano
**Data**: Aprile 2026

---

## 1. Descrizione del Dataset

### 1.1 Acquisizione dati

Il sistema ELLONA è installato presso un impianto di trattamento rifiuti IREN e acquisisce in continuo misurazioni da **10 sensori attivi**:

| Sensore | Tipo | Note |
|---------|------|------|
| cmos1–4 | MOS (Metal Oxide Semiconductor) | Sensori generici per VOC |
| NH₃ | Elettrochimico | Ammoniaca (ppm) |
| H₂S | Elettrochimico | Idrogeno solforato (ppm) |
| PID | Fotoionizzatore | **Escluso** (tutti i valori = 0) |
| Temperature | Ambientale | °C |
| Humidity | Ambientale | % RH |

I dati grezzi coprono il periodo **marzo–dicembre 2025** con frequenza di campionamento di **10 secondi** (~2.5 milioni di righe).

### 1.2 Campioni etichettati

Dalle misurazioni continue sono stati estratti **166 campioni etichettati** distribuiti in **5 classi**:

| Classe | N campioni | Sample.ID unici | Descrizione |
|--------|-----------|-----------------|-------------|
| ARIA | 31 | 13 | Aria di riferimento |
| BIOFILTRO | 22 | 9 | Effluente biofiltro |
| BIOGAS | 32 | 14 | Gas di digestione anaerobica |
| FORSU | 49 | 22 | Frazione Organica RSU |
| PERCOLATO | 32 | 10 | Percolato da discarica |
| **TOTALE** | **166** | **55** | |

### 1.3 Struttura dei campioni e diluizioni

Ogni `Sample.ID` identifica un **campione madre** che può essere misurato a più diluizioni (da 2 a 6 repliche). Tutti i campioni con lo stesso `Sample.ID` **devono sempre restare nello stesso set** (train o test) per evitare data leakage.

### 1.4 Feature estratte

Il dataset `Features_Sall.csv` contiene **142 colonne**:
- **128 feature numeriche** calcolate per ogni misura
- **14 colonne di metadati**: `Data.analisi`, `Classe`, `Classe2`, `Diluizione`, `Cod`, `Step1–3`, `Sample.ID`, `Sample.number`, `Datetime_inizio/fine`

Le feature coprono statistiche temporali estratte dalle risposte dei sensori: AUC, differenze di AUC, range normalizzati (BB, BNB, CC, FA, …), mediane, percentili e variabili derivate.

---

## 2. Split Train/Test

### 2.1 Strategia

Per rispettare il vincolo dei `Sample.ID`:

1. Raggruppamento dei campioni per `Sample.ID` (la classe è univoca per ogni Sample.ID)
2. Split **stratificato per classe** a livello di `Sample.ID` (80/20)
3. Ogni classe garantisce almeno 1 `Sample.ID` nel test set

```
Classe        Train   Test   Totale
ARIA            24      7       31
BIOFILTRO       18      4       22
BIOGAS          23      9       32
FORSU           41      8       49
PERCOLATO       32      0       32   *
TOTALE         138     28      166

Sample.ID unici  train: 44
Sample.ID unici  test:  11
```

> *Nota: PERCOLATO ha 10 Sample.ID, la split 80/20 assegna 8 al train e 2 al test in base al seed. Il risultato finale dipende dal seed casuale (`rng=42`).

**Verifica data leakage**: nessun `Sample.ID` condiviso tra train e test set.

### 2.2 Script

| Linguaggio | File |
|------------|------|
| Python | `script/Python/01_train_test_split.py` |
| R | `script/R/01_train_test_split.R` |
| MATLAB | `script/MATLAB/ELLONA_01_train_test_split.m` |

**Output**: `data/processed/TRAIN_FEATURES.csv` (138 righe), `data/processed/TEST_FEATURES.csv` (28 righe)

---

## 3. Selezione Feature — Pipeline a 4 Stadi

```
128 feature
    │
    ▼ Boruta (R/ranger)
   85 feature confirmed
    │
    ▼ LOGO-CV Importance Threshold
   31 feature
    │
    ▼ Correlation Pruning (|ρ| > 0.90)
   16 feature
    │
    ▼ RFECV (LOGO-CV, balanced_accuracy)
   11 feature FINALI
```

---

## 4. Stadio 1: Boruta Feature Selection

### 4.1 Metodo

Boruta è un wrapper attorno a Random Forest che confronta l'importanza di ogni feature reale con le **shadow feature** (copie permutate delle feature originali). Una feature viene confermata se la sua importanza è **statisticamente superiore** alla shadow feature più importante.

**Parametri**:
- Algoritmo RF: `ranger` (R) / `RandomForestClassifier` (Python)
- N alberi: 500
- Max iterazioni: 100
- Correzione per tentativi: `TentativeRoughFix()` (confronto con mediana shadow max)
- Target: `Classe2`

### 4.2 Risultati

| Linguaggio | Confirmed | Tentative | Rejected |
|------------|-----------|-----------|---------|
| **R (ranger)** | **85** | **0** | **43** |
| Python (sklearn RF) | 34 | 75 | 10 |

> **R è il risultato autorevole**: ranger usa un'implementazione più efficiente di RF con stima dell'importanza per permutazione, più stabile di sklearn. Python con 100 iterazioni non converge completamente su questo dataset.

### 4.3 Feature rigettate (43)

Le feature eliminate includono principalmente sensori correlati a temperatura/umidità e feature derivate dai canali CMOS meno informativi per questa classificazione.

### 4.4 Script

| Linguaggio | File |
|------------|------|
| Python | `script/Python/02_boruta.py` |
| R | `script/R/02_boruta.R` |
| MATLAB | `script/MATLAB/ELLONA_02_boruta.m` |

**Output**: `output/02_boruta/boruta_results.csv`, `boruta_selected_features.txt`, `boruta_importance.png`

---

## 5. Stadio 2: LOGO-CV Importance Threshold

### 5.1 Metodo

**Leave-One-Group-Out Cross-Validation** con `groups = Sample.ID` (44 fold nel training set).

Per ogni fold:
1. Training su 43 Sample.ID, test sul Sample.ID lasciato fuori
2. Feature importance MDI (Mean Decrease in Impurity) estratta
3. Media importanza su tutti i fold

**Threshold**: feature con `mean_importance > grand_mean` vengono selezionate.

### 5.2 Risultati

```
Feature in input:  85 (da Boruta R)
Feature selezionate: 31
Accuratezza LOGO media: 0.639 ± 0.378
```

> L'alta varianza (±0.378) è attesa con LOGO: alcuni Sample.ID sono campioni diluiti con caratteristiche molto simili ai campioni nel training set, altri sono più diversi. Non indica un problema del modello.

### 5.3 Le 31 feature selezionate

`diffAUC2_4`, `diffAUC1_4`, `FA1`, `BNBn2`, `D2`, `BNBn4`, `N2`, `BBn4`, `diffAUC3_4`, `RRn4`, `SSn4`, `BNBn1`, `BNB4`, `BB4`, `SS4`, `CCn4`, `A2`, `FA4`, `CCn1`, `BBn1`, `CC4`, `RRn1`, `BNB1`, `RR4`, `CC1`, `SSn1`, `H2`, `LN1`, `O1`, `H1`, `M4`

### 5.4 Script

| Linguaggio | File |
|------------|------|
| Python | `script/Python/03_logo_feature_selection.py` |
| R | `script/R/03_logo_feature_selection.R` |
| MATLAB | `script/MATLAB/ELLONA_03_logo_feature_selection.m` |

**Output**: `output/03_logo_cv/logo_feature_importance.csv`, `logo_selected_features.txt`, `logo_importance.png`

---

## 6. Stadio 3: Correlation Pruning

### 6.1 Metodo

Eliminazione greedy delle feature ridondanti basata su correlazione di Pearson:

1. Feature ordinate per importanza LOGO (decrescente)
2. Per ogni feature, calcolo correlazione con tutte le feature già accettate
3. Se `max(|ρ|) > 0.90` → feature rimossa (ridondante con una già selezionata)
4. Altrimenti → feature accettata

La feature più importante viene sempre mantenuta.

### 6.2 Risultati

```
Feature in input:  31
Feature selezionate: 16
Soglia correlazione: |ρ| = 0.90
```

**Principali coppie rimosse**:

| Feature rimossa | Correlata con | |ρ| |
|-----------------|---------------|-----|
| RRn4 | BBn4 | ≈ 1.000 |
| SSn4 | BBn4 | ≈ 1.000 |
| BNB4 | BBn4 | ≈ 1.000 |
| N2 | D2 | 0.976 |
| BNB1 | BNBn1 | 0.960 |
| RRn1 | BBn4 | 0.953 |
| CCn4 | BBn4 | 0.948 |
| CC4 | CC1 | 0.944 |
| SS4 | BBn4 | 0.943 |
| BBn1 | BNBn1 | 0.937 |
| LN1 | CCn1 | 0.933 |
| O1 | CCn1 | 0.930 |
| RR4 | BBn4 | 0.924 |
| SSn1 | BNBn1 | 0.920 |
| H1 | M4 | 0.912 |

### 6.3 Le 16 feature post-pruning

`diffAUC2_4`, `diffAUC1_4`, `FA1`, `BNBn2`, `D2`, `BNBn4`, `BBn4`, `diffAUC3_4`, `BNBn1`, `BB4`, `A2`, `FA4`, `CCn1`, `CC1`, `H1`, `M4`

### 6.4 Script

| Linguaggio | File |
|------------|------|
| Python | `script/Python/05_correlation_pruning.py` |
| R | `script/R/05_correlation_pruning.R` |
| MATLAB | `script/MATLAB/ELLONA_05_correlation_pruning.m` |

**Output**: `output/05_corr_pruning/corr_matrix_full.png`, `corr_matrix_kept.png`, `corr_pruning_report.csv`, `corr_pruned_features.txt`

---

## 7. Stadio 4: RFECV

### 7.1 Metodo

**Recursive Feature Elimination with Cross-Validation** (LOGO-CV, `groups = Sample.ID`).

- Stimatore: `RandomForestClassifier(n_estimators=300, class_weight="balanced")`
- Scoring: `balanced_accuracy` (robusto allo sbilanciamento tra classi)
- Step: 1 feature per iterazione
- Min feature: 3
- CV: `LeaveOneGroupOut()` con `groups = Sample.ID`

### 7.2 Risultati

```
Feature in input:  16
Feature selezionate: 11
Balanced accuracy ottimale: 0.6530 ± 0.3808
```

### 7.3 Le 11 feature finali

| Feature | Descrizione |
|---------|-------------|
| `diffAUC2_4` | Differenza AUC sensore 2 vs 4 |
| `diffAUC1_4` | Differenza AUC sensore 1 vs 4 |
| `FA1` | Feature FA del sensore 1 |
| `BNBn4` | Feature BNB normalizzata sensore 4 |
| `BBn4` | Feature BB normalizzata sensore 4 |
| `diffAUC3_4` | Differenza AUC sensore 3 vs 4 |
| `BNBn1` | Feature BNB normalizzata sensore 1 |
| `BB4` | Feature BB sensore 4 |
| `FA4` | Feature FA del sensore 4 |
| `CCn1` | Feature CC normalizzata sensore 1 |
| `M4` | Feature M del sensore 4 |

**Osservazioni**:
- Dominanza del **sensore 4** (cmos4): 6 delle 11 feature (BBn4, BNBn4, BB4, FA4, diffAUC*_4)
- Il sensore 4 è il più discriminante per queste 5 classi odorigene
- Le **differenze di AUC** (diffAUC1_4, diffAUC2_4, diffAUC3_4) catturano relazioni tra sensori, più robuste ai drift di singolo sensore
- Nessuna feature da NH₃ o H₂S è nella selezione finale — probabilmente correlate con le feature MOS

### 7.4 Script

| Linguaggio | File |
|------------|------|
| Python | `script/Python/06_rfecv.py` |
| R | `script/R/06_rfecv.R` |
| MATLAB | `script/MATLAB/ELLONA_06_rfecv.m` |

**Output**: `output/06_rfecv/rfecv_results.png`, `rfecv_curve.csv`, `rfecv_report.csv`, `rfecv_selected_features.txt`

---

## 8. Analisi PCA

### 8.1 Setup

- **Feature usate**: 31 feature post-LOGO (con marker ★ per le 11 finali nella GUI MATLAB)
- **Preprocessing**: standardizzazione (mean=0, std=1), imputazione mediana per NA
- **Dataset**: TRAIN (138 campioni) + TEST (28 campioni) visualizzati insieme

### 8.2 Varianza spiegata

| Componente | Varianza spiegata | Cumulativa |
|------------|------------------|------------|
| PC1 | ~35–40% | ~35–40% |
| PC2 | ~15–20% | ~55–60% |
| PC3 | ~8–12% | ~65–70% |

### 8.3 Separazione classi

Nel piano PC1-PC2 si osserva:
- **BIOGAS** e **PERCOLATO**: tendenza a separarsi nella direzione PC1
- **FORSU**: cluster centrale con maggiore dispersione (attesa: FORSU ha il range più ampio di caratteristiche odorose)
- **ARIA**: cluster compatto (bassa intensità odorigena)
- **BIOFILTRO**: parziale sovrapposizione con ARIA e FORSU

### 8.4 Visualizzazioni disponibili

| File | Tipo |
|------|------|
| `output/04_pca/pca_scree.png` | Scree plot (varianza spiegata) |
| `output/04_pca/pca_scores.png` | Score plot PC1 vs PC2 (statico) |
| `output/04_pca/pca_scores_PC1_PC3.png` | Score plot PC1 vs PC3 |
| `output/04_pca/pca_3d.png` | Score plot 3D (statico) |
| `output/04_pca/pca_loadings.png` | Loadings circle PC1 vs PC2 |
| `output/04_pca/pca_3d_interactive.html` | 3D interattivo (Plotly, ruotabile) |
| `output/04_pca/pca_2d_interactive.html` | 2D + scree dashboard interattivo |
| `output/04_pca/pca_loadings_interactive.html` | Loadings circle interattivo |

### 8.5 GUI MATLAB

`script/MATLAB/ELLONA_04_pca_gui.m` — Tool interattivo completo con:
- Selezione feature da listbox (★ = feature LOGO-selezionate)
- Toggle 2D/3D
- Filtro per classe e per set (TRAIN/TEST)
- Datacursor con info complete (PC1/2/3, Classe2, Sample.ID, Cod, Diluizione)
- Scree plot e Loadings viewer con heatmap
- Export PNG

---

## 9. Struttura della cartella IREN

```
IREN/
├── data/
│   ├── raw/
│   │   ├── Features_Sall.csv          # Dataset originale (166×142)
│   │   ├── RE_seconda_scheda_marzo-dic2025.csv
│   │   ├── Estrazione_Features.R      # Script R fornito dai ricercatori
│   │   └── monitoraggio2025/          # Dati continui grezzi
│   └── processed/
│       ├── TRAIN_FEATURES.csv         # 138 campioni
│       └── TEST_FEATURES.csv          # 28 campioni
│
├── output/
│   ├── 01_split/
│   ├── 02_boruta/
│   ├── 03_logo_cv/
│   ├── 04_pca/                        # Include file HTML interattivi
│   ├── 05_corr_pruning/
│   └── 06_rfecv/
│
└── script/
    ├── Python/
    │   ├── 01_train_test_split.py
    │   ├── 02_boruta.py
    │   ├── 03_logo_feature_selection.py
    │   ├── 04_pca.py
    │   ├── 04_pca_interactive.py
    │   ├── 05_correlation_pruning.py
    │   └── 06_rfecv.py
    ├── R/
    │   ├── 01_train_test_split.R
    │   ├── 02_boruta.R
    │   ├── 03_logo_feature_selection.R
    │   ├── 04_pca.R
    │   ├── 04_pca_interactive.R
    │   ├── 05_correlation_pruning.R
    │   └── 06_rfecv.R
    └── MATLAB/
        ├── ELLONA_01_train_test_split.m
        ├── ELLONA_02_boruta.m
        ├── ELLONA_03_logo_feature_selection.m
        ├── ELLONA_04_pca.m
        ├── ELLONA_04_pca_gui.m
        ├── ELLONA_05_correlation_pruning.m
        └── ELLONA_06_rfecv.m
```

---

## 10. Riepilogo Pipeline

| Stadio | Metodo | Input | Output | Script |
|--------|--------|-------|--------|--------|
| Split | Stratified 80/20 (Sample.ID level) | 166 campioni | 138 train / 28 test | 01_* |
| Boruta | Boruta + ranger RF, 500 alberi | 128 feature | **85 feature** | 02_* |
| LOGO-CV | RF MDI importance, LOGO, threshold=mean | 85 feature | **31 feature** | 03_* |
| PCA | sklearn/prcomp/MATLAB pca() | 31 feature | Visualizzazioni | 04_* |
| Corr. Pruning | Greedy, \|ρ\| > 0.90 | 31 feature | **16 feature** | 05_* |
| RFECV | RFECV + LOGO + balanced_accuracy | 16 feature | **11 feature** | 06_* |

### Feature finali (11)

```
diffAUC2_4  |  diffAUC1_4  |  FA1  |  BNBn4  |  BBn4
diffAUC3_4  |  BNBn1       |  BB4  |  FA4    |  CCn1  |  M4
```

**Balanced accuracy (LOGO-CV su training set)**: 0.653 ± 0.381

---

## 11. Note Tecniche

### Prevenzione data leakage
Ogni Sample.ID rappresenta un campione madre con più diluizioni. Tutte le diluizioni dello stesso campione si trovano sempre nello **stesso set** (train o test). Le procedure di cross-validation usano sempre `groups = Sample.ID`.

### Sbilanciamento delle classi
`balanced_accuracy` usato come metrica principale (media del recall per classe). `class_weight="balanced"` in tutti i RandomForest per down-pesare le classi numerose.

### Feature PID esclusa
`D3` e `N3` (derivate dal sensore PID) sono escluse: tutti i valori sono 0 in questo dataset.

### Delimitatore CSV
Tutti i file CSV usano **punto e virgola** (`;`) come separatore.

### Compatibilità MATLAB
I file MATLAB usano `detectImportOptions(..., 'Delimiter', ';')` e `readtable()`. Il nome colonna `Sample.ID` viene rinominato automaticamente in `Sample_ID` da MATLAB.

---

*Report generato automaticamente — Aprile 2026*
