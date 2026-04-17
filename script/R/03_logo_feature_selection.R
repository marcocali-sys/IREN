# ==============================================================================
# LOGO-CV Feature Selection — ELLONA/IREN
# - Legge le feature Boruta-confirmed da boruta_results.csv
# - Leave-One-Group-Out CV con gruppi = Sample.ID
# - Per ogni fold: allena RF (ranger), registra importanza feature
# - Output: importanza media ± std su tutti i fold
#           selezione finale per soglia (mean > grand_mean)
# ==============================================================================
# Richiede: install.packages(c("ranger", "ggplot2"))
# ==============================================================================

library(ranger)
library(ggplot2)

setwd(normalizePath("~/Desktop/IREN"))

# ── Parametri ──────────────────────────────────────────────────────────────────
TRAIN_FILE    <- "TRAIN_FEATURES.csv"
BORUTA_FILE   <- "boruta_results.csv"
RESULTS_FILE  <- "logo_feature_importance.csv"
SELECTED_FILE <- "logo_selected_features.txt"
PLOT_FILE     <- "logo_importance.png"
RANDOM_SEED   <- 42
N_TREES       <- 500
# ──────────────────────────────────────────────────────────────────────────────

META_COLS <- c("Data.analisi", "Classe", "Classe2", "Diluizione", "Cod",
               "Step1", "Step2", "Step3", "Sample.ID", "Sample.number",
               "Datetime_inizio", "Datetime_fine")

# ── Carica feature Boruta-confirmed ───────────────────────────────────────────
boruta_df      <- read.csv(BORUTA_FILE, sep = ";", stringsAsFactors = FALSE)
confirmed_feats <- boruta_df$Feature[boruta_df$Status == "Confirmed"]
cat(sprintf("Feature Boruta-confirmed: %d\n", length(confirmed_feats)))

# ── Carica training set ───────────────────────────────────────────────────────
df     <- read.csv(TRAIN_FILE, sep = ";", stringsAsFactors = FALSE)
groups <- df$Sample.ID
y      <- as.factor(df$Classe2)
X      <- df[, confirmed_feats, drop = FALSE]

cat(sprintf("Training set: %d campioni, %d feature\n", nrow(df), length(confirmed_feats)))

# Imputazione NA (mediana per colonna)
for (col in names(X)) {
    if (any(is.na(X[[col]]))) {
        X[[col]][is.na(X[[col]])] <- median(X[[col]], na.rm = TRUE)
    }
}

unique_groups <- unique(groups)
n_folds       <- length(unique_groups)
n_feat        <- length(confirmed_feats)
cat(sprintf("Gruppi (Sample.ID): %d unici → %d fold LOGO\n\n", n_folds, n_folds))

# ── LOGO-CV ───────────────────────────────────────────────────────────────────
imp_matrix   <- matrix(0, nrow = n_folds, ncol = n_feat,
                       dimnames = list(NULL, confirmed_feats))
acc_per_fold <- numeric(n_folds)

set.seed(RANDOM_SEED)
cat(sprintf("Avvio LOGO-CV (%d fold)...\n", n_folds))

for (i in seq_along(unique_groups)) {
    g         <- unique_groups[i]
    test_mask <- groups == g
    train_mask <- !test_mask

    X_tr <- X[train_mask, , drop = FALSE]
    X_te <- X[test_mask,  , drop = FALSE]
    y_tr <- y[train_mask]
    y_te <- y[test_mask]

    # Costruisce data.frame per ranger
    train_df_fold <- cbind(X_tr, Classe2 = y_tr)

    rf_fold <- ranger(
        Classe2 ~ .,
        data             = train_df_fold,
        num.trees        = N_TREES,
        importance       = "impurity",
        seed             = RANDOM_SEED,
        num.threads      = parallel::detectCores()
    )

    imp_matrix[i, ] <- rf_fold$variable.importance

    # Accuratezza su test fold
    preds <- predict(rf_fold, data = X_te)$predictions
    acc   <- mean(preds == y_te)
    acc_per_fold[i] <- acc

    cls_left <- paste(unique(as.character(y_te)), collapse = "/")
    cat(sprintf("  Fold %2d/%d | Group=%3d (%-12s) | Acc=%.2f\n",
                i, n_folds, g, cls_left, acc))
}

cat(sprintf("\nAccuratezza media LOGO: %.3f ± %.3f\n",
            mean(acc_per_fold), sd(acc_per_fold)))

# ── Aggregazione importanze ───────────────────────────────────────────────────
mean_imp  <- colMeans(imp_matrix)
std_imp   <- apply(imp_matrix, 2, sd)

# Frequenza top 50%: % fold in cui la feature è sopra la mediana del fold
top50_freq <- apply(imp_matrix, 1, function(row) {
    thresh <- median(row)
    as.integer(row >= thresh)
})
top50_freq <- rowMeans(top50_freq)  # ora n_feat elementi

grand_mean <- mean(mean_imp)
selected   <- mean_imp > grand_mean

results_df <- data.frame(
    Feature         = confirmed_feats,
    MeanImportance  = mean_imp,
    StdImportance   = std_imp,
    Top50pct_freq   = top50_freq,
    Selected        = selected,
    stringsAsFactors = FALSE
)
results_df <- results_df[order(-results_df$MeanImportance), ]
results_df$Rank <- seq_len(nrow(results_df))
rownames(results_df) <- NULL

# ── Report console ─────────────────────────────────────────────────────────────
cat(sprintf("\n%s\n", strrep("=", 65)))
cat(sprintf("  LOGO-CV Feature Ranking (soglia: mean > %.5f)\n", grand_mean))
cat(sprintf("%s\n", strrep("=", 65)))
cat(sprintf("  %3s  %-15s %9s %8s %7s %5s\n",
            "Rk", "Feature", "MeanImp", "StdImp", "Top50%", "Sel"))
cat(sprintf("  %s\n", strrep("-", 55)))
for (i in seq_len(nrow(results_df))) {
    r    <- results_df[i, ]
    mark <- if (r$Selected) "✓" else " "
    cat(sprintf("  %3d  %-15s %9.5f %8.5f %7s %5s\n",
                r$Rank, r$Feature,
                r$MeanImportance, r$StdImportance,
                sprintf("%.1f%%", r$Top50pct_freq * 100),
                mark))
}

n_sel <- sum(selected)
cat(sprintf("\n  Feature selezionate: %d / %d\n", n_sel, n_feat))
cat(sprintf("  Feature scartate:    %d / %d\n", n_feat - n_sel, n_feat))

# ── Plot ───────────────────────────────────────────────────────────────────────
results_df$Color <- ifelse(results_df$Selected, "#2196F3", "#BDBDBD")
results_df$Feature <- factor(results_df$Feature,
                              levels = results_df$Feature[order(-results_df$MeanImportance)])

p <- ggplot(results_df, aes(x = Feature, y = MeanImportance, fill = Color)) +
    geom_bar(stat = "identity") +
    geom_errorbar(aes(ymin = MeanImportance - StdImportance,
                      ymax = MeanImportance + StdImportance),
                  width = 0.4, linewidth = 0.6) +
    geom_hline(yintercept = grand_mean, color = "red",
               linetype = "dashed", linewidth = 0.9) +
    scale_fill_identity() +
    labs(title = "LOGO-CV Feature Importance — ELLONA/IREN",
         subtitle = sprintf("Soglia (linea rossa) = grand mean (%.4f) | Blu = selezionata", grand_mean),
         x = NULL, y = "Mean Feature Importance (MDI)") +
    theme_minimal(base_size = 9) +
    theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5))

ggsave(PLOT_FILE, p, width = 16, height = 6, dpi = 150)
cat(sprintf("✓  Salvato: %s\n", PLOT_FILE))

# ── Salva ─────────────────────────────────────────────────────────────────────
write.table(results_df, RESULTS_FILE, sep = ";", row.names = FALSE, quote = FALSE)

selected_feats <- results_df$Feature[results_df$Selected]
con <- file(SELECTED_FILE, "w")
writeLines(sprintf("# LOGO-CV Feature Selection — %d feature selezionate", n_sel), con)
writeLines(sprintf("# Soglia: MeanImportance > grand_mean (%.6f)", grand_mean), con)
writeLines(sprintf("# AccuratezzaMedia_LOGO: %.4f", mean(acc_per_fold)), con)
writeLines("", con)
writeLines(as.character(selected_feats), con)
close(con)

cat(sprintf("✓  Salvato: %s\n", RESULTS_FILE))
cat(sprintf("✓  Salvato: %s\n", SELECTED_FILE))
