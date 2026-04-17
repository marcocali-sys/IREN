% =========================================================================
% LDA — ELLONA/IREN
% Linear Discriminant Analysis (supervisionata): massimizza separazione classi.
% Input:  data/processed/TRAIN_FEATURES.csv
%         output/06_rfecv/rfecv_selected_features.txt
% Output: output/07_lda/lda_scores.png / lda_loadings.png / lda_results.csv
% =========================================================================

cd(fullfile(getenv('HOME'), 'Desktop', 'IREN'));
out_dir = 'output/07_lda';
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

CLASS_COLORS = containers.Map(...
    {'ARIA','BIOFILTRO','BIOGAS','FORSU','PERCOLATO'}, ...
    {[0.282 0.471 0.812], [0.416 0.800 0.396], [0.839 0.373 0.373], ...
     [0.706 0.675 0.780], [0.769 0.678 0.400]});
CLASS_MARKERS = containers.Map(...
    {'ARIA','BIOFILTRO','BIOGAS','FORSU','PERCOLATO'}, ...
    {'o','s','^','d','p'});

% ── Carica feature selezionate ─────────────────────────────────────────────
fid   = fopen('output/06_rfecv/rfecv_selected_features.txt','r');
lines = textscan(fid,'%s','Delimiter','\n'); fclose(fid);
lines = lines{1};
selected = {};
for i = 1:numel(lines)
    l = strtrim(lines{i});
    if ~isempty(l) && l(1) ~= '#'
        selected{end+1} = l;
    end
end
n_feat = numel(selected);
fprintf('Feature: %d\n', n_feat);

% ── Carica dati ─────────────────────────────────────────────────────────────
opts = detectImportOptions('data/processed/TRAIN_FEATURES.csv','Delimiter',';');
df   = readtable('data/processed/TRAIN_FEATURES.csv', opts);
y    = string(df.Classe2);
X    = table2array(df(:, selected));

% Imputa NA
for j = 1:n_feat
    col = X(:,j);
    if any(isnan(col))
        X(isnan(col),j) = median(col,'omitnan');
    end
end

% Standardizza
X_scaled = (X - mean(X,1)) ./ std(X,0,1);

% ── LDA con fitcdiscr ─────────────────────────────────────────────────────
mdl = fitcdiscr(X_scaled, y, 'DiscrimType','linear');

% Coefficienti LDA (eigenvectors dello scatter inter/intra)
% MATLAB non espone direttamente le direzioni LDA: le calcoliamo manualmente
classes    = unique(y);
n_classes  = numel(classes);
n_samp     = size(X_scaled, 1);

% Scatter within (Sw) e between (Sb)
grand_mean = mean(X_scaled, 1);
Sw = zeros(n_feat, n_feat);
Sb = zeros(n_feat, n_feat);
for ci = 1:n_classes
    cls   = classes(ci);
    mask  = y == cls;
    Xc    = X_scaled(mask, :);
    mu_c  = mean(Xc, 1);
    nc    = sum(mask);
    Sw    = Sw + (Xc - mu_c)' * (Xc - mu_c);
    d     = (mu_c - grand_mean)';
    Sb    = Sb + nc * (d * d');
end

% Eigenvectors di Sw^-1 * Sb
[V, D] = eig(Sb, Sw + eye(n_feat)*1e-8);
eigvals = diag(D);
[eigvals, idx] = sort(eigvals, 'descend');
V = V(:, idx);

n_ld    = min(n_classes - 1, n_feat);
V       = V(:, 1:n_ld);        % Direzioni discriminanti
scores  = X_scaled * V;         % Proiezioni (n x n_ld)
exp_var = (eigvals(1:n_ld) / sum(eigvals(1:n_ld))) * 100;

fprintf('\nLD1: %.1f%%  |  LD2: %.1f%%  |  LD3: %.1f%%\n', ...
        exp_var(1), exp_var(2), exp_var(3));
fprintf('Cumulativa LD1+LD2: %.1f%%\n', exp_var(1)+exp_var(2));

% ─────────────────────────────────────────────────────────────────────────────
% PLOT 1: LD1 vs LD2 con ellissi 95%
% ─────────────────────────────────────────────────────────────────────────────
figure('Position',[50 50 800 650]);
hold on;
legend_handles = gobjects(n_classes, 1);

for ci = 1:n_classes
    cls  = classes(ci);
    mask = y == cls;
    col  = CLASS_COLORS(char(cls));
    mrk  = CLASS_MARKERS(char(cls));
    h = scatter(scores(mask,1), scores(mask,2), 60, col, mrk, ...
                'filled','MarkerEdgeColor','white','LineWidth',0.4,'MarkerFaceAlpha',0.85);
    legend_handles(ci) = h;

    pts = scores(mask, 1:2);
    if size(pts,1) >= 3
        mu = mean(pts,1);
        C  = cov(pts);
        [Vell, Dell] = eig(C);
        chi2 = 5.991;
        t    = linspace(0, 2*pi, 200);
        ell  = (Vell * sqrt(Dell*chi2) * [cos(t); sin(t)])' + mu;
        fill(ell(:,1), ell(:,2), col, 'FaceAlpha',0.10, ...
             'EdgeColor',col,'LineWidth',1.5);
    end
end

xline(0,'--','Color',[0.7 0.7 0.7],'LineWidth',0.5);
yline(0,'--','Color',[0.7 0.7 0.7],'LineWidth',0.5);
xlabel(sprintf('LD1 (%.1f%%)', exp_var(1)),'FontSize',12);
ylabel(sprintf('LD2 (%.1f%%)', exp_var(2)),'FontSize',12);
title('LDA — ELLONA/IREN  (ellissi 95%)','FontSize',13);
legend(legend_handles, cellstr(classes),'Location','best','FontSize',9);
grid on; box on; hold off;
saveas(gcf, fullfile(out_dir,'lda_scores.png'));
fprintf('✓  lda_scores.png\n');

% ─────────────────────────────────────────────────────────────────────────────
% PLOT 2: LD1 vs LD3
% ─────────────────────────────────────────────────────────────────────────────
if n_ld >= 3
    figure('Position',[50 50 800 650]);
    hold on;
    lh2 = gobjects(n_classes,1);
    for ci = 1:n_classes
        cls  = classes(ci);
        mask = y == cls;
        col  = CLASS_COLORS(char(cls));
        mrk  = CLASS_MARKERS(char(cls));
        h = scatter(scores(mask,1), scores(mask,3), 60, col, mrk, ...
                    'filled','MarkerEdgeColor','white','LineWidth',0.4,'MarkerFaceAlpha',0.85);
        lh2(ci) = h;
        pts = scores(mask,[1,3]);
        if size(pts,1) >= 3
            mu = mean(pts,1); C = cov(pts); [Vell,Dell] = eig(C);
            ell = (Vell*sqrt(Dell*5.991)*[cos(linspace(0,2*pi,200));sin(linspace(0,2*pi,200))])' + mu;
            fill(ell(:,1),ell(:,2),col,'FaceAlpha',0.10,'EdgeColor',col,'LineWidth',1.5);
        end
    end
    xline(0,'--','Color',[0.7 0.7 0.7],'LineWidth',0.5);
    yline(0,'--','Color',[0.7 0.7 0.7],'LineWidth',0.5);
    xlabel(sprintf('LD1 (%.1f%%)',exp_var(1)),'FontSize',12);
    ylabel(sprintf('LD3 (%.1f%%)',exp_var(3)),'FontSize',12);
    title('LDA LD1 vs LD3 — ELLONA/IREN','FontSize',13);
    legend(lh2,cellstr(classes),'Location','best','FontSize',9);
    grid on; box on; hold off;
    saveas(gcf, fullfile(out_dir,'lda_scores_LD1_LD3.png'));
    fprintf('✓  lda_scores_LD1_LD3.png\n');
end

% ─────────────────────────────────────────────────────────────────────────────
% PLOT 3: Coefficienti discriminanti LD1 e LD2
% ─────────────────────────────────────────────────────────────────────────────
figure('Position',[50 50 1200 500]);

for ld_i = 1:2
    subplot(1,2,ld_i);
    vals = V(:, ld_i);
    [~, ord] = sort(abs(vals),'descend');
    feat_labels = selected(ord);
    vals_sorted = vals(ord);
    colors_bar  = zeros(n_feat, 3);
    for k = 1:n_feat
        if vals_sorted(k) >= 0
            colors_bar(k,:) = [0.282 0.471 0.812];
        else
            colors_bar(k,:) = [0.839 0.373 0.373];
        end
    end
    barh(1:n_feat, vals_sorted, 'FaceColor','flat');
    h_bar = get(gca,'Children');
    % Colori per barra
    hold on;
    barh(n_feat:-1:1, flip(vals_sorted), 0.7);
    % Manuale per colori misti:
    cla;
    for k = 1:n_feat
        barh(k, vals_sorted(k), 0.7, 'FaceColor', colors_bar(k,:), ...
             'EdgeColor','none','FaceAlpha',0.85);
        hold on;
    end
    xline(0,'Color',[0.5 0.5 0.5],'LineWidth',0.8);
    set(gca,'YTick',1:n_feat,'YTickLabel',feat_labels,'FontSize',9);
    xlabel('Scaling coefficient'); grid on;
    title(sprintf('Coefficienti LD%d (%.1f%%)', ld_i, exp_var(ld_i)),'FontSize',11);
    hold off;
end

saveas(gcf, fullfile(out_dir,'lda_loadings.png'));
fprintf('✓  lda_loadings.png\n');

% ─────────────────────────────────────────────────────────────────────────────
% Salva scores
% ─────────────────────────────────────────────────────────────────────────────
var_names = [{'Classe2','Sample_ID'}, arrayfun(@(i)sprintf('LD%d',i),1:n_ld,'UniformOutput',false)];
out_tbl   = array2table([scores(:,1:n_ld)], 'VariableNames', ...
    arrayfun(@(i)sprintf('LD%d',i),1:n_ld,'UniformOutput',false));
out_tbl   = [table(df.Classe2, df.Sample_ID, 'VariableNames',{'Classe2','Sample_ID'}), out_tbl];
writetable(out_tbl, fullfile(out_dir,'lda_results.csv'),'Delimiter',';');
fprintf('✓  lda_results.csv\n');

fprintf('\nVarianza spiegata:\n');
cum = 0;
for i = 1:n_ld
    cum = cum + exp_var(i);
    fprintf('  LD%d: %5.1f%%  (cumulativa: %5.1f%%)\n', i, exp_var(i), cum);
end
