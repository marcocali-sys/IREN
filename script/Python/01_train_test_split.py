"""
Train/Test split per dataset ELLONA/IREN
- Rispetta i gruppi Sample.ID (stesso campione madre sempre nello stesso set)
- Stratificato per Classe2 (ogni classe rappresentata nel test)
- Ordina per Classe2 per ispezione visiva
- Salva TRAIN_FEATURES.csv e TEST_FEATURES.csv
"""

import pandas as pd
import numpy as np

# ── Parametri ──────────────────────────────────────────────────────────────────
INPUT_FILE  = "Features_Sall.csv"
TRAIN_FILE  = "TRAIN_FEATURES.csv"
TEST_FILE   = "TEST_FEATURES.csv"
TEST_SIZE   = 0.20   # 80% train / 20% test  →  cambia a 0.30 per 70/30
RANDOM_SEED = 42
# ──────────────────────────────────────────────────────────────────────────────

rng = np.random.default_rng(RANDOM_SEED)

# Carica dataset
df = pd.read_csv(INPUT_FILE, sep=";")
print(f"Dataset caricato: {df.shape[0]} campioni, {df.shape[1]} colonne")

assert "Sample.ID" in df.columns, "Colonna Sample.ID non trovata"
assert "Classe2"   in df.columns, "Colonna Classe2 non trovata"

# ── Analisi gruppi prima dello split ─────────────────────────────────────────
print(f"\nSample.ID unici: {df['Sample.ID'].nunique()}")
print("\nDistribuzione campioni per Classe2:")
for cls, n in df["Classe2"].value_counts().sort_index().items():
    print(f"  {cls:<15} {n:>3} campioni")

group_sizes = df.groupby("Sample.ID")["Classe2"].agg(["count", "first"])
group_sizes.columns = ["n_diluizioni", "Classe2"]
print(f"\nSample.ID con più diluizioni:")
multi = group_sizes[group_sizes["n_diluizioni"] > 1].sort_values("n_diluizioni", ascending=False)
print(multi.to_string())

# ── Split stratificato per classe a livello di Sample.ID ─────────────────────
# Per ogni classe: prendo i Sample.ID unici di quella classe,
# ne metto ~TEST_SIZE nel test, garantendo almeno 1 per classe.

test_ids  = []
train_ids = []

# Mappa Sample.ID → Classe2 (ogni Sample.ID appartiene a una sola classe)
id_to_class = df.groupby("Sample.ID")["Classe2"].first()

for cls in sorted(df["Classe2"].unique()):
    cls_ids = id_to_class[id_to_class == cls].index.tolist()
    cls_ids_arr = np.array(cls_ids)
    rng.shuffle(cls_ids_arr)

    n_test = max(1, round(len(cls_ids_arr) * TEST_SIZE))
    test_ids.extend(cls_ids_arr[:n_test].tolist())
    train_ids.extend(cls_ids_arr[n_test:].tolist())

train_df = df[df["Sample.ID"].isin(train_ids)].sort_values("Classe2").reset_index(drop=True)
test_df  = df[df["Sample.ID"].isin(test_ids) ].sort_values("Classe2").reset_index(drop=True)

# ── Verifica: nessun Sample.ID condiviso ─────────────────────────────────────
overlap = set(train_ids) & set(test_ids)
if overlap:
    print(f"\n⚠️  ATTENZIONE: Sample.ID in comune: {overlap}")
else:
    print(f"\n✓  Nessun Sample.ID condiviso tra train e test")

# ── Report finale ─────────────────────────────────────────────────────────────
print(f"\n{'':=<55}")
print(f"  SPLIT {int((1-TEST_SIZE)*100)}/{int(TEST_SIZE*100)}  (stratificato per Classe2)")
print(f"{'':=<55}")
print(f"  {'Classe2':<15} {'Train':>6} {'Test':>6} {'Totale':>8}")
print(f"  {'-'*40}")
for cls in sorted(df["Classe2"].unique()):
    n_tr = (train_df["Classe2"] == cls).sum()
    n_te = (test_df["Classe2"]  == cls).sum()
    print(f"  {cls:<15} {n_tr:>6} {n_te:>6} {n_tr+n_te:>8}")
print(f"  {'-'*40}")
print(f"  {'TOTALE':<15} {len(train_df):>6} {len(test_df):>6} {len(df):>8}")
print(f"  Sample.ID unici train: {train_df['Sample.ID'].nunique()}")
print(f"  Sample.ID unici test:  {test_df['Sample.ID'].nunique()}")

# ── Salva ─────────────────────────────────────────────────────────────────────
train_df.to_csv(TRAIN_FILE, sep=";", index=False)
test_df.to_csv(TEST_FILE,  sep=";", index=False)
print(f"\n✓  Salvato: {TRAIN_FILE}  ({len(train_df)} righe)")
print(f"✓  Salvato: {TEST_FILE}   ({len(test_df)} righe)")
