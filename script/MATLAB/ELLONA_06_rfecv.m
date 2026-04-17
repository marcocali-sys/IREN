% ==============================================================================
% Step C — RFECV con LOGO-CV — MATLAB
% ==============================================================================

cd(fullfile(getenv('HOME'),'Desktop','IREN'));
rng(42);
N_TREES   = 300;
MIN_FEATS = 3;

% Carica feature post-pruning
lines_raw = readlines('corr_pruned_features.txt');
feats = strings(0,1);
for i=1:numel(lines_raw)
    l=strtrim(lines_raw(i));
    if strlength(l)>0 && l(1)~='#', feats(end+1,1)=l; end
end
fprintf('Feature in input: %d\n', numel(feats));

% Carica training set
opts   = detectImportOptions('TRAIN_FEATURES.csv','Delimiter',';');
df     = readtable('TRAIN_FEATURES.csv',opts);
groups = df.Sample_ID;
y      = string(df.Classe2);
X      = table2array(df(:,cellstr(feats)));
for j=1:size(X,2)
    col=X(:,j); X(isnan(col),j)=median(col,'omitnan');
end
fprintf('Training set: %d campioni, %d feature\n', size(X,1), numel(feats));

unique_groups = unique(groups);
n_folds = numel(unique_groups);
fprintf('Gruppi LOGO: %d fold\n\n', n_folds);

% Ranking iniziale via RF su tutto il training
rf_full = TreeBagger(N_TREES, X, y, 'Method','classification', ...
    'PredictorImportance','on','NumPredictorsToSample','all');
[~, imp_order] = sort(rf_full.OOBPermutedPredictorDeltaError,'descend');
feats_ranked = feats(imp_order);

% LOGO balanced accuracy su un sottoinsieme di feature
function ba = logo_ba(X_sub, y, groups, unique_groups, N_TREES)
    classes = unique(y);
    correct_cls = containers.Map(cellstr(classes), num2cell(zeros(1,numel(classes))));
    total_cls   = containers.Map(cellstr(classes), num2cell(zeros(1,numel(classes))));
    for gi = 1:numel(unique_groups)
        g          = unique_groups(gi);
        test_mask  = groups == g;
        train_mask = ~test_mask;
        rf = TreeBagger(N_TREES, X_sub(train_mask,:), y(train_mask), ...
            'Method','classification','NumPredictorsToSample',round(sqrt(size(X_sub,2))));
        preds = string(predict(rf, X_sub(test_mask,:)));
        y_te  = y(test_mask);
        for ci = 1:numel(classes)
            cls = char(classes(ci));
            mask_true = y_te == classes(ci);
            if ~any(mask_true), continue; end
            correct_cls(cls) = correct_cls(cls) + sum(preds(mask_true)==classes(ci));
            total_cls(cls)   = total_cls(cls)   + sum(mask_true);
        end
    end
    accs = zeros(1,numel(classes));
    for ci=1:numel(classes)
        cls=char(classes(ci));
        if total_cls(cls)>0, accs(ci)=correct_cls(cls)/total_cls(cls); end
    end
    ba = mean(accs);
end

% RFE loop
fprintf('Avvio RFECV...\n');
n_sizes   = numel(feats):-1:MIN_FEATS;
ba_scores = zeros(1,numel(n_sizes));
for i=1:numel(n_sizes)
    n     = n_sizes(i);
    top   = feats_ranked(1:n);
    idx_f = find(ismember(feats, top));
    ba    = logo_ba(X(:,idx_f), y, groups, unique_groups, N_TREES);
    ba_scores(i) = ba;
    fprintf('  n=%2d feature → balanced_accuracy=%.4f\n', n, ba);
end

[ba_optimal, best_idx] = max(ba_scores);
n_optimal = n_sizes(best_idx);
selected_feats = feats_ranked(1:n_optimal);
fprintf('\nNumero ottimale di feature: %d\n', n_optimal);
fprintf('Balanced accuracy ottimale: %.4f\n', ba_optimal);

% Plot
figure('Position',[50 50 900 480],'Color','w');
plot(n_sizes, ba_scores,'o-','Color',[0.282 0.471 0.812],'LineWidth',1.5,'MarkerFaceColor',[0.282 0.471 0.812]);
hold on;
xline(n_optimal,'--','Color',[0.839 0.373 0.373],'LineWidth',1.5);
yline(ba_optimal,':','Color',[0.839 0.373 0.373],'LineWidth',1);
text(n_optimal+0.2, ba_optimal-0.03, sprintf('%d feat\nBA=%.3f',n_optimal,ba_optimal),...
     'Color',[0.839 0.373 0.373],'FontSize',9);
xlabel('Numero di feature'); ylabel('Balanced accuracy (LOGO-CV)');
title('RFECV — Selezione numero ottimale di feature — ELLONA/IREN');
set(gca,'XTick',n_sizes); grid on; hold off;
saveas(gcf,'rfecv_results.png');
fprintf('\n✓  rfecv_results.png\n');

% Salva
fid = fopen('rfecv_selected_features.txt','w');
fprintf(fid,'# RFECV — %d feature selezionate\n', n_optimal);
fprintf(fid,'# Balanced accuracy ottimale: %.4f\n\n', ba_optimal);
for i=1:numel(selected_feats), fprintf(fid,'%s\n',selected_feats(i)); end
fclose(fid);
fprintf('✓  rfecv_selected_features.txt\n');
