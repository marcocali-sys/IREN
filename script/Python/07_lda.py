"""
LDA — ELLONA/IREN
Linear Discriminant Analysis (supervisionata): massimizza separazione tra classi.
Input:  data/processed/TRAIN_FEATURES.csv + output/06_rfecv/rfecv_selected_features.txt
Output: output/07_lda/lda_scores.png       (LD1 vs LD2, ellissi 95%)
        output/07_lda/lda_scores_LD1_LD3.png
        output/07_lda/lda_3d.png           (LD1 vs LD2 vs LD3)
        output/07_lda/lda_3d_interactive.html
        output/07_lda/lda_2d_interactive.html
        output/07_lda/lda_loadings.png     (coefficienti discriminanti)
        output/07_lda/lda_results.csv
"""

import os
import pandas as pd
import numpy as np
from sklearn.discriminant_analysis import LinearDiscriminantAnalysis
from sklearn.preprocessing import StandardScaler
from sklearn.impute import SimpleImputer
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import Ellipse
import matplotlib.transforms as transforms
import plotly.graph_objects as go
from plotly.subplots import make_subplots

# ── Parametri ──────────────────────────────────────────────────────────────────
TRAIN_FILE = "data/processed/TRAIN_FEATURES.csv"
FEAT_FILE  = "output/06_rfecv/rfecv_selected_features.txt"
OUT_DIR    = "output/07_lda"

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

# ── Carica feature selezionate ────────────────────────────────────────────────
with open(FEAT_FILE) as f:
    selected = [l.strip() for l in f if l.strip() and not l.startswith("#")]
print(f"Feature: {len(selected)}: {', '.join(selected)}")

# ── Carica dati ───────────────────────────────────────────────────────────────
df    = pd.read_csv(TRAIN_FILE, sep=";")
y     = df["Classe2"].values
sids  = df["Sample.ID"].values
X_raw = df[selected].values

X = SimpleImputer(strategy="median").fit_transform(X_raw)
X = StandardScaler().fit_transform(X)

# ── LDA ───────────────────────────────────────────────────────────────────────
lda     = LinearDiscriminantAnalysis()
scores  = lda.fit_transform(X, y)           # shape: (n, n_classes-1) = (138, 4)
exp_var = lda.explained_variance_ratio_ * 100
n_comp  = scores.shape[1]

print(f"\nLD1: {exp_var[0]:.1f}%  |  LD2: {exp_var[1]:.1f}%  |  LD3: {exp_var[2]:.1f}%")
print(f"Varianza cumulativa LD1+LD2: {exp_var[0]+exp_var[1]:.1f}%")
print(f"Varianza cumulativa LD1+LD2+LD3: {exp_var[0]+exp_var[1]+exp_var[2]:.1f}%")

classes = sorted(CLASS_COLORS.keys())

# ── Helper: ellisse di confidenza 95% ─────────────────────────────────────────
def confidence_ellipse(x, y_arr, ax, n_std=2.0, **kwargs):
    if len(x) < 3:
        return
    cov     = np.cov(x, y_arr)
    pearson = cov[0, 1] / np.sqrt(cov[0, 0] * cov[1, 1])
    rx = np.sqrt(1 + pearson)
    ry = np.sqrt(1 - pearson)
    ell = Ellipse((0, 0), width=rx * 2, height=ry * 2, **kwargs)
    sx = np.sqrt(cov[0, 0]) * n_std
    sy = np.sqrt(cov[1, 1]) * n_std
    t  = transforms.Affine2D().rotate_deg(45).scale(sx, sy).translate(np.mean(x), np.mean(y_arr))
    ell.set_transform(t + ax.transData)
    ax.add_patch(ell)

# ──────────────────────────────────────────────────────────────────────────────
# PLOT 1: LD1 vs LD2
# ──────────────────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(9, 7))

for cls in classes:
    mask = y == cls
    if mask.sum() == 0:
        continue
    ax.scatter(scores[mask, 0], scores[mask, 1],
               c=CLASS_COLORS[cls], marker=CLASS_MARKERS[cls],
               s=70, alpha=0.85, edgecolors="white", linewidths=0.5,
               label=f"{cls} (n={mask.sum()})")
    confidence_ellipse(scores[mask, 0], scores[mask, 1], ax,
                       n_std=2.0,
                       edgecolor=CLASS_COLORS[cls],
                       facecolor=CLASS_COLORS[cls],
                       alpha=0.12, linewidth=1.5)

ax.axhline(0, color="gray", linewidth=0.5, linestyle="--")
ax.axvline(0, color="gray", linewidth=0.5, linestyle="--")
ax.set_xlabel(f"LD1 ({exp_var[0]:.1f}%)", fontsize=12)
ax.set_ylabel(f"LD2 ({exp_var[1]:.1f}%)", fontsize=12)
ax.set_title("LDA — ELLONA/IREN  (ellissi 95%)", fontsize=13)
ax.legend(loc="best", framealpha=0.9, fontsize=9)
ax.grid(alpha=0.2)
plt.tight_layout()
plt.savefig(os.path.join(OUT_DIR, "lda_scores.png"), dpi=150)
plt.close()
print("✓  lda_scores.png")

# ──────────────────────────────────────────────────────────────────────────────
# PLOT 2: LD1 vs LD3
# ──────────────────────────────────────────────────────────────────────────────
if n_comp >= 3:
    fig, ax = plt.subplots(figsize=(9, 7))
    for cls in classes:
        mask = y == cls
        if mask.sum() == 0:
            continue
        ax.scatter(scores[mask, 0], scores[mask, 2],
                   c=CLASS_COLORS[cls], marker=CLASS_MARKERS[cls],
                   s=70, alpha=0.85, edgecolors="white", linewidths=0.5,
                   label=f"{cls} (n={mask.sum()})")
        confidence_ellipse(scores[mask, 0], scores[mask, 2], ax,
                           n_std=2.0,
                           edgecolor=CLASS_COLORS[cls],
                           facecolor=CLASS_COLORS[cls],
                           alpha=0.12, linewidth=1.5)

    ax.axhline(0, color="gray", linewidth=0.5, linestyle="--")
    ax.axvline(0, color="gray", linewidth=0.5, linestyle="--")
    ax.set_xlabel(f"LD1 ({exp_var[0]:.1f}%)", fontsize=12)
    ax.set_ylabel(f"LD3 ({exp_var[2]:.1f}%)", fontsize=12)
    ax.set_title("LDA LD1 vs LD3 — ELLONA/IREN", fontsize=13)
    ax.legend(loc="best", framealpha=0.9, fontsize=9)
    ax.grid(alpha=0.2)
    plt.tight_layout()
    plt.savefig(os.path.join(OUT_DIR, "lda_scores_LD1_LD3.png"), dpi=150)
    plt.close()
    print("✓  lda_scores_LD1_LD3.png")

# ──────────────────────────────────────────────────────────────────────────────
# PLOT 3: 3D statico LD1 vs LD2 vs LD3
# ──────────────────────────────────────────────────────────────────────────────
if n_comp >= 3:
    from mpl_toolkits.mplot3d import Axes3D  # noqa
    fig = plt.figure(figsize=(10, 7))
    ax3 = fig.add_subplot(111, projection="3d")
    for cls in classes:
        mask = y == cls
        if mask.sum() == 0:
            continue
        ax3.scatter(scores[mask, 0], scores[mask, 1], scores[mask, 2],
                    c=CLASS_COLORS[cls], marker=CLASS_MARKERS[cls],
                    s=50, alpha=0.85, edgecolors="white", linewidths=0.3,
                    label=cls)
    ax3.set_xlabel(f"LD1 ({exp_var[0]:.1f}%)", fontsize=9)
    ax3.set_ylabel(f"LD2 ({exp_var[1]:.1f}%)", fontsize=9)
    ax3.set_zlabel(f"LD3 ({exp_var[2]:.1f}%)", fontsize=9)
    ax3.set_title("LDA 3D — ELLONA/IREN", fontsize=12)
    ax3.legend(loc="upper left", fontsize=8, framealpha=0.8)
    plt.tight_layout()
    plt.savefig(os.path.join(OUT_DIR, "lda_3d.png"), dpi=150)
    plt.close()
    print("✓  lda_3d.png")

# ──────────────────────────────────────────────────────────────────────────────
# PLOT 4: Coefficienti discriminanti (contributo di ogni feature a LD1 e LD2)
# ──────────────────────────────────────────────────────────────────────────────
coef = lda.coef_           # (n_classes, n_features)
# Proiezione media: peso di ogni feature su LD1 e LD2
# lda.scalings_ = matrice delle direzioni discriminanti (n_features, n_comp)
scalings = lda.scalings_   # (n_features, n_comp)

fig, axes = plt.subplots(1, 2, figsize=(14, 5))

for ax_i, (ld_idx, ld_name) in enumerate([(0, "LD1"), (1, "LD2")]):
    vals = scalings[:, ld_idx]
    order = np.argsort(np.abs(vals))[::-1]
    colors = ["#4878CF" if v >= 0 else "#D65F5F" for v in vals[order]]
    axes[ax_i].barh([selected[i] for i in order], vals[order],
                    color=colors, alpha=0.85, edgecolor="white")
    axes[ax_i].axvline(0, color="gray", linewidth=0.8)
    axes[ax_i].set_title(f"Coefficienti {ld_name} ({exp_var[ld_idx]:.1f}%)", fontsize=11)
    axes[ax_i].set_xlabel("Scaling coefficient")
    axes[ax_i].grid(axis="x", alpha=0.3)
    axes[ax_i].invert_yaxis()

plt.suptitle("LDA — Contributo feature a LD1 e LD2", fontsize=13, y=1.01)
plt.tight_layout()
plt.savefig(os.path.join(OUT_DIR, "lda_loadings.png"), dpi=150, bbox_inches="tight")
plt.close()
print("✓  lda_loadings.png")

# ──────────────────────────────────────────────────────────────────────────────
# PLOT 5: 3D interattivo Plotly
# ──────────────────────────────────────────────────────────────────────────────
hover = [
    f"<b>{cls}</b><br>Sample.ID: {sid}<br>"
    f"LD1: {s1:.2f}<br>LD2: {s2:.2f}" + (f"<br>LD3: {s3:.2f}" if n_comp >= 3 else "")
    for cls, sid, s1, s2, s3 in zip(
        y, sids, scores[:, 0], scores[:, 1],
        scores[:, 2] if n_comp >= 3 else np.zeros(len(y))
    )
]

fig3d = go.Figure()
for cls in sorted(CLASS_COLORS.keys()):
    mask = y == cls
    fig3d.add_trace(go.Scatter3d(
        x=scores[mask, 0],
        y=scores[mask, 1],
        z=scores[mask, 2] if n_comp >= 3 else np.zeros(mask.sum()),
        mode="markers",
        name=f"{cls} (n={mask.sum()})",
        marker=dict(size=6, color=CLASS_COLORS[cls],
                    symbol=CLASS_SYMBOLS_3D[cls], opacity=0.85,
                    line=dict(color="white", width=0.5)),
        text=[hover[i] for i in np.where(mask)[0]],
        hovertemplate="%{text}<extra></extra>"
    ))

fig3d.update_layout(
    title=dict(
        text="<b>LDA 3D — ELLONA/IREN</b><br>"
             f"<sup>LD1={exp_var[0]:.1f}%  LD2={exp_var[1]:.1f}%  LD3={exp_var[2]:.1f}%  "
             f"[totale {exp_var[0]+exp_var[1]+exp_var[2]:.1f}%]</sup>",
        x=0.5),
    scene=dict(
        xaxis_title=f"LD1 ({exp_var[0]:.1f}%)",
        yaxis_title=f"LD2 ({exp_var[1]:.1f}%)",
        zaxis_title=f"LD3 ({exp_var[2]:.1f}%)" if n_comp >= 3 else "LD3",
        xaxis=dict(backgroundcolor="#f8f8f8", gridcolor="white"),
        yaxis=dict(backgroundcolor="#f0f0f0", gridcolor="white"),
        zaxis=dict(backgroundcolor="#e8e8e8", gridcolor="white"),
        camera=dict(eye=dict(x=1.5, y=1.5, z=1.0))
    ),
    legend=dict(title="Classe", itemsizing="constant", font=dict(size=12)),
    margin=dict(l=0, r=0, t=80, b=0),
    width=1000, height=750,
    paper_bgcolor="white"
)
fig3d.write_html(os.path.join(OUT_DIR, "lda_3d_interactive.html"),
                 include_plotlyjs="cdn", full_html=True)
print("✓  lda_3d_interactive.html")

# ──────────────────────────────────────────────────────────────────────────────
# PLOT 6: 2D interattivo + varianza spiegata
# ──────────────────────────────────────────────────────────────────────────────
fig2d = make_subplots(
    rows=1, cols=2, column_widths=[0.72, 0.28],
    subplot_titles=[
        f"LD1 ({exp_var[0]:.1f}%) vs LD2 ({exp_var[1]:.1f}%)",
        "Varianza spiegata"
    ]
)

for cls in sorted(CLASS_COLORS.keys()):
    mask = y == cls
    fig2d.add_trace(go.Scatter(
        x=scores[mask, 0], y=scores[mask, 1],
        mode="markers",
        name=f"{cls} (n={mask.sum()})",
        marker=dict(size=9, color=CLASS_COLORS[cls], opacity=0.85,
                    line=dict(color="white", width=0.8)),
        text=[hover[i] for i in np.where(mask)[0]],
        hovertemplate="%{text}<extra></extra>"
    ), row=1, col=1)

fig2d.add_hline(y=0, line=dict(color="gray", dash="dash", width=0.8), row=1, col=1)
fig2d.add_vline(x=0, line=dict(color="gray", dash="dash", width=0.8), row=1, col=1)

n_ld = len(exp_var)
fig2d.add_trace(go.Bar(
    x=[f"LD{i+1}" for i in range(n_ld)],
    y=exp_var,
    marker_color=[CLASS_COLORS["ARIA"]] + ["#BDBDBD"] * (n_ld - 1),
    name="Var. spiegata", showlegend=False,
    text=[f"{v:.1f}%" for v in exp_var], textposition="outside",
    textfont=dict(size=9)
), row=1, col=2)

fig2d.update_layout(
    title=dict(text="<b>LDA 2D — ELLONA/IREN</b>", x=0.5, font=dict(size=16)),
    legend=dict(title="Classe", itemsizing="constant"),
    width=1200, height=600,
    paper_bgcolor="white", plot_bgcolor="#fafafa"
)
fig2d.update_xaxes(title_text=f"LD1 ({exp_var[0]:.1f}%)", row=1, col=1, zeroline=False)
fig2d.update_yaxes(title_text=f"LD2 ({exp_var[1]:.1f}%)", row=1, col=1, zeroline=False)
fig2d.update_xaxes(title_text="Componente", row=1, col=2)
fig2d.update_yaxes(title_text="Varianza (%)", row=1, col=2)

fig2d.write_html(os.path.join(OUT_DIR, "lda_2d_interactive.html"),
                 include_plotlyjs="cdn", full_html=True)
print("✓  lda_2d_interactive.html")

# ── Salva scores ──────────────────────────────────────────────────────────────
cols = {f"LD{i+1}": scores[:, i] for i in range(n_comp)}
out  = pd.DataFrame({"Classe2": y, "Sample.ID": sids, **cols})
out.to_csv(os.path.join(OUT_DIR, "lda_results.csv"), sep=";", index=False)
print("✓  lda_results.csv")

print(f"\nVarianza spiegata:")
cum = 0
for i, v in enumerate(exp_var):
    cum += v
    print(f"  LD{i+1}: {v:5.1f}%  (cumulativa: {cum:5.1f}%)")
