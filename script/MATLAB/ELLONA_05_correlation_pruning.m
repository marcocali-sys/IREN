% ==============================================================================
% Step A — Correlation-based pruning — MATLAB
% ==============================================================================

cd(fullfile(getenv('HOME'),'Desktop','IREN'));
CORR_THRESH = 0.90;

% Carica feature e importanze
lines_raw  = readlines('logo_selected_features.txt');
logo_feats = strings(0,1);
for i = 1:numel(lines_raw)
    l = strtrim(lines_raw(i));
    if strlength(l)>0 && l(1)~='#', logo_feats(end+1,1)=l; end
end

imp_tbl = readtable('logo_feature_importance.csv','Delimiter',';','TextType','string');
mask_logo = ismember(imp_tbl.Feature, logo_feats);
imp_tbl   = imp_tbl(mask_logo,:);
[~,idx]   = sort(imp_tbl.MeanImportance,'descend');
imp_tbl   = imp_tbl(idx,:);
features_ranked = imp_tbl.Feature;
fprintf('Feature LOGO-selected in input: %d\n', numel(features_ranked));

% Carica training set
opts = detectImportOptions('TRAIN_FEATURES.csv','Delimiter',';');
df   = readtable('TRAIN_FEATURES.csv',opts);
X    = table2array(df(:, cellstr(features_ranked)));
for j = 1:size(X,2)
    col = X(:,j);
    X(isnan(col),j) = median(col,'omitnan');
end

corr_matrix = corrcoef(X);

% Pruning greedy
kept    = strings(0,1);
removed = strings(0,1);
partner_map = containers.Map('KeyType','char','ValueType','any');

for i = 1:numel(features_ranked)
    feat = features_ranked(i);
    if isempty(kept)
        kept(end+1,1) = feat; continue;
    end
    kept_idx = find(ismember(features_ranked, kept));
    corrs    = abs(corr_matrix(i, kept_idx));
    max_corr = max(corrs);
    if max_corr <= CORR_THRESH
        kept(end+1,1) = feat;
    else
        [~, max_pos]   = max(corrs);
        partner_feat   = kept(max_pos);
        removed(end+1,1) = feat;
        partner_map(char(feat)) = {char(partner_feat), corr_matrix(i, kept_idx(max_pos))};
    end
end

fprintf('\nSoglia correlazione: |ρ| > %.2f\n', CORR_THRESH);
fprintf('Feature mantenute: %d\n', numel(kept));
fprintf('Feature rimosse:   %d\n', numel(removed));

fprintf('\n%s\n  FEATURE MANTENUTE (%d)\n%s\n', repmat('=',1,55), numel(kept), repmat('=',1,55));
for i = 1:numel(kept)
    imp = imp_tbl.MeanImportance(strcmp(imp_tbl.Feature, kept(i)));
    fprintf('  %2d. %-15s  imp=%.5f\n', i, kept(i), imp);
end

fprintf('\n  FEATURE RIMOSSE (%d):\n', numel(removed));
for i = 1:numel(removed)
    feat = char(removed(i));
    imp  = imp_tbl.MeanImportance(strcmp(imp_tbl.Feature, removed(i)));
    info = partner_map(feat);
    fprintf('  %-15s  imp=%.5f  |ρ|=%.3f  con %s\n', feat, imp, abs(info{2}), info{1});
end

% Plot heatmap
kept_idx = find(ismember(features_ranked, kept));
corr_kept = corr_matrix(kept_idx, kept_idx);
corr_kept(triu(true(numel(kept)),1)) = NaN;

figure('Position',[50 50 800 700],'Color','w');
imagesc(corr_kept, [-1 1]); colormap(redblue_cmap()); colorbar;
xticks(1:numel(kept)); xticklabels(cellstr(kept)); xtickangle(45);
yticks(1:numel(kept)); yticklabels(cellstr(kept));
title(sprintf('Correlazione — %d feature post-pruning (|ρ|≤%.2f)', numel(kept), CORR_THRESH));
set(gca,'TickLabelInterpreter','none');
saveas(gcf,'corr_matrix_kept.png');
fprintf('\n✓  corr_matrix_kept.png\n');

% Salva
fid = fopen('corr_pruned_features.txt','w');
fprintf(fid,'# Correlation pruning — soglia |ρ|=%.2f\n', CORR_THRESH);
fprintf(fid,'# Input: %d  →  Output: %d feature\n\n', numel(features_ranked), numel(kept));
for i = 1:numel(kept), fprintf(fid,'%s\n', kept(i)); end
fclose(fid);
fprintf('✓  corr_pruned_features.txt\n');

function cmap = redblue_cmap()
    n = 256; cmap = zeros(n,3);
    for i=1:n
        t = (i-1)/(n-1)*2-1;
        if t<0, cmap(i,:)=[1+t, 1+t, 1]; else, cmap(i,:)=[1, 1-t, 1-t]; end
    end
end
