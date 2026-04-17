# ==============================================================================
# PCA — ELLONA/IREN
# Input:  data/processed/TRAIN_FEATURES.csv + output/06_rfecv/rfecv_selected_features.txt
# Output: output/04_pca/pca_scores.png / pca_scree.png / pca_loadings.png
# ==============================================================================
# Richiede: install.packages("ggplot2")
# ==============================================================================

library(ggplot2)

setwd(normalizePath("~/Desktop/IREN"))

# ── Palette ────────────────────────────────────────────────────────────────────
CLASS_COLORS  <- c(ARIA="#4878CF", BIOFILTRO="#6ACC65", BIOGAS="#D65F5F",
                   FORSU="#B47CC7", PERCOLATO="#C4AD66")
CLASS_SHAPES  <- c(ARIA=16, BIOFILTRO=15, BIOGAS=17, FORSU=18, PERCOLATO=8)

out_dir <- "output/04_pca"
dir.create(out_dir, showWarnings=FALSE, recursive=TRUE)

# ── Carica feature selezionate ─────────────────────────────────────────────────
lines_raw <- readLines("output/06_rfecv/rfecv_selected_features.txt")
selected  <- lines_raw[!grepl("^#", lines_raw) & nchar(trimws(lines_raw)) > 0]
cat(sprintf("Feature selezionate: %d\n", length(selected)))

# ── Carica dati ───────────────────────────────────────────────────────────────
df   <- read.csv("data/processed/TRAIN_FEATURES.csv", sep=";", stringsAsFactors=FALSE)
y    <- df$Classe2
X    <- df[, selected, drop=FALSE]

# Imputa NA (mediana per colonna)
for (col in names(X)) {
    if (any(is.na(X[[col]])))
        X[[col]][is.na(X[[col]])] <- median(X[[col]], na.rm=TRUE)
}

# Standardizza
X_scaled <- scale(X)

# ── PCA ───────────────────────────────────────────────────────────────────────
pca_res  <- prcomp(X_scaled, center=FALSE, scale.=FALSE)
scores   <- as.data.frame(pca_res$x)
scores$Classe2   <- y
scores$Sample.ID <- df$Sample.ID

exp_var  <- (pca_res$sdev^2 / sum(pca_res$sdev^2)) * 100
cum_var  <- cumsum(exp_var)
n_comp_90 <- which(cum_var >= 90)[1]

cat(sprintf("\nPC1: %.1f%%  |  PC2: %.1f%%  |  PC3: %.1f%%\n",
            exp_var[1], exp_var[2], exp_var[3]))
cat(sprintf("Componenti per 90%% varianza: %d\n", n_comp_90))

# ─────────────────────────────────────────────────────────────────────────────
# PLOT 1: Scree plot
# ─────────────────────────────────────────────────────────────────────────────
scree_df <- data.frame(
    PC      = 1:min(15, length(exp_var)),
    ExpVar  = exp_var[1:min(15, length(exp_var))],
    CumVar  = cum_var[1:min(15, length(exp_var))]
)

p_scree <- ggplot(scree_df, aes(x=PC, y=ExpVar)) +
    geom_bar(stat="identity", fill="#4878CF", alpha=0.85, width=0.7) +
    geom_line(aes(y=CumVar), color="#D65F5F", linewidth=1, linetype="solid") +
    geom_point(aes(y=CumVar), color="#D65F5F", size=2.5) +
    geom_hline(yintercept=90, linetype="dashed", color="gray50", linewidth=0.8) +
    geom_text(aes(label=sprintf("%.1f%%", ExpVar)), vjust=-0.5, size=3) +
    scale_x_continuous(breaks=1:15) +
    scale_y_continuous(limits=c(0, 105), sec.axis=sec_axis(~., name="Varianza cumulativa (%)")) +
    labs(title="Scree Plot — PCA ELLONA/IREN",
         x="Componente principale",
         y="Varianza spiegata (%)") +
    theme_minimal(base_size=11)

ggsave(file.path(out_dir, "pca_scree.png"), p_scree, width=10, height=5, dpi=150)
cat("✓  pca_scree.png\n")

# ─────────────────────────────────────────────────────────────────────────────
# PLOT 2: PC1 vs PC2 con ellissi di confidenza (95%)
# ─────────────────────────────────────────────────────────────────────────────
p_scores <- ggplot(scores, aes(x=PC1, y=PC2, color=Classe2, shape=Classe2)) +
    stat_ellipse(aes(fill=Classe2), type="norm", level=0.95,
                 geom="polygon", alpha=0.10, linewidth=0.8) +
    geom_point(size=3, alpha=0.9) +
    geom_hline(yintercept=0, color="gray70", linewidth=0.4, linetype="dashed") +
    geom_vline(xintercept=0, color="gray70", linewidth=0.4, linetype="dashed") +
    scale_color_manual(values=CLASS_COLORS) +
    scale_fill_manual(values=CLASS_COLORS) +
    scale_shape_manual(values=CLASS_SHAPES) +
    labs(title="PCA — ELLONA/IREN  (ellissi 95%)",
         x=sprintf("PC1 (%.1f%%)", exp_var[1]),
         y=sprintf("PC2 (%.1f%%)", exp_var[2]),
         color="Classe", shape="Classe", fill="Classe") +
    theme_minimal(base_size=12) +
    theme(legend.position="right",
          panel.grid.minor=element_blank())

ggsave(file.path(out_dir, "pca_scores.png"), p_scores, width=9, height=7, dpi=150)
cat("✓  pca_scores.png\n")

# ─────────────────────────────────────────────────────────────────────────────
# PLOT 3: Loadings PC1 vs PC2 — cerchio delle correlazioni
# ─────────────────────────────────────────────────────────────────────────────
loadings_df <- data.frame(
    Feature = selected,
    Load1   = pca_res$rotation[, 1],
    Load2   = pca_res$rotation[, 2],
    Contrib = sqrt(pca_res$rotation[, 1]^2 + pca_res$rotation[, 2]^2)
)
# Tutte le feature selezionate
top_load <- loadings_df[order(-loadings_df$Contrib), ]

circle_pts <- data.frame(
    x = cos(seq(0, 2*pi, length.out=200)),
    y = sin(seq(0, 2*pi, length.out=200))
)

p_load <- ggplot(top_load) +
    geom_path(data=circle_pts, aes(x=x, y=y),
              color="gray60", linetype="dashed", linewidth=0.7) +
    geom_segment(aes(x=0, y=0, xend=Load1, yend=Load2),
                 arrow=arrow(length=unit(0.25,"cm"), type="closed"),
                 color="#4878CF", linewidth=0.9, alpha=0.85) +
    geom_text(aes(x=Load1*1.12, y=Load2*1.12, label=Feature),
              size=3.2, color="#222222", hjust=0.5, vjust=0.5) +
    geom_hline(yintercept=0, color="gray70", linewidth=0.4) +
    geom_vline(xintercept=0, color="gray70", linewidth=0.4) +
    coord_fixed(xlim=c(-1.15, 1.15), ylim=c(-1.15, 1.15)) +
    labs(title=sprintf("Cerchio delle correlazioni — %d feature RFECV", length(selected)),
         x=sprintf("PC1 (%.1f%%)", exp_var[1]),
         y=sprintf("PC2 (%.1f%%)", exp_var[2])) +
    theme_minimal(base_size=11)

ggsave(file.path(out_dir, "pca_loadings.png"), p_load, width=8, height=8, dpi=150)
cat("✓  pca_loadings.png\n")

# ─────────────────────────────────────────────────────────────────────────────
# PLOT 4: PC1 vs PC3 (vista alternativa)
# ─────────────────────────────────────────────────────────────────────────────
p_13 <- ggplot(scores, aes(x=PC1, y=PC3, color=Classe2, shape=Classe2)) +
    stat_ellipse(aes(fill=Classe2), type="norm", level=0.95,
                 geom="polygon", alpha=0.10, linewidth=0.8) +
    geom_point(size=3, alpha=0.9) +
    geom_hline(yintercept=0, color="gray70", linewidth=0.4, linetype="dashed") +
    geom_vline(xintercept=0, color="gray70", linewidth=0.4, linetype="dashed") +
    scale_color_manual(values=CLASS_COLORS) +
    scale_fill_manual(values=CLASS_COLORS) +
    scale_shape_manual(values=CLASS_SHAPES) +
    labs(title="PCA PC1 vs PC3 — ELLONA/IREN",
         x=sprintf("PC1 (%.1f%%)", exp_var[1]),
         y=sprintf("PC3 (%.1f%%)", exp_var[3]),
         color="Classe", shape="Classe", fill="Classe") +
    theme_minimal(base_size=12)

ggsave(file.path(out_dir, "pca_scores_PC1_PC3.png"), p_13, width=9, height=7, dpi=150)
cat("✓  pca_scores_PC1_PC3.png\n")

# ─────────────────────────────────────────────────────────────────────────────
# Salva scores
# ─────────────────────────────────────────────────────────────────────────────
out_df <- cbind(
    data.frame(Classe2=y, Sample.ID=df$Sample.ID),
    as.data.frame(pca_res$x[, 1:5])
)
write.table(out_df, file.path(out_dir, "pca_results.csv"), sep=";", row.names=FALSE, quote=FALSE)
cat("✓  pca_results.csv\n")

# Summary varianza
cat(sprintf("\nVarianza spiegata:\n"))
for (i in 1:min(8, length(exp_var))) {
    cat(sprintf("  PC%d: %5.1f%%  (cumulativa: %5.1f%%)\n", i, exp_var[i], cum_var[i]))
}
