% =========================================================================
% PCA — ELLONA/IREN
% Input:  data/processed/TRAIN_FEATURES.csv
%         output/06_rfecv/rfecv_selected_features.txt
% Output: output/04_pca/pca_scree.png / pca_scores.png / pca_loadings.png
% =========================================================================

cd(fullfile(getenv('HOME'), 'Desktop', 'IREN'));
out_dir = 'output/04_pca';
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

CLASS_COLORS = containers.Map(...
    {'ARIA','BIOFILTRO','BIOGAS','FORSU','PERCOLATO'}, ...
    {[0.282 0.471 0.812], [0.416 0.800 0.396], [0.839 0.373 0.373], ...
     [0.706 0.675 0.780], [0.769 0.678 0.400]});
CLASS_MARKERS = containers.Map(...
    {'ARIA','BIOFILTRO','BIOGAS','FORSU','PERCOLATO'}, ...
    {'o','s','^','d','p'});

% ── Carica feature selezionate ─────────────────────────────────────────────────
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
fprintf('Feature selezionate: %d\n', n_feat);

% ── Carica dati ───────────────────────────────────────────────────────────────
opts = detectImportOptions('data/processed/TRAIN_FEATURES.csv','Delimiter',';');
df   = readtable('data/processed/TRAIN_FEATURES.csv', opts);
y    = string(df.Classe2);
X    = table2array(df(:, selected));
[n, ~] = size(X);

% Imputa NA
for j = 1:n_feat
    col = X(:,j);
    if any(isnan(col))
        X(isnan(col),j) = median(col,'omitnan');
    end
end

% Standardizza (z-score per colonna)
X_scaled = (X - mean(X,1)) ./ std(X,0,1);

% ── PCA ───────────────────────────────────────────────────────────────────────
[coeff, scores, ~, ~, explained] = pca(X_scaled);
cum_var   = cumsum(explained);
n_comp_90 = find(cum_var >= 90, 1);

fprintf('\nPC1: %.1f%%  |  PC2: %.1f%%  |  PC3: %.1f%%\n', ...
        explained(1), explained(2), explained(3));
fprintf('Componenti per 90%% varianza: %d\n', n_comp_90);

classes = unique(y);

% ─────────────────────────────────────────────────────────────────────────────
% PLOT 1: Scree plot
% ─────────────────────────────────────────────────────────────────────────────
n_show = min(12, n_feat);
figure('Position',[50 50 1100 450]);

subplot(1,2,1);
bar(1:n_show, explained(1:n_show), 'FaceColor',[0.282 0.471 0.812], 'EdgeColor','none');
xlabel('Componente principale'); ylabel('Varianza spiegata (%)');
title('Scree Plot'); xticks(1:n_show); grid on;
for i = 1:n_show
    text(i, explained(i)+0.3, sprintf('%.1f%%',explained(i)), ...
         'HorizontalAlignment','center','FontSize',7);
end

subplot(1,2,2);
plot(1:n_show, cum_var(1:n_show), 'o-', 'Color',[0.839 0.373 0.373], ...
     'LineWidth',1.5,'MarkerFaceColor',[0.839 0.373 0.373],'MarkerSize',5);
yline(90,'--','90%','Color',[0.5 0.5 0.5],'LineWidth',0.8);
xline(n_comp_90,'--','Color',[0.5 0.5 0.5],'LineWidth',0.8);
xlabel('Numero di componenti'); ylabel('Varianza cumulativa (%)');
title('Varianza Cumulativa'); xlim([1 n_show]); ylim([0 105]); grid on;

saveas(gcf, fullfile(out_dir,'pca_scree.png')); fprintf('✓  pca_scree.png\n');

% ─────────────────────────────────────────────────────────────────────────────
% PLOT 2: PC1 vs PC2 con ellissi di confidenza (95%)
% ─────────────────────────────────────────────────────────────────────────────
figure('Position',[50 50 800 650]);
hold on;
legend_handles = gobjects(numel(classes),1);

for ci = 1:numel(classes)
    cls  = classes(ci);
    mask = y == cls;
    col  = CLASS_COLORS(char(cls));
    mrk  = CLASS_MARKERS(char(cls));

    % Scatter
    h = scatter(scores(mask,1), scores(mask,2), 60, col, mrk, ...
                'filled','MarkerEdgeColor','white','LineWidth',0.4,'MarkerFaceAlpha',0.85);
    legend_handles(ci) = h;

    % Ellisse di confidenza 95% (assumendo distribuzione normale bivariata)
    pts = scores(mask, 1:2);
    if size(pts,1) >= 3
        mu   = mean(pts,1);
        C    = cov(pts);
        [V,D] = eig(C);
        chi2  = 5.991;  % chi2 95% con 2 gradi di libertà
        t     = linspace(0, 2*pi, 200);
        ellipse = (V * sqrt(D*chi2) * [cos(t); sin(t)])' + mu;
        fill(ellipse(:,1), ellipse(:,2), col, 'FaceAlpha',0.10, ...
             'EdgeColor',col,'LineWidth',1.5);
    end
end

xline(0,'--','Color',[0.7 0.7 0.7],'LineWidth',0.5);
yline(0,'--','Color',[0.7 0.7 0.7],'LineWidth',0.5);
xlabel(sprintf('PC1 (%.1f%%)', explained(1)),'FontSize',12);
ylabel(sprintf('PC2 (%.1f%%)', explained(2)),'FontSize',12);
title('PCA — ELLONA/IREN  (ellissi 95%)','FontSize',13);
legend(legend_handles, cellstr(classes), 'Location','best','FontSize',9);
grid on; box on; hold off;
saveas(gcf, fullfile(out_dir,'pca_scores.png')); fprintf('✓  pca_scores.png\n');

% ─────────────────────────────────────────────────────────────────────────────
% PLOT 3: Cerchio delle correlazioni — top 15 loadings
% ─────────────────────────────────────────────────────────────────────────────
load1   = coeff(:,1);
load2   = coeff(:,2);
contrib = sqrt(load1.^2 + load2.^2);
[~, top_idx] = sort(contrib,'descend');
% Mostra tutte le feature (sono già 11 dopo RFECV)

figure('Position',[50 50 750 750]);
hold on;
theta = linspace(0, 2*pi, 300);
plot(cos(theta), sin(theta), '--', 'Color',[0.6 0.6 0.6], 'LineWidth',0.8);

for i = 1:numel(top_idx)
    k = top_idx(i);
    quiver(0, 0, load1(k), load2(k), 0, ...
           'Color',[0.282 0.471 0.812],'LineWidth',1.4,'MaxHeadSize',0.5);
    text(load1(k)*1.1, load2(k)*1.1, selected{k}, ...
         'FontSize',8,'HorizontalAlignment','center','Color',[0.15 0.15 0.15]);
end

xline(0,'Color',[0.7 0.7 0.7],'LineWidth',0.5);
yline(0,'Color',[0.7 0.7 0.7],'LineWidth',0.5);
xlim([-1.2 1.2]); ylim([-1.2 1.2]); axis square;
xlabel(sprintf('PC1 (%.1f%%)', explained(1)),'FontSize',12);
ylabel(sprintf('PC2 (%.1f%%)', explained(2)),'FontSize',12);
title(sprintf('Cerchio delle correlazioni — %d feature RFECV', n_feat),'FontSize',12);
grid on; box on; hold off;
saveas(gcf, fullfile(out_dir,'pca_loadings.png')); fprintf('✓  pca_loadings.png\n');

% ─────────────────────────────────────────────────────────────────────────────
% PLOT 4: PC1 vs PC3
% ─────────────────────────────────────────────────────────────────────────────
figure('Position',[50 50 800 650]);
hold on;
legend_handles2 = gobjects(numel(classes),1);

for ci = 1:numel(classes)
    cls  = classes(ci);
    mask = y == cls;
    col  = CLASS_COLORS(char(cls));
    mrk  = CLASS_MARKERS(char(cls));
    h = scatter(scores(mask,1), scores(mask,3), 60, col, mrk, ...
                'filled','MarkerEdgeColor','white','LineWidth',0.4,'MarkerFaceAlpha',0.85);
    legend_handles2(ci) = h;
    pts = scores(mask,[1,3]);
    if size(pts,1) >= 3
        mu = mean(pts,1); C = cov(pts); [V,D] = eig(C);
        ellipse = (V * sqrt(D*5.991) * [cos(linspace(0,2*pi,200)); sin(linspace(0,2*pi,200))])' + mu;
        fill(ellipse(:,1), ellipse(:,2), col,'FaceAlpha',0.10,'EdgeColor',col,'LineWidth',1.5);
    end
end

xline(0,'--','Color',[0.7 0.7 0.7],'LineWidth',0.5);
yline(0,'--','Color',[0.7 0.7 0.7],'LineWidth',0.5);
xlabel(sprintf('PC1 (%.1f%%)', explained(1)),'FontSize',12);
ylabel(sprintf('PC3 (%.1f%%)', explained(3)),'FontSize',12);
title('PCA PC1 vs PC3 — ELLONA/IREN','FontSize',13);
legend(legend_handles2, cellstr(classes),'Location','best','FontSize',9);
grid on; box on; hold off;
saveas(gcf, fullfile(out_dir,'pca_scores_PC1_PC3.png')); fprintf('✓  pca_scores_PC1_PC3.png\n');

% ─────────────────────────────────────────────────────────────────────────────
% Salva scores + summary
% ─────────────────────────────────────────────────────────────────────────────
out_tbl = table(df.Classe2, df.Sample_ID, scores(:,1), scores(:,2), scores(:,3), scores(:,4), scores(:,5), ...
    'VariableNames',{'Classe2','Sample_ID','PC1','PC2','PC3','PC4','PC5'});
writetable(out_tbl, fullfile(out_dir,'pca_results.csv'),'Delimiter',';');
fprintf('✓  pca_results.csv\n');

fprintf('\nVarianza spiegata:\n');
for i = 1:min(8,numel(explained))
    fprintf('  PC%d: %5.1f%%  (cumulativa: %5.1f%%)\n', i, explained(i), cum_var(i));
end
