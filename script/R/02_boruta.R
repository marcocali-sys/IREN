# ==============================================================================
# Boruta feature selection — ELLONA/IREN
# - Input:  TRAIN_FEATURES.csv
# - Output: boruta_results.csv
#           boruta_selected_features.txt
# ==============================================================================
# Richiede: install.packages("Boruta")
# ==============================================================================

library(Boruta)

# Assicura che i file vengano salvati nella cartella dello script
setwd(normalizePath("~/Desktop/IREN"))

# ── Parametri ──────────────────────────────────────────────────────────────────
TRAIN_FILE    <- "TRAIN_FEATURES.csv"
RESULTS_FILE  <- "boruta_results.csv"
SELECTED_FILE <- "boruta_selected_features.txt"
RANDOM_SEED   <- 42
MAX_RUNS      <- 100     # iterazioni massime Boruta
P_VALUE       <- 0.05    # soglia significatività
N_TREES       <- 500     # alberi RF interno
# ──────────────────────────────────────────────────────────────────────────────

META_COLS <- c("Data.analisi", "Classe", "Classe2", "Diluizione", "Cod",
               "Step1", "Step2", "Step3", "Sample.ID", "Sample.number",
               "Datetime_inizio", "Datetime_fine")
PID_COLS  <- c("D3", "N3")   # PID = 0 ovunque

# ── Carica dati ───────────────────────────────────────────────────────────────
df <- read.csv(TRAIN_FILE, sep = ";", stringsAsFactors = FALSE)
cat(sprintf("Training set caricato: %d campioni, %d colonne\n", nrow(df), ncol(df)))

y <- as.factor(df$Classe2)

exclude_cols  <- c(META_COLS, PID_COLS)
feature_cols  <- setdiff(names(df), exclude_cols)
X             <- df[, feature_cols]

cat(sprintf("Feature iniziali: %d  (escluse meta + PID)\n", length(feature_cols)))
cat(sprintf("NA presenti:      %d valori\n", sum(is.na(X))))

# ── Imputazione NA (mediana per colonna) ──────────────────────────────────────
for (col in names(X)) {
    if (any(is.na(X[[col]]))) {
        X[[col]][is.na(X[[col]])] <- median(X[[col]], na.rm = TRUE)
    }
}

# ── Boruta ────────────────────────────────────────────────────────────────────
set.seed(RANDOM_SEED)

cat(sprintf("\nAvvio Boruta (maxRuns=%d, pValue=%.2f)...\n\n", MAX_RUNS, P_VALUE))

boruta_result <- Boruta(
    x        = X,
    y        = y,
    maxRuns  = MAX_RUNS,
    pValue   = P_VALUE,
    num.trees = N_TREES,
    doTrace  = 2
)

# Risolve i Tentative con TentativeRoughFix (più permissivo)
# — commentalo se vuoi mantenerli come Tentative
boruta_fixed <- TentativeRoughFix(boruta_result)

# ── Raccolta risultati ─────────────────────────────────────────────────────────
final_dec <- boruta_fixed$finalDecision

results_df <- data.frame(
    Feature = names(final_dec),
    Status  = as.character(final_dec),
    stringsAsFactors = FALSE
)

# Aggiungi importanza mediana da history
imp_history <- boruta_result$ImpHistory
# Escludi colonne shadow dall'history
shadow_cols <- grep("^shadow", colnames(imp_history), value = TRUE)
feat_cols_h <- setdiff(colnames(imp_history), shadow_cols)

med_imp <- apply(imp_history[, feat_cols_h, drop = FALSE], 2,
                 function(x) median(x[is.finite(x)]))
results_df$MedianImportance <- med_imp[results_df$Feature]
results_df <- results_df[order(results_df$Status, -results_df$MedianImportance), ]

# ── Report console ─────────────────────────────────────────────────────────────
for (s in c("Confirmed", "Tentative", "Rejected")) {
    subset <- results_df[results_df$Status == s, ]
    cat(sprintf("\n%s (%d):\n", toupper(s), nrow(subset)))
    if (s != "Rejected") {
        for (i in seq_len(nrow(subset))) {
            cat(sprintf("  %-15s  imp=%.3f\n",
                        subset$Feature[i], subset$MedianImportance[i]))
        }
    } else {
        cat(sprintf("  %d feature rifiutate\n", nrow(subset)))
    }
}

confirmed      <- results_df$Feature[results_df$Status == "Confirmed"]
tentative_list <- results_df$Feature[results_df$Status == "Tentative"]
rejected_list  <- results_df$Feature[results_df$Status == "Rejected"]

cat(sprintf("\n%s\n", strrep("=", 50)))
cat(sprintf("  Confirmed:  %d\n", length(confirmed)))
cat(sprintf("  Tentative:  %d\n", length(tentative_list)))
cat(sprintf("  Rejected:   %d\n", length(rejected_list)))
cat(sprintf("%s\n", strrep("=", 50)))

# ── Plot importanza ───────────────────────────────────────────────────────────
png("boruta_importance.png", width = 1200, height = 700, res = 120)
par(mar = c(10, 4, 4, 2))
plot(boruta_result,
     las    = 2,
     cex.axis = 0.6,
     main   = "Boruta Feature Importance — ELLONA/IREN",
     xlab   = "",
     ylab   = "Importance (RF)")
dev.off()
cat("✓  Salvato: boruta_importance.png\n")

# ── Salva ─────────────────────────────────────────────────────────────────────
write.table(results_df, RESULTS_FILE, sep = ";", row.names = FALSE, quote = FALSE)

con <- file(SELECTED_FILE, "w")
writeLines("# Boruta — Feature Confirmed", con)
writeLines(confirmed, con)
if (length(tentative_list) > 0) {
    writeLines("", con)
    writeLines("# Tentative (valuta manualmente)", con)
    writeLines(tentative_list, con)
}
close(con)

cat(sprintf("\n✓  Salvato: %s\n", RESULTS_FILE))
cat(sprintf("✓  Salvato: %s\n", SELECTED_FILE))
