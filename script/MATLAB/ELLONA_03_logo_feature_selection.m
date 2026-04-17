% =========================================================================
% LOGO-CV Feature Selection — ELLONA/IREN
% - Legge le feature Boruta-confirmed da boruta_results.csv
% - Leave-One-Group-Out CV con gruppi = Sample.ID
% - Per ogni fold: allena RF (TreeBagger), registra importanza feature
% - Output: importanza media ± std su tutti i fold
%           selezione finale per soglia (mean > grand_mean)
% =========================================================================

setenv('IREN_DIR', fullfile(getenv('HOME'), 'Desktop', 'IREN'));
cd(getenv('IREN_DIR'));

TRAIN_FILE    = 'TRAIN_FEATURES.csv';
BORUTA_FILE   = 'boruta_results.csv';
RESULTS_FILE  = 'logo_feature_importance.csv';
SELECTED_FILE = 'logo_selected_features.txt';
PLOT_FILE     = 'logo_importance.png';
RANDOM_SEED   = 42;
N_TREES       = 500;

rng(RANDOM_SEED);

META_COLS = {'Data_analisi','Classe','Classe2','Diluizione','Cod', ...
             'Step1','Step2','Step3','Sample_ID','Sample_number', ...
             'Datetime_inizio','Datetime_fine'};

% ── Carica feature Boruta-confirmed ───────────────────────────────────────────
boruta_tbl     = readtable(BORUTA_FILE, 'Delimiter', ';', 'TextType', 'string');
confirmed_mask = strcmp(boruta_tbl.Status, 'Confirmed');
confirmed_feats = boruta_tbl.Feature(confirmed_mask);
fprintf('Feature Boruta-confirmed: %d\n', numel(confirmed_feats));

% ── Carica training set ───────────────────────────────────────────────────────
opts   = detectImportOptions(TRAIN_FILE, 'Delimiter', ';');
df     = readtable(TRAIN_FILE, opts);
fprintf('Training set: %d campioni, %d colonne\n', height(df), width(df));

groups     = df.Sample_ID;
y_labels   = df.Classe2;
unique_grp = unique(groups);
n_folds    = numel(unique_grp);
n_feat     = numel(confirmed_feats);

% Estrai matrice feature
X = table2array(df(:, confirmed_feats));
[n_samples, ~] = size(X);

fprintf('Gruppi (Sample.ID): %d unici → %d fold LOGO\n\n', n_folds, n_folds);

% Imputazione NA (mediana per colonna)
for j = 1:n_feat
    col = X(:, j);
    if any(isnan(col))
        X(isnan(col), j) = median(col, 'omitnan');
    end
end

% ── LOGO-CV ───────────────────────────────────────────────────────────────────
imp_matrix   = zeros(n_folds, n_feat);
acc_per_fold = zeros(n_folds, 1);

fprintf('Avvio LOGO-CV (%d fold)...\n', n_folds);

for i = 1:n_folds
    g          = unique_grp(i);
    test_mask  = groups == g;
    train_mask = ~test_mask;

    X_tr = X(train_mask, :);
    X_te = X(test_mask,  :);
    y_tr = y_labels(train_mask);
    y_te = y_labels(test_mask);

    % Allena Random Forest
    rf_fold = TreeBagger(N_TREES, X_tr, y_tr, ...
        'Method',              'classification', ...
        'PredictorImportance', 'on', ...
        'NumPredictorsToSample', round(sqrt(n_feat)));

    imp_matrix(i, :) = rf_fold.OOBPermutedPredictorDeltaError;

    % Accuratezza sul fold di test
    [preds, ~] = predict(rf_fold, X_te);
    preds      = string(preds);
    acc        = mean(preds == string(y_te));
    acc_per_fold(i) = acc;

    cls_left = strjoin(unique(string(y_te)), '/');
    fprintf('  Fold %2d/%d | Group=%3d (%-12s) | Acc=%.2f\n', ...
            i, n_folds, g, cls_left, acc);
end

fprintf('\nAccuratezza media LOGO: %.3f ± %.3f\n', ...
        mean(acc_per_fold), std(acc_per_fold));

% ── Aggregazione importanze ───────────────────────────────────────────────────
mean_imp  = mean(imp_matrix, 1);
std_imp   = std(imp_matrix,  0, 1);

% Frequenza top 50%
top50_freq = zeros(1, n_feat);
for i = 1:n_folds
    thresh = median(imp_matrix(i, :));
    top50_freq = top50_freq + double(imp_matrix(i, :) >= thresh);
end
top50_freq = top50_freq / n_folds;

grand_mean = mean(mean_imp);
selected   = mean_imp > grand_mean;

% Ordina per importanza decrescente
[mean_imp_sorted, sort_idx] = sort(mean_imp, 'descend');
feat_sorted    = confirmed_feats(sort_idx);
std_sorted     = std_imp(sort_idx);
top50_sorted   = top50_freq(sort_idx);
selected_sorted = selected(sort_idx);

% ── Report console ─────────────────────────────────────────────────────────────
fprintf('\n%s\n', repmat('=', 1, 65));
fprintf('  LOGO-CV Feature Ranking (soglia: mean > %.5f)\n', grand_mean);
fprintf('%s\n', repmat('=', 1, 65));
fprintf('  %3s  %-15s %9s %8s %7s %5s\n', 'Rk','Feature','MeanImp','StdImp','Top50%','Sel');
fprintf('  %s\n', repmat('-', 1, 55));
for i = 1:n_feat
    if selected_sorted(i), mark = '*'; else, mark = ' '; end
    fprintf('  %3d  %-15s %9.5f %8.5f %6.1f%% %5s\n', ...
            i, feat_sorted{i}, mean_imp_sorted(i), std_sorted(i), ...
            top50_sorted(i)*100, mark);
end

n_sel = sum(selected_sorted);
fprintf('\n  Feature selezionate: %d / %d\n', n_sel, n_feat);
fprintf('  Feature scartate:    %d / %d\n', n_feat - n_sel, n_feat);

% ── Plot ───────────────────────────────────────────────────────────────────────
colors_rgb = zeros(n_feat, 3);
for i = 1:n_feat
    if selected_sorted(i)
        colors_rgb(i,:) = [0.129, 0.588, 0.953];   % blu
    else
        colors_rgb(i,:) = [0.741, 0.741, 0.741];   % grigio
    end
end

figure('Position', [50 50 1600 550]);
hold on;
for i = 1:n_feat
    b = bar(i, mean_imp_sorted(i), 'FaceColor', colors_rgb(i,:), 'EdgeColor','none');
    errorbar(i, mean_imp_sorted(i), std_sorted(i), 'k.', 'LineWidth', 0.8);
end
yline(grand_mean, 'r--', sprintf('Soglia=%.4f', grand_mean), 'LineWidth', 1.2);
xticks(1:n_feat);
xticklabels(feat_sorted);
xtickangle(90);
ylabel('Mean Feature Importance (MDI)');
title('LOGO-CV Feature Importance — ELLONA/IREN', 'FontSize', 12);
grid on; box on;
hold off;
saveas(gcf, PLOT_FILE);
fprintf('✓  Salvato: %s\n', PLOT_FILE);

% ── Salva CSV ─────────────────────────────────────────────────────────────────
results_tbl = table(feat_sorted, mean_imp_sorted', std_sorted', top50_sorted', ...
                    selected_sorted', (1:n_feat)', ...
    'VariableNames', {'Feature','MeanImportance','StdImportance','Top50pct_freq','Selected','Rank'});
writetable(results_tbl, RESULTS_FILE, 'Delimiter', ';');

% Salva lista feature selezionate
fid = fopen(SELECTED_FILE, 'w');
fprintf(fid, '# LOGO-CV Feature Selection — %d feature selezionate\n', n_sel);
fprintf(fid, '# Soglia: MeanImportance > grand_mean (%.6f)\n', grand_mean);
fprintf(fid, '# AccuratezzaMedia_LOGO: %.4f\n\n', mean(acc_per_fold));
sel_feats = feat_sorted(selected_sorted);
for i = 1:numel(sel_feats)
    fprintf(fid, '%s\n', sel_feats{i});
end
fclose(fid);

fprintf('✓  Salvato: %s\n', RESULTS_FILE);
fprintf('✓  Salvato: %s\n', SELECTED_FILE);
