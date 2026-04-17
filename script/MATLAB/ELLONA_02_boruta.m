% =========================================================================
% Boruta feature selection — ELLONA/IREN
% Implementazione da zero con TreeBagger (Random Forest MATLAB)
%
% Algoritmo Boruta (Kursa & Rudnicki, 2010):
%   1. Crea shadow features = permutazioni casuali di ogni feature reale
%   2. Allena RF su dataset ampliato (reali + shadow)
%   3. Confronta importanza di ogni feature reale vs max shadow (MZSA)
%   4. Test binomiale per decidere Confirmed / Rejected / Tentative
%   5. Ripeti rimuovendo i decisi, fino a maxIter o convergenza
%
% Input:  TRAIN_FEATURES.csv
% Output: boruta_results.csv
%         boruta_selected_features.txt
%         boruta_importance.png
% =========================================================================

TRAIN_FILE    = 'TRAIN_FEATURES.csv';
RESULTS_FILE  = 'boruta_results.csv';
SELECTED_FILE = 'boruta_selected_features.txt';
RANDOM_SEED   = 42;
N_TREES       = 500;    % alberi per RF in ogni iterazione
MAX_ITER      = 100;    % iterazioni massime
ALPHA         = 0.05;   % soglia significatività (two-sided → α/2)

rng(RANDOM_SEED);

META_COLS = {'Data_analisi','Classe','Classe2','Diluizione','Cod', ...
             'Step1','Step2','Step3','Sample_ID','Sample_number', ...
             'Datetime_inizio','Datetime_fine'};
PID_COLS  = {'D3','N3'};

% ── Carica dati ───────────────────────────────────────────────────────────────
opts   = detectImportOptions(TRAIN_FILE, 'Delimiter', ';');
df     = readtable(TRAIN_FILE, opts);
fprintf('Training set caricato: %d campioni, %d colonne\n', height(df), width(df));

y_labels = df.Classe2;   % cell array di stringhe

% Identifica colonne feature (escludi meta + PID)
exclude = [META_COLS, PID_COLS];
all_cols = df.Properties.VariableNames;
feat_mask = ~ismember(all_cols, exclude);
feature_cols = all_cols(feat_mask);

X = table2array(df(:, feature_cols));
[n_samples, n_feat] = size(X);

fprintf('Feature iniziali: %d  (escluse meta + PID)\n', n_feat);
fprintf('NA presenti:      %d valori\n', sum(sum(isnan(X))));

% ── Imputazione NA (mediana per colonna) ──────────────────────────────────────
for j = 1:n_feat
    col = X(:, j);
    if any(isnan(col))
        X(isnan(col), j) = median(col, 'omitnan');
    end
end

% ── Boruta ────────────────────────────────────────────────────────────────────
fprintf('\nAvvio Boruta (maxIter=%d, alpha=%.2f)...\n\n', MAX_ITER, ALPHA);

% Stato di ogni feature: 0=Tentative, 1=Confirmed, -1=Rejected
feat_status  = zeros(1, n_feat);   % 0=Tentative, 1=Confirmed, -1=Rejected
hit_count    = zeros(1, n_feat);   % volte in cui imp > max shadow
iter_count   = zeros(1, n_feat);   % iterazioni completate per ogni feature
imp_history  = nan(MAX_ITER, n_feat);

for iter = 1:MAX_ITER
    % Feature ancora Tentative
    active_idx = find(feat_status == 0);
    if isempty(active_idx)
        fprintf('Iter %d: tutte le feature decise. Stop.\n', iter);
        break;
    end

    X_active = X(:, active_idx);
    n_active = length(active_idx);

    % Crea shadow features (permutazione per colonna)
    X_shadow = X_active;
    for j = 1:n_active
        X_shadow(:, j) = X_active(randperm(n_samples), j);
    end

    % Dataset ampliato: [reali_active | shadow_active]
    X_aug = [X_active, X_shadow];

    % Allena Random Forest
    rf = TreeBagger(N_TREES, X_aug, y_labels, ...
        'Method',          'classification', ...
        'PredictorSelection', 'curvature', ...
        'OOBPredictorImportance', 'on', ...
        'NumPredictorsToSample', 'all');

    imp_aug = rf.OOBPermutedPredictorDeltaError;  % 1 × 2*n_active

    imp_real   = imp_aug(1:n_active);
    imp_shadow = imp_aug(n_active+1:end);
    max_shadow = max(imp_shadow);

    % Aggiorna contatori
    for k = 1:n_active
        fi = active_idx(k);
        imp_history(iter, fi) = imp_real(k);
        iter_count(fi) = iter_count(fi) + 1;
        if imp_real(k) > max_shadow
            hit_count(fi) = hit_count(fi) + 1;
        end
    end

    % Test binomiale two-sided (Bonferroni su n_active)
    alpha_adj = ALPHA / n_active;
    for k = 1:n_active
        fi  = active_idx(k);
        n_i = iter_count(fi);
        h_i = hit_count(fi);

        % p-value: P(X >= h | n, 0.5) e P(X <= h | n, 0.5)
        p_confirm = 1 - binocdf(h_i - 1, n_i, 0.5);  % prob di essere >= h
        p_reject  = binocdf(h_i, n_i, 0.5);           % prob di essere <= h

        if p_confirm <= alpha_adj
            feat_status(fi) = 1;    % Confirmed
        elseif p_reject <= alpha_adj
            feat_status(fi) = -1;   % Rejected
        end
    end

    n_conf = sum(feat_status ==  1);
    n_rej  = sum(feat_status == -1);
    n_tent = sum(feat_status ==  0);
    fprintf('Iter %3d | Active: %3d | Confirmed: %3d | Rejected: %3d | Tentative: %3d\n', ...
            iter, length(active_idx), n_conf, n_rej, n_tent);
end

% Feature rimaste Tentative → decidi con importanza mediana vs mediana shadow
% (TentativeRoughFix equivalente)
tent_idx = find(feat_status == 0);
if ~isempty(tent_idx)
    fprintf('\nRisoluzione %d feature Tentative con mediana importanza...\n', length(tent_idx));
    for fi = tent_idx
        med_imp = median(imp_history(:, fi), 'omitnan');
        if med_imp > 0
            feat_status(fi) = 1;
        else
            feat_status(fi) = -1;
        end
    end
end

% ── Raccolta risultati ─────────────────────────────────────────────────────────
status_str = cell(1, n_feat);
for fi = 1:n_feat
    if feat_status(fi) ==  1, status_str{fi} = 'Confirmed';
    elseif feat_status(fi) == -1, status_str{fi} = 'Rejected';
    else, status_str{fi} = 'Tentative';
    end
end

med_importance = median(imp_history, 1, 'omitnan');

results_table = table(feature_cols', status_str', med_importance', ...
    'VariableNames', {'Feature','Status','MedianImportance'});
results_table = sortrows(results_table, {'Status','MedianImportance'}, {'ascend','descend'});

% ── Report console ─────────────────────────────────────────────────────────────
for s = {'Confirmed','Tentative','Rejected'}
    s = s{1};
    mask = strcmp(results_table.Status, s);
    sub  = results_table(mask, :);
    fprintf('\n%s (%d):\n', upper(s), sum(mask));
    if ~strcmp(s, 'Rejected')
        for i = 1:height(sub)
            fprintf('  %-15s  imp=%.4f\n', sub.Feature{i}, sub.MedianImportance(i));
        end
    else
        fprintf('  %d feature rifiutate\n', sum(mask));
    end
end

confirmed      = results_table.Feature(strcmp(results_table.Status, 'Confirmed'));
tentative_list = results_table.Feature(strcmp(results_table.Status, 'Tentative'));
rejected_list  = results_table.Feature(strcmp(results_table.Status, 'Rejected'));

fprintf('\n%s\n', repmat('=',1,50));
fprintf('  Confirmed:  %d\n', numel(confirmed));
fprintf('  Tentative:  %d\n', numel(tentative_list));
fprintf('  Rejected:   %d\n', numel(rejected_list));
fprintf('%s\n', repmat('=',1,50));

% ── Plot importanza ───────────────────────────────────────────────────────────
colors = zeros(n_feat, 3);
for fi = 1:n_feat
    name = feature_cols{fi};
    s    = results_table.Status{strcmp(results_table.Feature, name)};
    if strcmp(s, 'Confirmed'),  colors(fi,:) = [0.2 0.6 0.2];  % verde
    elseif strcmp(s,'Tentative'), colors(fi,:) = [0.9 0.7 0.1]; % giallo
    else,  colors(fi,:) = [0.8 0.2 0.2];  % rosso
    end
end

[~, sort_idx] = sort(med_importance, 'descend');

figure('Position',[100 100 1400 600]);
b = bar(med_importance(sort_idx));
b.FaceColor = 'flat';
b.CData = colors(sort_idx,:);
xticks(1:n_feat);
xticklabels(feature_cols(sort_idx));
xtickangle(90);
ylabel('Median Importance (OOB)');
title('Boruta Feature Importance — ELLONA/IREN');
legend([patch(nan,nan,[0.2 0.6 0.2]), patch(nan,nan,[0.9 0.7 0.1]), patch(nan,nan,[0.8 0.2 0.2])], ...
       {'Confirmed','Tentative','Rejected'}, 'Location','northeast');
grid on;
saveas(gcf, 'boruta_importance.png');
fprintf('✓  Salvato: boruta_importance.png\n');

% ── Salva ─────────────────────────────────────────────────────────────────────
writetable(results_table, RESULTS_FILE, 'Delimiter', ';');

fid = fopen(SELECTED_FILE, 'w');
fprintf(fid, '# Boruta — Feature Confirmed\n');
for i = 1:numel(confirmed)
    fprintf(fid, '%s\n', confirmed{i});
end
if ~isempty(tentative_list)
    fprintf(fid, '\n# Tentative (valuta manualmente)\n');
    for i = 1:numel(tentative_list)
        fprintf(fid, '%s\n', tentative_list{i});
    end
end
fclose(fid);

fprintf('\n✓  Salvato: %s\n', RESULTS_FILE);
fprintf('✓  Salvato: %s\n', SELECTED_FILE);
