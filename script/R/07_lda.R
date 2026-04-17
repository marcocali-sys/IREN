# ==============================================================================
# LDA — ELLONA/IREN
# Linear Discriminant Analysis (supervisionata): massimizza separazione classi.
# Input:  data/processed/TRAIN_FEATURES.csv
#         output/06_rfecv/rfecv_selected_features.txt
# Output: output/07_lda/lda_scores.png / lda_loadings.png / lda_results.csv
# ==============================================================================
# Richiede: install.packages(c("MASS","ggplot2"))
# ==============================================================================

library(MASS)
library(ggplot2)

setwd(normalizePath("~/Desktop/IREN"))

out_dir <- "output/07_lda"
dir.create(out_dir, showWarnings=FALSE, recursive=TRUE)

CLASS_COLORS <- c(ARIA="#4878CF", BIOFILTRO="#6ACC65", BIOGAS="#D65F5F",
                  FORSU="#B47CC7", PERCOLATO="#C4AD66")
CLASS_SHAPES  <- c(ARIA=16, BIOFILTRO=15, BIOGAS=17, FORSU=18, PERCOLATO=8)

# ── Carica feature selezionate ─────────────────────────────────────────────────
lines_raw <- readLines("output/06_rfecv/rfecv_selected_features.txt")
selected  <- lines_raw[!grepl("^#", lines_raw) & nchar(trimws(lines_raw)) > 0]
cat(sprintf("Feature: %d\n", length(selected)))

# ── Carica dati ───────────────────────────────────────────────────────────────
df   <- read.csv("data/processed/TRAIN_FEATURES.csv", sep=";", stringsAsFactors=FALSE)
y    <- df$Classe2
X    <- df[, selected, drop=FALSE]

# Imputa NA (mediana)
for (col in names(X)) {
    if (any(is.na(X[[col]])))
        X[[col]][is.na(X[[col]])] <- median(X[[col]], na.rm=TRUE)
}
X_scaled <- as.data.frame(scale(X))

# ── LDA ───────────────────────────────────────────────────────────────────────
lda_data <- cbind(Classe2=y, X_scaled)
lda_res  <- lda(Classe2 ~ ., data=lda_data)

# Scores
scores   <- as.data.frame(predict(lda_res, X_scaled)$x)
scores$Classe2   <- y
scores$Sample.ID <- df$Sample.ID

# Varianza spiegata (proporzionale a svd^2)
svd_vals <- lda_res$svd
exp_var  <- (svd_vals^2 / sum(svd_vals^2)) * 100
cat(sprintf("\nLD1: %.1f%%  |  LD2: %.1f%%  |  LD3: %.1f%%\n",
            exp_var[1], exp_var[2], exp_var[3]))
cat(sprintf("Cumulativa LD1+LD2: %.1f%%\n", exp_var[1]+exp_var[2]))

n_ld <- ncol(scores) - 2   # esclude Classe2 e Sample.ID

# ─────────────────────────────────────────────────────────────────────────────
# PLOT 1: LD1 vs LD2 con ellissi 95%
# ─────────────────────────────────────────────────────────────────────────────
p1 <- ggplot(scores, aes(x=LD1, y=LD2, color=Classe2, shape=Classe2)) +
    stat_ellipse(aes(fill=Classe2), type="norm", level=0.95,
                 geom="polygon", alpha=0.10, linewidth=0.8) +
    geom_point(size=3, alpha=0.9) +
    geom_hline(yintercept=0, color="gray70", linewidth=0.4, linetype="dashed") +
    geom_vline(xintercept=0, color="gray70", linewidth=0.4, linetype="dashed") +
    scale_color_manual(values=CLASS_COLORS) +
    scale_fill_manual(values=CLASS_COLORS) +
    scale_shape_manual(values=CLASS_SHAPES) +
    labs(title="LDA — ELLONA/IREN  (ellissi 95%)",
         x=sprintf("LD1 (%.1f%%)", exp_var[1]),
         y=sprintf("LD2 (%.1f%%)", exp_var[2]),
         color="Classe", shape="Classe", fill="Classe") +
    theme_minimal(base_size=12) +
    theme(legend.position="right", panel.grid.minor=element_blank())

ggsave(file.path(out_dir, "lda_scores.png"), p1, width=9, height=7, dpi=150)
cat("✓  lda_scores.png\n")

# ─────────────────────────────────────────────────────────────────────────────
# PLOT 2: LD1 vs LD3 (se disponibile)
# ─────────────────────────────────────────────────────────────────────────────
if (n_ld >= 3) {
    p13 <- ggplot(scores, aes(x=LD1, y=LD3, color=Classe2, shape=Classe2)) +
        stat_ellipse(aes(fill=Classe2), type="norm", level=0.95,
                     geom="polygon", alpha=0.10, linewidth=0.8) +
        geom_point(size=3, alpha=0.9) +
        geom_hline(yintercept=0, color="gray70", linewidth=0.4, linetype="dashed") +
        geom_vline(xintercept=0, color="gray70", linewidth=0.4, linetype="dashed") +
        scale_color_manual(values=CLASS_COLORS) +
        scale_fill_manual(values=CLASS_COLORS) +
        scale_shape_manual(values=CLASS_SHAPES) +
        labs(title="LDA LD1 vs LD3 — ELLONA/IREN",
             x=sprintf("LD1 (%.1f%%)", exp_var[1]),
             y=sprintf("LD3 (%.1f%%)", exp_var[3]),
             color="Classe", shape="Classe", fill="Classe") +
        theme_minimal(base_size=12)

    ggsave(file.path(out_dir, "lda_scores_LD1_LD3.png"), p13, width=9, height=7, dpi=150)
    cat("✓  lda_scores_LD1_LD3.png\n")
}

# ─────────────────────────────────────────────────────────────────────────────
# PLOT 3: Coefficienti discriminanti (LD1 e LD2)
# ─────────────────────────────────────────────────────────────────────────────
# lda_res$scaling: matrice (n_features x n_ld) dei coefficienti
scalings <- as.data.frame(lda_res$scaling)
scalings$Feature <- rownames(scalings)

# LD1
ld1_df <- scalings[order(abs(scalings$LD1), decreasing=TRUE), ]
ld1_df$Feature <- factor(ld1_df$Feature, levels=rev(ld1_df$Feature))
ld1_df$Dir <- ifelse(ld1_df$LD1 >= 0, "pos", "neg")

p_ld1 <- ggplot(ld1_df, aes(x=LD1, y=Feature, fill=Dir)) +
    geom_bar(stat="identity", alpha=0.85, width=0.7) +
    geom_vline(xintercept=0, color="gray50", linewidth=0.8) +
    scale_fill_manual(values=c(pos="#4878CF", neg="#D65F5F"), guide="none") +
    labs(title=sprintf("Coefficienti LD1 (%.1f%%)", exp_var[1]),
         x="Scaling coefficient", y=NULL) +
    theme_minimal(base_size=11) +
    theme(panel.grid.minor=element_blank())

# LD2
ld2_df <- scalings[order(abs(scalings$LD2), decreasing=TRUE), ]
ld2_df$Feature <- factor(ld2_df$Feature, levels=rev(ld2_df$Feature))
ld2_df$Dir <- ifelse(ld2_df$LD2 >= 0, "pos", "neg")

p_ld2 <- ggplot(ld2_df, aes(x=LD2, y=Feature, fill=Dir)) +
    geom_bar(stat="identity", alpha=0.85, width=0.7) +
    geom_vline(xintercept=0, color="gray50", linewidth=0.8) +
    scale_fill_manual(values=c(pos="#4878CF", neg="#D65F5F"), guide="none") +
    labs(title=sprintf("Coefficienti LD2 (%.1f%%)", exp_var[2]),
         x="Scaling coefficient", y=NULL) +
    theme_minimal(base_size=11) +
    theme(panel.grid.minor=element_blank())

# Unisci in unica figura con cowplot (oppure patchwork)
# Fallback senza librerie esterne: salva separati
ggsave(file.path(out_dir, "lda_loadings_LD1.png"), p_ld1, width=7, height=5, dpi=150)
ggsave(file.path(out_dir, "lda_loadings_LD2.png"), p_ld2, width=7, height=5, dpi=150)
cat("✓  lda_loadings_LD1.png\n")
cat("✓  lda_loadings_LD2.png\n")

# ─────────────────────────────────────────────────────────────────────────────
# Salva scores
# ─────────────────────────────────────────────────────────────────────────────
ld_cols <- paste0("LD", 1:n_ld)
out_df  <- cbind(
    data.frame(Classe2=y, Sample.ID=df$Sample.ID),
    scores[, ld_cols]
)
write.table(out_df, file.path(out_dir, "lda_results.csv"),
            sep=";", row.names=FALSE, quote=FALSE)
cat("✓  lda_results.csv\n")

cat(sprintf("\nVarianza spiegata:\n"))
cum <- 0
for (i in seq_along(exp_var)) {
    cum <- cum + exp_var[i]
    cat(sprintf("  LD%d: %5.1f%%  (cumulativa: %5.1f%%)\n", i, exp_var[i], cum))
}
