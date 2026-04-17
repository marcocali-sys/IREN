"""
PCA con feature selezionate per ANOVA F-statistic — ELLONA/IREN
Seleziona le feature dove la varianza inter-classe è massima rispetto
alla varianza intra-classe: PCA su questi dati separa visivamente le classi.

Input:  data/processed/TRAIN_FEATURES.csv
        output/02_boruta/boruta_selected_features.txt  (85 feature Boruta)
Output: output/08_pca_anova/
"""

import os
import pandas as pd
import numpy as np
from sklearn.decomposition import PCA
from sklearn.preprocessing import StandardScaler
from sklearn.impute import SimpleImputer
from sklearn.feature_selection import f_classif
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.transforms as transforms
from matplotlib.patches import Ellipse
import plotly.graph_objects as go
from plotly.subplots import make_subplots

# ── Parametri ──────────────────────────────────────────────────────────────────
TRAIN_FILE = "data/processed/TRAIN_FEATURES.csv"
FEAT_FILE  = "output/02_boruta/boruta_selected_features.txt"
OUT_DIR    = "output/08_pca_anova"
N_TOP      = 12          # numero feature da selezionare per ANOVA

CLASS_COLORS = {
    "ARIA":      "#4878CF",
    "BIOFILTRO": "#6ACC65",
    "BIOGAS":    "#D65F5F",
    "FORSU":     "#B47CC7",
    "PERCOLATO": "#C4AD66",
}
CLASS_MARKERS = {
    "ARIA": "o", "BIOFILTRO": "s", "BIOGAS": "^", "FORSU": "D", "PERCOLATO": "P"
}
CLASS_SYMBOLS_3D = {
    "ARIA": "circle", "BIOFILTRO": "square", "BIOGAS": "diamond",
    "FORSU": "cross", "PERCOLATO": "circle-open"
}
# ──────────────────────────────────────────────────────────────────────────────

os.makedirs(OUT_DIR, exist_ok=True)

# ── Carica feature Boruta ─────────────────────────────────────────────────────
with open(FEAT_FILE) as f:
    boruta_feats = [l.strip() for l in f if l.strip() and not l.startswith("#")]
print(f"Feature Boruta in input: {len(boruta_feats)}")

# ── Carica dati ───────────────────────────────────────────────────────────────
df    = pd.read_csv(TRAIN_FILE, sep=";")
y     = df["Classe2"].values
sids  = df["Sample.ID"].values
X_raw = df[boruta_feats].values

X_imp = SimpleImputer(strategy="median").fit_transform(X_raw)
X_std = StandardScaler().fit_transform(X_imp)

# ── ANOVA F-statistic ─────────────────────────────────────────────────────────
f_vals, p_vals = f_classif(X_std, y)

anova_df = pd.DataFrame({
    "Feature":   boruta_feats,
    "F_stat":    f_vals,
    "p_value":   p_vals,
}).sort_values("F_stat", ascending=False).reset_index(drop=True)

anova_df.to_csv(os.path.join(OUT_DIR, "anova_ranking.csv"), sep=";", index=False)

print(f"\nTop {N_TOP} feature per F-statistic ANOVA:")
for _, row in anova_df.head(N_TOP).iterrows():
    print(f"  {row['Feature']:20s}  F={row['F_stat']:.1f}   p={row['p_value']:.2e}")

# ── Plot ranking ANOVA (top 25) ───────────────────────────────────────────────
top25 = anova_df.head(25).copy()
top25["selected"] = top25["Feature"].isin(anova_df.head(N_TOP)["Feature"])

fig, ax = plt.subplots(figsize=(10, 7))
colors = ["#4878CF" if s else "#BDBDBD" for s in top25["selected"]]
bars = ax.barh(top25["Feature"][::-1], top25["F_stat"][::-1],
               color=colors[::-1], alpha=0.85, edgecolor="white")
ax.axvline(anova_df.iloc[N_TOP-1]["F_stat"], color="#D65F5F",
           linestyle="--", linewidth=1, label=f"Soglia top {N_TOP}")
ax.set_xlabel("F-statistic ANOVA (one-way)", fontsize=11)
ax.set_title(f"Ranking feature ANOVA — Top {N_TOP} selezionate (blu)", fontsize=12)
ax.legend(fontsize=9)
ax.grid(axis="x", alpha=0.3)
plt.tight_layout()
plt.savefig(os.path.join(OUT_DIR, "anova_ranking.png"), dpi=150)
plt.close()
print("✓  anova_ranking.png")

# ── Seleziona top N e ricalcola PCA ──────────────────────────────────────────
selected = anova_df.head(N_TOP)["Feature"].tolist()
print(f"\nFeature selezionate per PCA: {selected}")

X_sel = X_std[:, [boruta_feats.index(f) for f in selected]]

pca      = PCA(random_state=42)
scores   = pca.fit_transform(X_sel)
exp_var  = pca.explained_variance_ratio_ * 100
cum_var  = np.cumsum(exp_var)
loadings = pca.components_

print(f"\nPC1: {exp_var[0]:.1f}%  |  PC2: {exp_var[1]:.1f}%  |  PC3: {exp_var[2]:.1f}%")
print(f"Cumulativa PC1+PC2: {exp_var[0]+exp_var[1]:.1f}%")

classes = sorted(CLASS_COLORS.keys())

# ── Helper ellisse ────────────────────────────────────────────────────────────
def confidence_ellipse(x, y_arr, ax, n_std=2.0, **kwargs):
    if len(x) < 3:
        return
    cov = np.cov(x, y_arr)
    pearson = cov[0,1] / np.sqrt(cov[0,0] * cov[1,1])
    rx = np.sqrt(1 + pearson)
    ry = np.sqrt(1 - pearson)
    ell = Ellipse((0,0), width=rx*2, height=ry*2, **kwargs)
    sx = np.sqrt(cov[0,0]) * n_std
    sy = np.sqrt(cov[1,1]) * n_std
    t  = transforms.Affine2D().rotate_deg(45).scale(sx, sy).translate(np.mean(x), np.mean(y_arr))
    ell.set_transform(t + ax.transData)
    ax.add_patch(ell)

# ──────────────────────────────────────────────────────────────────────────────
# PLOT: PC1 vs PC2
# ──────────────────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(9, 7))
for cls in classes:
    mask = y == cls
    if mask.sum() == 0:
        continue
    ax.scatter(scores[mask,0], scores[mask,1],
               c=CLASS_COLORS[cls], marker=CLASS_MARKERS[cls],
               s=70, alpha=0.85, edgecolors="white", linewidths=0.5,
               label=f"{cls} (n={mask.sum()})")
    confidence_ellipse(scores[mask,0], scores[mask,1], ax, n_std=2.0,
                       edgecolor=CLASS_COLORS[cls], facecolor=CLASS_COLORS[cls],
                       alpha=0.12, linewidth=1.5)

ax.axhline(0, color="gray", linewidth=0.5, linestyle="--")
ax.axvline(0, color="gray", linewidth=0.5, linestyle="--")
ax.set_xlabel(f"PC1 ({exp_var[0]:.1f}%)", fontsize=12)
ax.set_ylabel(f"PC2 ({exp_var[1]:.1f}%)", fontsize=12)
ax.set_title(f"PCA — Top {N_TOP} feature ANOVA  (ellissi 95%)", fontsize=13)
ax.legend(loc="best", framealpha=0.9, fontsize=9)
ax.grid(alpha=0.2)
plt.tight_layout()
plt.savefig(os.path.join(OUT_DIR, "pca_scores.png"), dpi=150)
plt.close()
print("✓  pca_scores.png")

# ──────────────────────────────────────────────────────────────────────────────
# PLOT: PC1 vs PC3
# ──────────────────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(9, 7))
for cls in classes:
    mask = y == cls
    ax.scatter(scores[mask,0], scores[mask,2],
               c=CLASS_COLORS[cls], marker=CLASS_MARKERS[cls],
               s=70, alpha=0.85, edgecolors="white", linewidths=0.5,
               label=f"{cls} (n={mask.sum()})")
    confidence_ellipse(scores[mask,0], scores[mask,2], ax, n_std=2.0,
                       edgecolor=CLASS_COLORS[cls], facecolor=CLASS_COLORS[cls],
                       alpha=0.12, linewidth=1.5)
ax.axhline(0, color="gray", linewidth=0.5, linestyle="--")
ax.axvline(0, color="gray", linewidth=0.5, linestyle="--")
ax.set_xlabel(f"PC1 ({exp_var[0]:.1f}%)", fontsize=12)
ax.set_ylabel(f"PC3 ({exp_var[2]:.1f}%)", fontsize=12)
ax.set_title(f"PCA PC1 vs PC3 — Top {N_TOP} feature ANOVA", fontsize=13)
ax.legend(loc="best", framealpha=0.9, fontsize=9)
ax.grid(alpha=0.2)
plt.tight_layout()
plt.savefig(os.path.join(OUT_DIR, "pca_scores_PC1_PC3.png"), dpi=150)
plt.close()
print("✓  pca_scores_PC1_PC3.png")

# ──────────────────────────────────────────────────────────────────────────────
# PLOT: Scree
# ──────────────────────────────────────────────────────────────────────────────
fig, axes = plt.subplots(1, 2, figsize=(12, 4))
n_show = min(N_TOP, 10)
axes[0].bar(range(1, n_show+1), exp_var[:n_show], color="#4878CF", alpha=0.8, edgecolor="white")
axes[0].set_xlabel("Componente principale"); axes[0].set_ylabel("Varianza spiegata (%)")
axes[0].set_title("Scree Plot"); axes[0].set_xticks(range(1, n_show+1))
for i, v in enumerate(exp_var[:n_show]):
    axes[0].text(i+1, v+0.3, f"{v:.1f}%", ha="center", fontsize=8)

axes[1].plot(range(1, n_show+1), cum_var[:n_show], "o-", color="#D65F5F",
             linewidth=1.5, markersize=4)
axes[1].axhline(90, color="gray", linestyle="--", linewidth=1, label="90%")
axes[1].set_xlabel("Numero di componenti"); axes[1].set_ylabel("Varianza cumulativa (%)")
axes[1].set_title("Varianza Cumulativa"); axes[1].legend(); axes[1].grid(alpha=0.3)
plt.tight_layout()
plt.savefig(os.path.join(OUT_DIR, "pca_scree.png"), dpi=150)
plt.close()
print("✓  pca_scree.png")

# ──────────────────────────────────────────────────────────────────────────────
# PLOT: Loadings (tutte le feature selezionate)
# ──────────────────────────────────────────────────────────────────────────────
load1 = loadings[0]; load2 = loadings[1]
contrib = np.sqrt(load1**2 + load2**2)
order = np.argsort(contrib)[::-1]

fig, ax = plt.subplots(figsize=(9, 7))
for i in order:
    ax.annotate("", xy=(load1[i], load2[i]), xytext=(0,0),
                arrowprops=dict(arrowstyle="->", color="#4878CF", lw=1.5))
    ax.text(load1[i]*1.1, load2[i]*1.1, selected[i],
            fontsize=8.5, ha="center", color="#222222")
circle = plt.Circle((0,0), 1, fill=False, color="gray", linestyle="--", linewidth=0.8)
ax.add_patch(circle)
ax.set_xlim(-1.2, 1.2); ax.set_ylim(-1.2, 1.2)
ax.axhline(0, color="gray", linewidth=0.5); ax.axvline(0, color="gray", linewidth=0.5)
ax.set_xlabel(f"PC1 ({exp_var[0]:.1f}%)", fontsize=12)
ax.set_ylabel(f"PC2 ({exp_var[1]:.1f}%)", fontsize=12)
ax.set_title(f"Cerchio delle correlazioni — {N_TOP} feature ANOVA", fontsize=13)
ax.set_aspect("equal"); ax.grid(alpha=0.2)
plt.tight_layout()
plt.savefig(os.path.join(OUT_DIR, "pca_loadings.png"), dpi=150)
plt.close()
print("✓  pca_loadings.png")

# ──────────────────────────────────────────────────────────────────────────────
# PLOT: 3D statico
# ──────────────────────────────────────────────────────────────────────────────
from mpl_toolkits.mplot3d import Axes3D  # noqa
fig = plt.figure(figsize=(10, 7))
ax3 = fig.add_subplot(111, projection="3d")
for cls in classes:
    mask = y == cls
    ax3.scatter(scores[mask,0], scores[mask,1], scores[mask,2],
                c=CLASS_COLORS[cls], marker=CLASS_MARKERS[cls],
                s=50, alpha=0.85, edgecolors="white", linewidths=0.3, label=cls)
ax3.set_xlabel(f"PC1 ({exp_var[0]:.1f}%)", fontsize=9)
ax3.set_ylabel(f"PC2 ({exp_var[1]:.1f}%)", fontsize=9)
ax3.set_zlabel(f"PC3 ({exp_var[2]:.1f}%)", fontsize=9)
ax3.set_title(f"PCA 3D — Top {N_TOP} feature ANOVA", fontsize=12)
ax3.legend(loc="upper left", fontsize=8, framealpha=0.8)
plt.tight_layout()
plt.savefig(os.path.join(OUT_DIR, "pca_3d.png"), dpi=150)
plt.close()
print("✓  pca_3d.png")

# ──────────────────────────────────────────────────────────────────────────────
# Plotly 3D interattivo
# ──────────────────────────────────────────────────────────────────────────────
hover = [
    f"<b>{cls}</b><br>Sample.ID: {sid}<br>PC1: {s1:.2f}<br>PC2: {s2:.2f}<br>PC3: {s3:.2f}"
    for cls, sid, s1, s2, s3 in zip(y, sids, scores[:,0], scores[:,1], scores[:,2])
]

fig3d = go.Figure()
for cls in sorted(CLASS_COLORS.keys()):
    mask = y == cls
    fig3d.add_trace(go.Scatter3d(
        x=scores[mask,0], y=scores[mask,1], z=scores[mask,2],
        mode="markers",
        name=f"{cls} (n={mask.sum()})",
        marker=dict(size=6, color=CLASS_COLORS[cls], symbol=CLASS_SYMBOLS_3D[cls],
                    opacity=0.85, line=dict(color="white", width=0.5)),
        text=[hover[i] for i in np.where(mask)[0]],
        hovertemplate="%{text}<extra></extra>"
    ))
fig3d.update_layout(
    title=dict(
        text=f"<b>PCA 3D — Top {N_TOP} feature ANOVA</b><br>"
             f"<sup>PC1={exp_var[0]:.1f}%  PC2={exp_var[1]:.1f}%  PC3={exp_var[2]:.1f}%</sup>",
        x=0.5),
    scene=dict(
        xaxis_title=f"PC1 ({exp_var[0]:.1f}%)",
        yaxis_title=f"PC2 ({exp_var[1]:.1f}%)",
        zaxis_title=f"PC3 ({exp_var[2]:.1f}%)",
        camera=dict(eye=dict(x=1.5, y=1.5, z=1.0))
    ),
    legend=dict(title="Classe", itemsizing="constant", font=dict(size=12)),
    margin=dict(l=0, r=0, t=80, b=0), width=1000, height=750,
)
fig3d.write_html(os.path.join(OUT_DIR, "pca_3d_interactive.html"),
                 include_plotlyjs="cdn", full_html=True)
print("✓  pca_3d_interactive.html")

# Plotly 2D interattivo
fig2d = make_subplots(rows=1, cols=2, column_widths=[0.72, 0.28],
    subplot_titles=[f"PC1 ({exp_var[0]:.1f}%) vs PC2 ({exp_var[1]:.1f}%)",
                    "Varianza spiegata"])
for cls in sorted(CLASS_COLORS.keys()):
    mask = y == cls
    fig2d.add_trace(go.Scatter(
        x=scores[mask,0], y=scores[mask,1], mode="markers",
        name=f"{cls} (n={mask.sum()})",
        marker=dict(size=9, color=CLASS_COLORS[cls], opacity=0.85,
                    line=dict(color="white", width=0.8)),
        text=[hover[i] for i in np.where(mask)[0]],
        hovertemplate="%{text}<extra></extra>"
    ), row=1, col=1)
fig2d.add_hline(y=0, line=dict(color="gray", dash="dash", width=0.8), row=1, col=1)
fig2d.add_vline(x=0, line=dict(color="gray", dash="dash", width=0.8), row=1, col=1)
fig2d.add_trace(go.Bar(
    x=[f"PC{i+1}" for i in range(n_show)], y=exp_var[:n_show],
    marker_color=["#4878CF"] + ["#BDBDBD"]*(n_show-1), showlegend=False,
    text=[f"{v:.1f}%" for v in exp_var[:n_show]], textposition="outside", textfont=dict(size=9)
), row=1, col=2)
fig2d.update_layout(
    title=dict(text=f"<b>PCA — Top {N_TOP} feature ANOVA — ELLONA/IREN</b>",
               x=0.5, font=dict(size=16)),
    legend=dict(title="Classe"), width=1200, height=600,
    paper_bgcolor="white", plot_bgcolor="#fafafa"
)
fig2d.update_xaxes(title_text=f"PC1 ({exp_var[0]:.1f}%)", row=1, col=1)
fig2d.update_yaxes(title_text=f"PC2 ({exp_var[1]:.1f}%)", row=1, col=1)
fig2d.write_html(os.path.join(OUT_DIR, "pca_2d_interactive.html"),
                 include_plotlyjs="cdn", full_html=True)
print("✓  pca_2d_interactive.html")

# ── Salva feature selezionate e scores ───────────────────────────────────────
with open(os.path.join(OUT_DIR, "anova_selected_features.txt"), "w") as f:
    f.write(f"# PCA ANOVA — Top {N_TOP} feature per F-statistic\n")
    for feat in selected:
        f.write(feat + "\n")

scores_df = pd.DataFrame(scores[:,:5], columns=[f"PC{i+1}" for i in range(5)])
scores_df.insert(0, "Classe2",   y)
scores_df.insert(1, "Sample.ID", sids)
scores_df.to_csv(os.path.join(OUT_DIR, "pca_results.csv"), sep=";", index=False)
print("✓  pca_results.csv")

print(f"\nVarianza spiegata:")
cum = 0
for i, v in enumerate(exp_var[:6]):
    cum += v
    print(f"  PC{i+1}: {v:5.1f}%  (cumulativa: {cum:5.1f}%)")
