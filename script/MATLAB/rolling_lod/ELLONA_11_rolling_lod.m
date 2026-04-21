%% ELLONA_11_rolling_lod.m
% LOD mobile (rolling) su PC₁ — confronto con LOD fisso.
%
% Metodologia
% ───────────
%   ┌─────────────────────────────────────────────────────────────────────┐
%   │  Modello PCA  →  FISSO  (output ELLONA_08)                          │
%   │                                                                     │
%   │  LOD(t) = μ_roll(t) ± k·σ_global    [Opzione B]                    │
%   │                                                                     │
%   │  Tre finestre rolling testate: 7d, 14d, 30d                         │
%   │  → confronto σ_roll(t) per identificare la scala temporale          │
%   │    a cui la variabilità del baseline è stabile                      │
%   └─────────────────────────────────────────────────────────────────────┘
%
% Output  IREN/output/rolling_lod/
%   ├── sigma_window_comparison.png     σ_roll(t) per 7d / 14d / 30d
%   ├── mu_window_comparison.png        μ_roll(t) per 7d / 14d / 30d
%   ├── PC1_fixed_vs_rolling.png        overview LOD fisso vs rolling 30d
%   ├── events_weekly_comparison.png    barchart eventi (4 varianti)
%   └── comparison_stats.csv           metriche riepilogative
%
% Marco Calì — PoliMi, Aprile 2026

clear; clc; close all;

%% ── CONFIG ───────────────────────────────────────────────────────────────
scriptDir = fileparts(mfilename('fullpath'));
baseDir   = fullfile(scriptDir, '..', '..', '..');   % → IREN/

modelFile = fullfile(baseDir, 'output', 'event_detection', 'pca_model_ELLONA.mat');
dataFile  = fullfile(baseDir, 'data',   'processed',       'monitoring_all.mat');
outDir    = fullfile(baseDir, 'output', 'rolling_lod');
if ~isfolder(outDir), mkdir(outDir); end

% ── Parametri LOD ─────────────────────────────────────────────────────────
windows   = [7, 14, 30];   % finestre da testare (giorni)
step_days = 1;
pLow      = 25;
pHigh     = 75;
k_lod     = 3;
minBL     = 100;

%% ── CARICA MODELLO & DATI ────────────────────────────────────────────────
fprintf('Caricamento modello PCA... ');
M = load(modelFile);
fprintf('OK  (baseline=%s, k=%.0f)\n', M.baselineMode, M.k_lod);

fprintf('Caricamento dati...        '); tic;
S = load(dataFile, 'DATA'); DATA = S.DATA;
fprintf('%.1fs  (%d righe)\n', toc, height(DATA));

moxCols = cellstr(M.predictors);

%% ── CALCOLO SCORE PC₁ ────────────────────────────────────────────────────
fprintf('Calcolo score PCA...       '); tic;
X = DATA{:, moxCols};
for j = 1:size(X,2)
    nm = isnan(X(:,j));
    if any(nm), X(nm,j) = median(X(~nm,j)); end
end
SC   = ((X - M.mu) ./ M.sigma - M.muPCA) * M.coeff;
PC1  = SC(:,1);
t    = DATA.datetime;
dt_s = seconds(median(diff(t(1:min(5000,end)))));
fprintf('%.1fs\n', toc);

%% ── LOD FISSO ────────────────────────────────────────────────────────────
lod_lo_fix = M.lod_lower_pc1;
lod_hi_fix = M.lod_upper_pc1;
isEvt_fix  = PC1 < lod_lo_fix;

fprintf('\n--- LOD fisso ---\n');
fprintf('  LOD = [%.4f, %.4f]   (mu=%.4f, sigma=%.4f)\n', ...
    lod_lo_fix, lod_hi_fix, M.mu_pc1, M.sigma_pc1);
fprintf('  Eventi: %d / %d  (%.2f%%)\n', ...
    sum(isEvt_fix), numel(PC1), 100*mean(isEvt_fix));

%% ── LOD ROLLING per le 3 finestre ────────────────────────────────────────
X_mox = DATA{:, moxCols};
nW    = numel(windows);

% Celle di output: mu_roll{i}, sigma_roll{i}, lod_lo_roll{i}, isEvt_roll{i}
mu_roll     = cell(nW,1);
sigma_roll  = cell(nW,1);
lod_lo_roll = cell(nW,1);
lod_hi_roll = cell(nW,1);
isEvt_roll  = cell(nW,1);

for wi = 1:nW
    wd = windows(wi);
    fprintf('\n--- LOD rolling (finestra %dd, step %dd) ---\n', wd, step_days);
    [lod_lo_roll{wi}, lod_hi_roll{wi}, mu_roll{wi}, sigma_roll{wi}] = ...
        ellona_rolling_lod(t, PC1, X_mox, pLow, pHigh, k_lod, wd, step_days, minBL, ...
        lod_lo_fix, lod_hi_fix);
    isEvt_roll{wi} = PC1 < lod_lo_roll{wi};
    fprintf('  LOD_lo medio = %.4f  (range: [%.4f, %.4f])\n', ...
        mean(lod_lo_roll{wi},'omitnan'), min(lod_lo_roll{wi}), max(lod_lo_roll{wi}));
    fprintf('  sigma_roll medio = %.4f  (range: [%.4f, %.4f])\n', ...
        mean(sigma_roll{wi},'omitnan'), min(sigma_roll{wi}), max(sigma_roll{wi}));
    fprintf('  Eventi: %d / %d  (%.2f%%)\n', ...
        sum(isEvt_roll{wi}), numel(PC1), 100*mean(isEvt_roll{wi}));
end

%% ── DOWNSAMPLE PER PLOT ──────────────────────────────────────────────────
step_ds = max(1, floor(numel(t)/120000));
idx_ds  = 1:step_ds:numel(t);
t_ds    = t(idx_ds);
p1_ds   = PC1(idx_ds);

%% ════════════════════════════════════════════════════════════════════════
%  PLOT 1 — σ_roll(t): 7d / 14d / 30d + σ_globale  [PLOT CHIAVE]
%% ════════════════════════════════════════════════════════════════════════
colors_sg = [0.85 0.33 0.10;   % 7d  — arancio bruciato
             0.18 0.55 0.34;   % 14d — verde scuro
             0.12 0.38 0.74];  % 30d — blu

fig1 = figure('Name','σ_roll(t) — confronto finestre', ...
    'Color','w','Position',[40 40 1400 480]);
hold on; grid on;

for wi = 1:nW
    sg_ds = sigma_roll{wi}(idx_ds);
    plot(t_ds, sg_ds, '-', 'Color', colors_sg(wi,:), 'LineWidth', 1.4, ...
        'DisplayName', sprintf('σ_{roll}  %dd', windows(wi)));
end

yline(M.sigma_pc1, '--k', sprintf('σ_{global} = %.4f', M.sigma_pc1), ...
    'LineWidth', 2.0, 'LabelHorizontalAlignment','right', 'FontSize',10);

hold off;
ax1 = gca;
ax1.XAxis.TickLabelFormat = 'MMM-yy';
ax1.FontSize = 10;
xlabel('Data','FontSize',11);
ylabel('σ_{roll}(t)','FontSize',11);
title('Confronto σ rolling per finestre diverse  (baseline IQR [P25,P75] su MOX)', ...
    'FontSize',11);
legend('Location','northeast','FontSize',10);
xlim([t(1) t(end)]);

exportgraphics(fig1, fullfile(outDir,'sigma_window_comparison.png'), 'Resolution',300);
fprintf('\nSalvato: sigma_window_comparison.png\n');

%% ════════════════════════════════════════════════════════════════════════
%  PLOT 2 — μ_roll(t): 7d / 14d / 30d + μ_globale
%% ════════════════════════════════════════════════════════════════════════
fig2 = figure('Name','μ_roll(t) — confronto finestre', ...
    'Color','w','Position',[40 40 1400 480]);
hold on; grid on;

for wi = 1:nW
    mu_ds = mu_roll{wi}(idx_ds);
    plot(t_ds, mu_ds, '-', 'Color', colors_sg(wi,:), 'LineWidth', 1.4, ...
        'DisplayName', sprintf('μ_{roll}  %dd', windows(wi)));
end

yline(M.mu_pc1, '--k', sprintf('μ_{global} = %.4f', M.mu_pc1), ...
    'LineWidth', 2.0, 'LabelHorizontalAlignment','right', 'FontSize',10);

hold off;
ax2 = gca;
ax2.XAxis.TickLabelFormat = 'MMM-yy';
ax2.FontSize = 10;
xlabel('Data','FontSize',11);
ylabel('μ_{roll}(t)','FontSize',11);
title('Confronto μ rolling per finestre diverse  (deriva del baseline nel tempo)', ...
    'FontSize',11);
legend('Location','northeast','FontSize',10);
xlim([t(1) t(end)]);

exportgraphics(fig2, fullfile(outDir,'mu_window_comparison.png'), 'Resolution',300);
fprintf('Salvato: mu_window_comparison.png\n');

%% ════════════════════════════════════════════════════════════════════════
%  PLOT 3 — PC₁(t): LOD fisso vs rolling 30d  (overview)
%% ════════════════════════════════════════════════════════════════════════
wi_30 = find(windows == 30);
lo_r_ds  = lod_lo_roll{wi_30}(idx_ds);
hi_r_ds  = lod_hi_roll{wi_30}(idx_ds);

fig3 = figure('Name','PC1 — Fixed vs Rolling LOD (30d)', ...
    'Color','w','Position',[40 40 1500 580]);
hold on; grid on;

plot(t_ds, p1_ds, '-', 'Color',[0.70 0.80 0.93], 'LineWidth',0.4, 'DisplayName','PC₁(t)');

patch([t_ds; flipud(t_ds)], [lo_r_ds; flipud(hi_r_ds)], ...
    [0.78 0.94 0.78], 'EdgeColor','none', 'FaceAlpha',0.45, 'DisplayName','Banda rolling 30d');

plot(t_ds, lo_r_ds, '-', 'Color',[0.10 0.55 0.15], 'LineWidth',1.5, ...
    'DisplayName', sprintf('LOD_{roll}−  30d  (%.2f%% eventi)', 100*mean(isEvt_roll{wi_30})));
plot(t_ds, hi_r_ds, '-', 'Color',[0.10 0.55 0.15], 'LineWidth',1.5, 'HandleVisibility','off');

yline(lod_lo_fix, '--', sprintf('LOD_{fix}− = %.3f  (%.2f%% eventi)', ...
    lod_lo_fix, 100*mean(isEvt_fix)), ...
    'Color',[0.88 0.48 0.08], 'LineWidth',2.0, ...
    'LabelHorizontalAlignment','left', 'FontSize',9);
yline(lod_hi_fix, '--', 'Color',[0.88 0.48 0.08], 'LineWidth',2.0, ...
    'HandleVisibility','off');

hold off;
ax3 = gca;
ax3.XAxis.TickLabelFormat = 'MMM-yy';
ax3.FontSize = 10;
xlabel('Data','FontSize',11); ylabel('PC₁','FontSize',11);
title(sprintf('PC₁(t) — LOD fisso (arancio) vs LOD rolling 30d (verde)  |  k = %.0f', ...
    k_lod), 'FontSize',11);
legend('Location','southwest','FontSize',9);
xlim([t(1) t(end)]);

exportgraphics(fig3, fullfile(outDir,'PC1_fixed_vs_rolling.png'), 'Resolution',300);
fprintf('Salvato: PC1_fixed_vs_rolling.png\n');

%% ════════════════════════════════════════════════════════════════════════
%  PLOT 4 — Confronto eventi settimanali (fisso + 3 rolling)
%% ════════════════════════════════════════════════════════════════════════
weeks_all = unique(dateshift(t, 'start','week'));
nWeeks    = numel(weeks_all);
pct_mat   = zeros(nWeeks, nW+1);   % colonne: fix, 7d, 14d, 30d

for w = 1:nWeeks
    mw = t >= weeks_all(w) & t < weeks_all(w) + days(7);
    if sum(mw) < 10, continue; end
    pct_mat(w,1) = 100 * mean(isEvt_fix(mw));
    for wi = 1:nW
        pct_mat(w, wi+1) = 100 * mean(isEvt_roll{wi}(mw));
    end
end

fig4 = figure('Name','Confronto eventi settimanali', ...
    'Color','w','Position',[40 40 1400 460]);
b = bar(weeks_all, pct_mat, 0.85, 'grouped');
bar_colors = [[0.88 0.55 0.12]; colors_sg];
for bi = 1:nW+1
    b(bi).FaceColor = bar_colors(bi,:);
    b(bi).FaceAlpha = 0.85;
end
ax4 = gca;
ax4.XAxis.TickLabelFormat = 'MMM-yy';
ax4.FontSize = 10;
grid on;
xlabel('Settimana (inizio)','FontSize',11);
ylabel('% campioni flaggati come evento','FontSize',11);
title(sprintf('Confronto eventi settimanali  |  k=%.0f', k_lod),'FontSize',11);
lbls = ['LOD fisso', arrayfun(@(w) sprintf('Rolling %dd', w), windows, 'UniformOutput',false)];
legend(lbls,'Location','northeast','FontSize',9);

exportgraphics(fig4, fullfile(outDir,'events_weekly_comparison.png'), 'Resolution',300);
fprintf('Salvato: events_weekly_comparison.png\n');

%% ── STATS RIEPILOGATIVE ──────────────────────────────────────────────────
fprintf('\n======== RIEPILOGO ========\n');
all_labels = [{'LOD fisso'}, arrayfun(@(w) sprintf('Roll %dd', w), windows, 'UniformOutput',false)];
all_isEvt  = [{isEvt_fix}, isEvt_roll(:)'];
all_lod_lo = [lod_lo_fix,  cellfun(@(x) mean(x,'omitnan'), lod_lo_roll)'];
all_sigma  = [M.sigma_pc1, cellfun(@(x) mean(x,'omitnan'), sigma_roll)'];
all_mu     = [M.mu_pc1,    cellfun(@(x) mean(x,'omitnan'), mu_roll)'];

fprintf('%-12s  %8s  %8s  %9s  %9s\n', 'Metodo','% eventi','LOD_lo','mu_medio','sigma_medio');
fprintf('%s\n', repmat('-',55,1));
for i = 1:numel(all_labels)
    fprintf('%-12s  %7.2f%%  %8.4f  %9.4f  %9.4f\n', ...
        all_labels{i}, 100*mean(all_isEvt{i}), all_lod_lo(i), all_mu(i), all_sigma(i));
end

fprintf('\n--- Concordanza con LOD fisso ---\n');
for wi = 1:nW
    ag   = mean(isEvt_fix == isEvt_roll{wi}) * 100;
    o_f  = mean(isEvt_fix & ~isEvt_roll{wi}) * 100;
    o_r  = mean(~isEvt_fix & isEvt_roll{wi}) * 100;
    fprintf('  Rolling %2dd: concordanza=%.1f%%  solo-fisso=%.2f%%  solo-rolling=%.2f%%\n', ...
        windows(wi), ag, o_f, o_r);
end

% CSV
StatsT = table(all_labels', ...
    cellfun(@(x) 100*mean(x), all_isEvt)', ...
    all_lod_lo', all_mu', all_sigma', ...
    'VariableNames',{'Metodo','Pct_eventi','LOD_lo_medio','mu_medio','sigma_medio'});
writetable(StatsT, fullfile(outDir,'comparison_stats.csv'));

fprintf('\n===== OUTPUT =====\n');
fprintf('  %s\n', outDir);
fprintf('  ├── sigma_window_comparison.png   [CHIAVE]\n');
fprintf('  ├── mu_window_comparison.png\n');
fprintf('  ├── PC1_fixed_vs_rolling.png      (LOD fisso vs rolling 30d)\n');
fprintf('  ├── events_weekly_comparison.png  (4 varianti)\n');
fprintf('  └── comparison_stats.csv\n');
