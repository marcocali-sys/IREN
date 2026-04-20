%% ELLONA_11_rolling_lod.m
% LOD mobile (rolling) su PC₁ — confronto con LOD fisso.
%
% Metodologia
% ───────────
%   ┌─────────────────────────────────────────────────────────────────────┐
%   │  Modello PCA  →  FISSO  (output ELLONA_08)                          │
%   │                                                                     │
%   │  LOD fisso   : μ_BL ± k·σ_BL  (calcolato una tantum su tutta la    │
%   │                baseline globale)                                    │
%   │                                                                     │
%   │  LOD rolling : per ogni giorno t,                                   │
%   │                  finestra causale [t−7d, t)                         │
%   │                  → selezione baseline IQR [P25,P75] sui MOX raw     │
%   │                  → μ(t) e σ(t) sui PC₁_baseline della finestra      │
%   │                  → LOD_lo(t) = μ(t) − k·σ(t)                       │
%   │                LOD(t) adattivo al drift locale del sensore           │
%   └─────────────────────────────────────────────────────────────────────┘
%
% Output  IREN/output/rolling_lod/
%   ├── PC1_fixed_vs_rolling.png      overview con entrambe le bande
%   ├── rolling_mu_sigma.png          evoluzione μ(t) e σ(t)
%   ├── events_weekly_comparison.png  barchart eventi settimanali
%   ├── lod_disagreement.png          dove i due metodi discordano
%   └── comparison_stats.csv          metriche riepilogative
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
window_days = 7;     % ampiezza finestra rolling (giorni)
step_days   = 1;     % passo griglia valutazione (giorni)
pLow        = 25;    % percentile inferiore IQR (stesso di ELLONA_08)
pHigh       = 75;    % percentile superiore IQR
k_lod       = 3;     % moltiplicatore LOD (k·σ)
minBL       = 100;   % min punti baseline per validare una finestra

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

%% ── LOD ROLLING ──────────────────────────────────────────────────────────
fprintf('\n--- LOD rolling (finestra %dd, step %dd) ---\n', window_days, step_days);
X_mox = DATA{:, moxCols};   % valori raw per selezione IQR

[lod_lo_roll, lod_hi_roll, mu_roll, sigma_roll] = ellona_rolling_lod( ...
    t, PC1, X_mox, pLow, pHigh, k_lod, window_days, step_days, minBL, ...
    lod_lo_fix, lod_hi_fix);

isEvt_roll = PC1 < lod_lo_roll;

fprintf('  LOD_lo medio = %.4f  (range: [%.4f, %.4f])\n', ...
    mean(lod_lo_roll,'omitnan'), min(lod_lo_roll), max(lod_lo_roll));
fprintf('  LOD_hi medio = %.4f  (range: [%.4f, %.4f])\n', ...
    mean(lod_hi_roll,'omitnan'), min(lod_hi_roll), max(lod_hi_roll));
fprintf('  sigma medio  = %.4f  (range: [%.4f, %.4f])\n', ...
    mean(sigma_roll,'omitnan'),  min(sigma_roll),  max(sigma_roll));
fprintf('  Eventi: %d / %d  (%.2f%%)\n', ...
    sum(isEvt_roll), numel(PC1), 100*mean(isEvt_roll));

%% ── CONCORDANZA ──────────────────────────────────────────────────────────
agree      = mean( isEvt_fix ==  isEvt_roll) * 100;
only_fix   = mean( isEvt_fix & ~isEvt_roll)  * 100;
only_roll  = mean(~isEvt_fix &  isEvt_roll)  * 100;
fprintf('\nConcordanza totale  : %.1f%%\n', agree);
fprintf('Solo LOD fisso      : %.2f%%  ← eventi persi dal rolling\n',   only_fix);
fprintf('Solo LOD rolling    : %.2f%%  ← nuovi eventi rilevati dal rolling\n', only_roll);

%% ── DOWNSAMPLE PER PLOT ──────────────────────────────────────────────────
step_ds = max(1, floor(numel(t)/120000));
idx_ds  = 1:step_ds:numel(t);
t_ds    = t(idx_ds);
p1_ds   = PC1(idx_ds);
lo_r_ds = lod_lo_roll(idx_ds);
hi_r_ds = lod_hi_roll(idx_ds);
mu_ds   = mu_roll(idx_ds);
sg_ds   = sigma_roll(idx_ds);

%% ════════════════════════════════════════════════════════════════════════
%  PLOT 1 — PC₁(t): LOD fisso (arancio tratteggiate) vs rolling (verde)
%% ════════════════════════════════════════════════════════════════════════
fig1 = figure('Name','PC1 — Fixed vs Rolling LOD', ...
    'Color','w','Position',[40 40 1500 620]);
hold on; grid on;

% Segnale completo
plot(t_ds, p1_ds, '-', 'Color',[0.70 0.80 0.93], 'LineWidth',0.4);

% Banda LOD rolling (fill verde semi-trasparente)
patch([t_ds; flipud(t_ds)], [lo_r_ds; flipud(hi_r_ds)], ...
    [0.78 0.94 0.78], 'EdgeColor','none', 'FaceAlpha',0.45);

% LOD rolling (bordi verdi solidi)
plot(t_ds, lo_r_ds, '-', 'Color',[0.10 0.55 0.15], 'LineWidth',1.5);
plot(t_ds, hi_r_ds, '-', 'Color',[0.10 0.55 0.15], 'LineWidth',1.5);

% LOD fisso (tratteggiate arancio)
yline(lod_lo_fix, '--', sprintf('LOD_{fix}− = %.3f', lod_lo_fix), ...
    'Color',[0.88 0.48 0.08], 'LineWidth',2.0, ...
    'LabelHorizontalAlignment','left', 'FontSize',9);
yline(lod_hi_fix, '--', sprintf('LOD_{fix}+ = %.3f', lod_hi_fix), ...
    'Color',[0.88 0.48 0.08], 'LineWidth',2.0, ...
    'LabelHorizontalAlignment','left', 'FontSize',9);

hold off;
ax1 = gca;
ax1.XAxis.TickLabelFormat = 'MMM-yy';
ax1.FontSize = 10;
xlabel('Data','FontSize',11);
ylabel('PC₁','FontSize',11);
title(sprintf(['PC₁(t) — LOD fisso (arancio) vs LOD rolling (verde, finestra %dd)' ...
    '  |  k = %.0f  |  LOD−: fisso=%.2f%%  rolling=%.2f%%'], ...
    window_days, k_lod, 100*mean(isEvt_fix), 100*mean(isEvt_roll)), 'FontSize',11);
legend({'PC₁(t)', sprintf('Banda LOD rolling'), ...
    'LOD_{roll}−', 'LOD_{roll}+', 'LOD_{fix}±'}, ...
    'Location','southwest', 'FontSize',9);
xlim([t(1) t(end)]);

exportgraphics(fig1, fullfile(outDir,'PC1_fixed_vs_rolling.png'), 'Resolution',300);
fprintf('\nSalvato: PC1_fixed_vs_rolling.png\n');

%% ════════════════════════════════════════════════════════════════════════
%  PLOT 2 — Evoluzione μ(t) e σ(t) rolling
%% ════════════════════════════════════════════════════════════════════════
fig2 = figure('Name','Rolling μ(t) e σ(t)', ...
    'Color','w','Position',[40 40 1400 500]);
tl = tiledlayout(2,1,'TileSpacing','compact','Padding','compact');

ax_mu = nexttile(tl);
plot(ax_mu, t_ds, mu_ds, '-', 'Color',[0.18 0.44 0.82], 'LineWidth',1.3);
hold(ax_mu,'on');
yline(ax_mu, M.mu_pc1, '--', sprintf('μ_{fisso} = %.4f', M.mu_pc1), ...
    'Color',[0.88 0.48 0.08], 'LineWidth',1.8, 'FontSize',9);
hold(ax_mu,'off');
ax_mu.XAxis.TickLabelFormat = 'MMM-yy';
ax_mu.XTickLabelRotation = 0;
ylabel(ax_mu,'μ_{roll}(t)','FontSize',10); grid(ax_mu,'on');
title(ax_mu,'Media rolling PC₁  (finestra settimana precedente)','FontSize',11);
xlim(ax_mu,[t(1) t(end)]);

ax_sg = nexttile(tl);
plot(ax_sg, t_ds, sg_ds, '-', 'Color',[0.58 0.14 0.70], 'LineWidth',1.3);
hold(ax_sg,'on');
yline(ax_sg, M.sigma_pc1, '--', sprintf('σ_{fisso} = %.4f', M.sigma_pc1), ...
    'Color',[0.88 0.48 0.08], 'LineWidth',1.8, 'FontSize',9);
hold(ax_sg,'off');
ax_sg.XAxis.TickLabelFormat = 'MMM-yy';
ax_sg.XTickLabelRotation = 0;
ylabel(ax_sg,'σ_{roll}(t)','FontSize',10); grid(ax_sg,'on');
title(ax_sg,'Dev. std rolling PC₁  (finestra settimana precedente)','FontSize',11);
xlim(ax_sg,[t(1) t(end)]);

exportgraphics(fig2, fullfile(outDir,'rolling_mu_sigma.png'), 'Resolution',300);
fprintf('Salvato: rolling_mu_sigma.png\n');

%% ════════════════════════════════════════════════════════════════════════
%  PLOT 3 — Confronto eventi settimanali
%% ════════════════════════════════════════════════════════════════════════
weeks    = unique(dateshift(t, 'start','week'));
nW       = numel(weeks);
pct_fix  = zeros(nW,1);
pct_roll = zeros(nW,1);
n_pts_wk = zeros(nW,1);

for w = 1:nW
    mw = t >= weeks(w) & t < weeks(w) + days(7);
    n_pts_wk(w) = sum(mw);
    if n_pts_wk(w) < 10, continue; end
    pct_fix(w)  = 100 * sum(isEvt_fix(mw))  / n_pts_wk(w);
    pct_roll(w) = 100 * sum(isEvt_roll(mw)) / n_pts_wk(w);
end

fig3 = figure('Name','Confronto eventi settimanali', ...
    'Color','w','Position',[40 40 1400 440]);
b = bar(weeks, [pct_fix pct_roll], 0.8, 'grouped');
b(1).FaceColor = [0.88 0.55 0.12]; b(1).FaceAlpha = 0.85;
b(2).FaceColor = [0.12 0.58 0.18]; b(2).FaceAlpha = 0.85;
ax3 = gca;
ax3.XAxis.TickLabelFormat = 'MMM-yy';
ax3.FontSize = 10;
grid on;
xlabel('Settimana (inizio)','FontSize',11);
ylabel('% campioni flaggati come evento','FontSize',11);
title(sprintf('Confronto eventi settimanali  |  k=%.0f  |  finestra rolling=%dd', ...
    k_lod, window_days),'FontSize',11);
legend({'LOD fisso','LOD rolling'},'Location','northeast','FontSize',10);

exportgraphics(fig3, fullfile(outDir,'events_weekly_comparison.png'), 'Resolution',300);
fprintf('Salvato: events_weekly_comparison.png\n');

%% ════════════════════════════════════════════════════════════════════════
%  PLOT 4 — Discordanza (dove i due metodi divergono)
%% ════════════════════════════════════════════════════════════════════════
% Tre stati: concordanza / solo-fisso / solo-rolling
only_f_mask = isEvt_fix  & ~isEvt_roll;
only_r_mask = isEvt_roll & ~isEvt_fix;
agree_mask  = isEvt_fix  &  isEvt_roll;

fig4 = figure('Name','Discordanza LOD fisso vs rolling', ...
    'Color','w','Position',[40 40 1500 380]);
hold on; grid on;

% Segnale base (grigio chiaro)
plot(t_ds, p1_ds, '-', 'Color',[0.80 0.85 0.92], 'LineWidth',0.4);

% Concordanza (entrambi: rosso)
plot(t(agree_mask), PC1(agree_mask), '.', ...
    'Color',[0.82 0.10 0.06], 'MarkerSize',3, 'DisplayName','Evento (entrambi)');

% Solo fisso (arancio)
plot(t(only_f_mask), PC1(only_f_mask), '.', ...
    'Color',[0.92 0.52 0.08], 'MarkerSize',4, 'DisplayName','Solo LOD fisso');

% Solo rolling (blu-verde)
plot(t(only_r_mask), PC1(only_r_mask), '.', ...
    'Color',[0.05 0.55 0.72], 'MarkerSize',4, 'DisplayName','Solo LOD rolling');

% LOD fisso
yline(lod_lo_fix,'--','Color',[0.88 0.48 0.08],'LineWidth',1.5);
% LOD rolling (media)
plot(t_ds, lo_r_ds, '-', 'Color',[0.10 0.55 0.15], 'LineWidth',1.2);

hold off;
ax4 = gca;
ax4.XAxis.TickLabelFormat = 'MMM-yy';
ax4.FontSize = 10;
xlabel('Data','FontSize',11); ylabel('PC₁','FontSize',11);
title(sprintf(['Discordanza  |  concordano: %.1f%%  |  ' ...
    'solo-fisso: %.2f%%  |  solo-rolling: %.2f%%'], ...
    agree, only_fix, only_roll),'FontSize',11);
legend({'PC₁','Evento (entrambi)','Solo LOD fisso','Solo LOD rolling'}, ...
    'Location','southwest','FontSize',9);
xlim([t(1) t(end)]);

exportgraphics(fig4, fullfile(outDir,'lod_disagreement.png'), 'Resolution',300);
fprintf('Salvato: lod_disagreement.png\n');

%% ── STATS RIEPILOGATIVE ──────────────────────────────────────────────────
fprintf('\n======== RIEPILOGO CONFRONTO ========\n');
hdr = '%-25s  %12s  %12s\n';
row_n = '%-25s  %12.0f  %12.0f\n';
row_f = '%-25s  %12.4f  %12.4f\n';
row_p = '%-25s  %11.2f%%  %11.2f%%\n';

fprintf(hdr, 'Metrica','LOD fisso','LOD rolling');
fprintf('%s\n', repmat('-',52,1));
fprintf(row_n, 'Campioni totali',      numel(PC1),          numel(PC1));
fprintf(row_n, 'N eventi (LOD−)',      sum(isEvt_fix),      sum(isEvt_roll));
fprintf(row_p, '% eventi (LOD−)',      100*mean(isEvt_fix), 100*mean(isEvt_roll));
fprintf(row_f, 'LOD− medio',           lod_lo_fix,          mean(lod_lo_roll,'omitnan'));
fprintf(row_f, 'LOD+ medio',           lod_hi_fix,          mean(lod_hi_roll,'omitnan'));
fprintf(row_f, 'μ_BL medio',           M.mu_pc1,            mean(mu_roll,'omitnan'));
fprintf(row_f, 'σ_BL medio',           M.sigma_pc1,         mean(sigma_roll,'omitnan'));
fprintf(row_f, 'σ_BL min',             M.sigma_pc1,         min(sigma_roll));
fprintf(row_f, 'σ_BL max',             M.sigma_pc1,         max(sigma_roll));
fprintf('%s\n', repmat('-',52,1));
fprintf('Concordanza totale   : %.2f%%\n', agree);
fprintf('Solo LOD fisso       : %.2f%%  ← eventi non rilevati dal rolling\n', only_fix);
fprintf('Solo LOD rolling     : %.2f%%  ← nuovi eventi rilevati dal rolling\n', only_roll);

% Salva CSV
StatsT = table( ...
    {'LOD_fisso';   'LOD_rolling'}, ...
    [sum(isEvt_fix);   sum(isEvt_roll)], ...
    [100*mean(isEvt_fix); 100*mean(isEvt_roll)], ...
    [lod_lo_fix;       mean(lod_lo_roll,'omitnan')], ...
    [lod_hi_fix;       mean(lod_hi_roll,'omitnan')], ...
    [M.mu_pc1;         mean(mu_roll,'omitnan')], ...
    [M.sigma_pc1;      mean(sigma_roll,'omitnan')], ...
    'VariableNames', {'Metodo','N_eventi','Pct_eventi', ...
    'LOD_lo_medio','LOD_hi_medio','mu_medio','sigma_medio'});
writetable(StatsT, fullfile(outDir,'comparison_stats.csv'));

fprintf('\n===== OUTPUT =====\n');
fprintf('  %s\n', outDir);
fprintf('  ├── PC1_fixed_vs_rolling.png\n');
fprintf('  ├── rolling_mu_sigma.png\n');
fprintf('  ├── events_weekly_comparison.png\n');
fprintf('  ├── lod_disagreement.png\n');
fprintf('  └── comparison_stats.csv\n');
