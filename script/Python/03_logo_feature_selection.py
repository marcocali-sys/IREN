"""
LOGO-CV Feature Selection — ELLONA/IREN
- Legge le feature Boruta-confirmed da boruta_results.csv
- Leave-One-Group-Out CV con gruppi = Sample.ID
- Per ogni fold: allena RF, registra importanza feature
- Output: importanza media ± std su tutti i fold
          selezione finale per soglia (mean > grand_mean)
          logo_feature_importance.csv
          logo_selected_features.txt
"""

import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.model_selection import LeaveOneGroupOut
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

# ── Parametri ──────────────────────────────────────────────────────────────────
TRAIN_FILE      = "TRAIN_FEATURES.csv"
BORUTA_FILE     = "boruta_results.csv"
RESULTS_FILE    = "logo_feature_importance.csv"
SELECTED_FILE   = "logo_selected_features.txt"
PLOT_FILE       = "logo_importance.png"
RANDOM_SEED     = 42
N_TREES         = 500
# ──────────────────────────────────────────────────────────────────────────────

META_COLS = [
    "Data.analisi", "Classe", "Classe2", "Diluizione", "Cod",
    "Step1", "Step2", "Step3", "Sample.ID", "Sample.number",
    "Datetime_inizio", "Datetime_fine"
]

# ── Carica feature Boruta-confirmed ───────────────────────────────────────────
boruta_df     = pd.read_csv(BORUTA_FILE, sep=";")
confirmed_feats = boruta_df[boruta_df["Status"] == "Confirmed"]["Feature"].tolist()
print(f"Feature Boruta-confirmed: {len(confirmed_feats)}")

# ── Carica training set ───────────────────────────────────────────────────────
df     = pd.read_csv(TRAIN_FILE, sep=";")
groups = df["Sample.ID"].values
y      = df["Classe2"].values
X_raw  = df[confirmed_feats].values

print(f"Training set: {df.shape[0]} campioni, {len(confirmed_feats)} feature")
print(f"Gruppi (Sample.ID): {len(np.unique(groups))} unici → {len(np.unique(groups))} fold LOGO")

# ── Imputazione NA ────────────────────────────────────────────────────────────
imputer = SimpleImputer(strategy="median")
X = imputer.fit_transform(X_raw)

# ── LOGO-CV ───────────────────────────────────────────────────────────────────
logo       = LeaveOneGroupOut()
n_folds    = logo.get_n_splits(X, y, groups)
n_feat     = len(confirmed_feats)

imp_matrix = np.zeros((n_folds, n_feat))   # importanza per fold
acc_per_fold = []

rf = RandomForestClassifier(
    n_estimators=N_TREES,
    max_features="sqrt",
    n_jobs=-1,
    random_state=RANDOM_SEED
)

print(f"\nAvvio LOGO-CV ({n_folds} fold)...")
for fold_idx, (train_idx, test_idx) in enumerate(logo.split(X, y, groups)):
    X_tr, X_te = X[train_idx], X[test_idx]
    y_tr, y_te = y[train_idx], y[test_idx]

    rf_fold = RandomForestClassifier(
        n_estimators=N_TREES,
        max_features="sqrt",
        n_jobs=-1,
        random_state=RANDOM_SEED
    )
    rf_fold.fit(X_tr, y_tr)

    imp_matrix[fold_idx] = rf_fold.feature_importances_

    acc = (rf_fold.predict(X_te) == y_te).mean()
    acc_per_fold.append(acc)

    left_out_id = np.unique(groups[test_idx])[0]
    left_out_cls = np.unique(y[test_idx])[0]
    print(f"  Fold {fold_idx+1:2d}/{n_folds} | Group={left_out_id:3d} ({left_out_cls:<12}) | Acc={acc:.2f}")

print(f"\nAccuratezza media LOGO: {np.mean(acc_per_fold):.3f} ± {np.std(acc_per_fold):.3f}")

# ── Aggregazione importanze ───────────────────────────────────────────────────
mean_imp  = imp_matrix.mean(axis=0)
std_imp   = imp_matrix.std(axis=0)
# Frequenza: % di fold in cui la feature è nel top 50% per importanza
top50_threshold = np.median(imp_matrix, axis=1, keepdims=True)
top50_freq      = (imp_matrix >= top50_threshold).mean(axis=0)

# Soglia di selezione: mean_imp > grand_mean
grand_mean = mean_imp.mean()
selected   = mean_imp > grand_mean

results_df = pd.DataFrame({
    "Feature":       confirmed_feats,
    "MeanImportance": mean_imp,
    "StdImportance":  std_imp,
    "Top50pct_freq":  top50_freq,
    "Selected":       selected
}).sort_values("MeanImportance", ascending=False).reset_index(drop=True)

results_df["Rank"] = range(1, len(results_df) + 1)

# ── Report console ─────────────────────────────────────────────────────────────
print(f"\n{'':=<65}")
print(f"  LOGO-CV Feature Ranking (soglia: mean > {grand_mean:.5f})")
print(f"{'':=<65}")
print(f"  {'Rk':>3}  {'Feature':<15} {'MeanImp':>9} {'StdImp':>8} {'Top50%':>7} {'Sel':>5}")
print(f"  {'-'*55}")
for _, row in results_df.iterrows():
    mark = "✓" if row["Selected"] else " "
    print(f"  {int(row['Rank']):>3}  {row['Feature']:<15} {row['MeanImportance']:>9.5f} "
          f"{row['StdImportance']:>8.5f} {row['Top50pct_freq']:>7.2%} {mark:>5}")

n_sel = selected.sum()
print(f"\n  Feature selezionate: {n_sel} / {n_feat}")
print(f"  Feature scartate:    {n_feat - n_sel} / {n_feat}")

# ── Plot ───────────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(16, 6))

colors = ["#2196F3" if s else "#BDBDBD" for s in results_df["Selected"]]
bars   = ax.bar(range(n_feat), results_df["MeanImportance"], color=colors,
                yerr=results_df["StdImportance"], capsize=2, error_kw={"linewidth": 0.8})

ax.axhline(grand_mean, color="red", linestyle="--", linewidth=1.2, label=f"Soglia (mean={grand_mean:.4f})")
ax.set_xticks(range(n_feat))
ax.set_xticklabels(results_df["Feature"], rotation=90, fontsize=7)
ax.set_ylabel("Mean Feature Importance (MDI)")
ax.set_title("LOGO-CV Feature Importance — ELLONA/IREN\n(blu=selezionata, grigio=scartata)")
ax.legend()
ax.grid(axis="y", alpha=0.3)
plt.tight_layout()
plt.savefig(PLOT_FILE, dpi=150)
plt.close()
print(f"\n✓  Salvato: {PLOT_FILE}")

# ── Salva ─────────────────────────────────────────────────────────────────────
results_df.to_csv(RESULTS_FILE, sep=";", index=False)

selected_feats = results_df[results_df["Selected"]]["Feature"].tolist()
with open(SELECTED_FILE, "w") as f:
    f.write(f"# LOGO-CV Feature Selection — {n_sel} feature selezionate\n")
    f.write(f"# Soglia: MeanImportance > grand_mean ({grand_mean:.6f})\n")
    f.write(f"# AccuratezzaMedia_LOGO: {np.mean(acc_per_fold):.4f}\n\n")
    for feat in selected_feats:
        f.write(feat + "\n")

print(f"✓  Salvato: {RESULTS_FILE}")
print(f"✓  Salvato: {SELECTED_FILE}")
