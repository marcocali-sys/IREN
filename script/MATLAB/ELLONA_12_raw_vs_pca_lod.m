%% ELLONA_12_raw_vs_pca_lod.m
% Confronto diretto: LOD su segnali grezzi (cmos1–4, media normalizzata)
% vs LOD su PC₁.
%
% Domanda chiave: quanti falsi positivi genera un LOD sul grezzo rispetto
% a PC₁? La risposta mostra perché la PCA è necessaria per isolare la
% risposta olfattiva dai confounders ambientali (T, RH, deriva stagionale).
%
% Metodologia
% ───────────
%   Per tutti i metodi si usa la STESSA selezione baseline:
%   intersezione IQR [P25,P75] su tutti e quattro i sensori MOX (identica
%   a ELLONA_08). Questo isola l'effetto della trasformazione del segnale
%   (grezzo vs PCA) tenendo costante la qualità del baseline.
%
%   Metodi confrontati:
%     1. cmos1, cmos2, cmos3, cmos4  (grezzo, LOD individuale)
%     2. media z-normalizzata          (combinazione naive, pesi uguali)
%     3. PC₁                           (combinazione PCA ottimale)
%
%   Per ogni metodo:
%     μ_BL = media del segnale sui punti baseline
%     σ_BL = std  del segnale sui punti baseline
%     LOD⁻ = μ_BL − k·σ_BL
%     evento(t) ⟺ segnale(t) < LOD⁻
%
% Output  IREN/output/raw_vs_pca/
%   ├── weekly_event_rates.png    confronto % eventi/settimana (tutti metodi)
%   ├── temperature_correlation.png  correlaz. eventi vs T settimanale
%   ├── signal_comparison.png     PC₁ vs z-cmos2 nel tempo (esempio)
%   ├── event_overlap.png         Venn/mappa sovrapposizione eventi
%   └── raw_vs_pca_stats.csv      tabella riepilogativa
%
% Marco Calì — PoliMi, Aprile 2026

clear; clc; close all;

%% ── CONFIG ───────────────────────────────────────────────────────────────
scriptDir = fileparts(mfilename('fullpath'));
baseDir   = fullfile(scriptDir, '..', '..');

modelFile = fullfile(baseDir, 'output', 'event_detection', 'pca_model_ELLONA.mat');
dataFile  = fullfile(baseDir, 'data',   'processed',       'monitoring_all.mat');
outDir    = fullfile(baseDir, 'output', 'raw_vs_pca');
if ~isfolder(outDir), mkdir(outDir); end

pLow  = 25; pHigh = 75;
k_lod = 3;

%% ── CARICA ───────────────────────────────────────────────────────────────
fprintf('Caricamento modello PCA... ');
M = load(modelFile);
fprintf('OK\n');

fprintf('Caricamento dati...        '); tic;
S = load(dataFile, 'DATA'); DATA = S.DATA;
fprintf('%.1fs  (%d righe)\n\n', toc, height(DATA));

moxCols = {'cmos1','cmos2','cmos3','cmos4'};
nMox    = numel(moxCols);
t       = DATA.datetime;
N       = numel(t);
T_env   = DATA.temperature;   % per correlazione
dt_s    = seconds(median(diff(t(1:min(5000,end)))));

%% ── SCORE PC₁ ────────────────────────────────────────────────────────────
X_mox = DATA{:, moxCols};
X_pca = X_mox;
for j = 1:nMox
    nm = isnan(X_pca(:,j));
    if any(nm), X_pca(nm,j) = median(X_pca(~nm,j)); end
end
SC  = ((X_pca - M.mu) ./ M.sigma - M.muPCA) * M.coeff;
PC1 = SC(:,1);

%% ── BASELINE MASK (comune a tutti i metodi) ─────────────────────────────
% Stesso criterio di ELLONA_08: IQR [P25,P75] su ciascun MOX, intersezione
fprintf('Calcolo maschera baseline comune...\n');
in_band = true(N,1);
for j = 1:nMox
    x = X_mox(:,j);
    p_lo = prctile(x, pLow);
    p_hi = prctile(x, pHigh);
    in_band = in_band & (x >= p_lo) & (x < p_hi);
end
fprintf('  Punti baseline: %d / %d  (%.1f%%)\n\n', ...
    sum(in_band), N, 100*mean(in_band));

%% ── LOD SUI SEGNALI GREZZI ───────────────────────────────────────────────
fprintf('%-20s  %8s  %10s  %10s  %10s\n', 'Metodo','% eventi','μ_BL','σ_BL','LOD_lo');
fprintf('%s\n', repmat('-',62,1));

% Strutture di output
labels    = [moxCols, {'avg_z','PC1'}];
nMethods  = numel(labels);
isEvt     = false(N, nMethods);
lod_lo_v  = zeros(1, nMethods);
mu_bl_v   = zeros(1, nMethods);
sig_bl_v  = zeros(1, nMethods);
signals   = zeros(N, nMethods);  % segnali z-normalizzati per plot

for j = 1:nMox
    x = X_mox(:,j);
    mu_j  = mean(x(in_band), 'omitnan');
    sg_j  = std( x(in_band), 'omitnan');
    lod_j = mu_j - k_lod * sg_j;
    isEvt(:,j)  = x < lod_j;
    lod_lo_v(j) = lod_j;
    mu_bl_v(j)  = mu_j;
    sig_bl_v(j) = sg_j;
    signals(:,j) = (x - mu_j) / sg_j;   % z-score per confronto visivo
    fprintf('%-20s  %7.2f%%  %10.2f  %10.2f  %10.2f\n', ...
        moxCols{j}, 100*mean(isEvt(:,j)), mu_j, sg_j, lod_j);
end

%% ── LOD SULLA MEDIA Z-NORMALIZZATA ──────────────────────────────────────
% z_i = (cmos_i - μ_BL_i) / σ_BL_i  → media dei 4 z-score per campione
z_each  = zeros(N, nMox);
for j = 1:nMox
    mu_j = mean(X_mox(in_band,j),'omitnan');
    sg_j = std( X_mox(in_band,j),'omitnan');
    z_each(:,j) = (X_mox(:,j) - mu_j) / sg_j;
end
avg_z = mean(z_each, 2);

mu_avg  = mean(avg_z(in_band), 'omitnan');
sg_avg  = std( avg_z(in_band), 'omitnan');
lod_avg = mu_avg - k_lod * sg_avg;
j_avg   = nMox + 1;
isEvt(:,j_avg)  = avg_z < lod_avg;
lod_lo_v(j_avg) = lod_avg;
mu_bl_v(j_avg)  = mu_avg;
sig_bl_v(j_avg) = sg_avg;
signals(:,j_avg) = avg_z;
fprintf('%-20s  %7.2f%%  %10.4f  %10.4f  %10.4f\n', ...
    'avg_z', 100*mean(isEvt(:,j_avg)), mu_avg, sg_avg, lod_avg);

%% ── LOD PC₁ (dal modello) ────────────────────────────────────────────────
j_pc1 = nMox + 2;
lod_pc1 = M.lod_lower_pc1;
isEvt(:,j_pc1)  = PC1 < lod_pc1;
lod_lo_v(j_pc1) = lod_pc1;
mu_bl_v(j_pc1)  = M.mu_pc1;
sig_bl_v(j_pc1) = M.sigma_pc1;
signals(:,j_pc1) = PC1;
fprintf('%-20s  %7.2f%%  %10.4f  %10.4f  %10.4f\n', ...
    'PC1', 100*mean(isEvt(:,j_pc1)), M.mu_pc1, M.sigma_pc1, lod_pc1);
fprintf('%s\n', repmat('-',62,1));

%% ── STATISTICHE SETTIMANALI ──────────────────────────────────────────────
weeks    = unique(dateshift(t,'start','week'));
nWeeks   = numel(weeks);
pct_wk   = zeros(nWeeks, nMethods);   % % eventi per settimana
T_wk     = zeros(nWeeks, 1);          % temperatura media settimanale

for w = 1:nWeeks
    mw = t >= weeks(w) & t < weeks(w) + days(7);
    if sum(mw) < 10, continue; end
    for m = 1:nMethods
        pct_wk(w,m) = 100 * mean(isEvt(mw,m));
    end
    T_wk(w) = mean(T_env(mw), 'omitnan');
end

% Correlazione Pearson tra % eventi settimanali e temperatura
valid_wk = T_wk ~= 0 & ~isnan(T_wk);
rho = zeros(1, nMethods);
for m = 1:nMethods
    r = corrcoef(T_wk(valid_wk), pct_wk(valid_wk,m));
    rho(m) = r(1,2);
end

fprintf('\n--- Correlazione eventi vs temperatura (Pearson r) ---\n');
for m = 1:nMethods
    fprintf('  %-20s:  r = %+.3f\n', labels{m}, rho(m));
end

%% ════════════════════════════════════════════════════════════════════════
%  PLOT 1 — % eventi per settimana: tutti i metodi
%% ════════════════════════════════════════════════════════════════════════
colors = [0.70 0.40 0.12;   % cmos1
          0.93 0.60 0.08;   % cmos2
          0.30 0.65 0.20;   % cmos3
          0.12 0.48 0.78;   % cmos4
          0.55 0.18 0.72;   % avg_z
          0.85 0.12 0.08];  % PC1

fig1 = figure('Color','w','Position',[40 40 1500 520]);
tl1  = tiledlayout(2,1,'TileSpacing','compact','Padding','compact');

% Pannello superiore: segnali grezzi + avg_z
ax_top = nexttile(tl1);
b_top  = bar(weeks, pct_wk(:,1:nMox+1), 0.85, 'grouped');
for i = 1:nMox+1, b_top(i).FaceColor = colors(i,:); b_top(i).FaceAlpha = 0.85; end
ax_top.XAxis.TickLabelFormat = 'MMM-yy'; ax_top.FontSize = 9; grid(ax_top,'on');
ylabel(ax_top,'% eventi','FontSize',10);
title(ax_top,'LOD su segnali grezzi e media normalizzata','FontSize',11);
legend(ax_top, [moxCols, {'avg\_z'}], 'Location','northwest','FontSize',8,'NumColumns',3);
xlim(ax_top,[weeks(1)-days(7) weeks(end)+days(7)]);

% Pannello inferiore: PC1 (riferimento)
ax_bot = nexttile(tl1);
bar(weeks, pct_wk(:,j_pc1), 0.75, 'FaceColor',colors(j_pc1,:), 'FaceAlpha',0.85);
ax_bot.XAxis.TickLabelFormat = 'MMM-yy'; ax_bot.FontSize = 9; grid(ax_bot,'on');
ylabel(ax_bot,'% eventi','FontSize',10);
title(ax_bot,sprintf('LOD su PC₁  (riferimento)  —  %.2f%% totale', ...
    100*mean(isEvt(:,j_pc1))),'FontSize',11);
xlim(ax_bot,[weeks(1)-days(7) weeks(end)+days(7)]);

exportgraphics(fig1, fullfile(outDir,'weekly_event_rates.png'), 'Resolution',300);
fprintf('\nSalvato: weekly_event_rates.png\n');

%% ════════════════════════════════════════════════════════════════════════
%  PLOT 2 — Correlazione eventi vs temperatura
%% ════════════════════════════════════════════════════════════════════════
fig2 = figure('Color','w','Position',[40 40 1400 600]);
tl2  = tiledlayout(2, 3, 'TileSpacing','compact','Padding','compact');

for m = 1:nMethods
    ax = nexttile(tl2);
    scatter(ax, T_wk(valid_wk), pct_wk(valid_wk,m), 30, colors(m,:), 'filled', 'MarkerFaceAlpha',0.6);
    hold(ax,'on');
    % Linea di tendenza lineare
    cf = polyfit(T_wk(valid_wk), pct_wk(valid_wk,m), 1);
    T_fit = linspace(min(T_wk(valid_wk)), max(T_wk(valid_wk)), 50);
    plot(ax, T_fit, polyval(cf,T_fit), '-', 'Color', colors(m,:)*0.6, 'LineWidth',1.8);
    hold(ax,'off');
    xlabel(ax,'Temperatura media settimanale (°C)','FontSize',9);
    ylabel(ax,'% eventi','FontSize',9);
    title(ax, sprintf('%s   r = %+.3f', labels{m}, rho(m)), 'FontSize',10);
    grid(ax,'on'); ax.FontSize = 9;
end

sgtitle('Correlazione Pearson tra tasso eventi settimanale e temperatura', 'FontSize',12);
exportgraphics(fig2, fullfile(outDir,'temperature_correlation.png'), 'Resolution',300);
fprintf('Salvato: temperature_correlation.png\n');

%% ════════════════════════════════════════════════════════════════════════
%  PLOT 3 — Serie temporale: z-cmos2 vs PC₁ (esempio più illustrativo)
%  Mostra visivamente come il drift termico stagionale contamina il grezzo
%  ma non PC₁.
%% ════════════════════════════════════════════════════════════════════════
step_ds = max(1, floor(N/150000));
idx_ds  = 1:step_ds:N;
t_ds    = t(idx_ds);

% Identifica il sensore grezzo con la correlazione più alta con T
[~, worst_j] = max(abs(rho(1:nMox)));

fig3 = figure('Color','w','Position',[40 40 1500 600]);
tl3  = tiledlayout(2,1,'TileSpacing','compact','Padding','compact');

ax1 = nexttile(tl3);
sig_worst_ds = signals(idx_ds, worst_j);
hold(ax1,'on'); grid(ax1,'on');
plot(ax1, t_ds, sig_worst_ds, '-', 'Color',[0.70 0.80 0.93], 'LineWidth',0.4);
yline(ax1, -k_lod, '--', sprintf('LOD⁻ = −%.0f (su z-score)', k_lod), ...
    'Color',[0.88 0.35 0.08], 'LineWidth',2, 'LabelHorizontalAlignment','left','FontSize',9);
% Evidenzia eventi
evt_j = isEvt(:,worst_j);
plot(ax1, t(evt_j & mod((1:N)',step_ds)==0), signals(evt_j & mod((1:N)',step_ds)==0, worst_j), ...
    '.', 'Color',[0.88 0.35 0.08], 'MarkerSize',2);
hold(ax1,'off');
ax1.XAxis.TickLabelFormat = 'MMM-yy'; ax1.FontSize = 9;
ylabel(ax1, sprintf('z-score  %s', labels{worst_j}),'FontSize',10);
title(ax1, sprintf('Segnale grezzo z-normalizzato  %s  (r_{T} = %+.3f)  —  eventi: %.2f%%', ...
    labels{worst_j}, rho(worst_j), 100*mean(isEvt(:,worst_j))), 'FontSize',11);
xlim(ax1, [t(1) t(end)]);

ax2 = nexttile(tl3);
pc1_ds = signals(idx_ds, j_pc1);
hold(ax2,'on'); grid(ax2,'on');
plot(ax2, t_ds, pc1_ds, '-', 'Color',[0.70 0.80 0.93], 'LineWidth',0.4);
yline(ax2, lod_pc1, '--', sprintf('LOD⁻ = %.3f', lod_pc1), ...
    'Color',[0.12 0.45 0.78], 'LineWidth',2, 'LabelHorizontalAlignment','left','FontSize',9);
evt_pc = isEvt(:,j_pc1);
plot(ax2, t(evt_pc & mod((1:N)',step_ds)==0), PC1(evt_pc & mod((1:N)',step_ds)==0), ...
    '.', 'Color',[0.12 0.45 0.78], 'MarkerSize',2);
hold(ax2,'off');
ax2.XAxis.TickLabelFormat = 'MMM-yy'; ax2.FontSize = 9;
ylabel(ax2,'PC₁','FontSize',10);
title(ax2, sprintf('PC₁  (r_{T} = %+.3f)  —  eventi: %.2f%%', ...
    rho(j_pc1), 100*mean(isEvt(:,j_pc1))), 'FontSize',11);
xlim(ax2, [t(1) t(end)]);

exportgraphics(fig3, fullfile(outDir,'signal_comparison.png'), 'Resolution',300);
fprintf('Salvato: signal_comparison.png\n');

%% ════════════════════════════════════════════════════════════════════════
%  PLOT 4 — Sovrapposizione eventi: quanti eventi del grezzo NON sono in PC₁?
%% ════════════════════════════════════════════════════════════════════════
% Per ciascun metodo: eventi esclusivi (non presenti in PC₁) = falsi positivi
fig4 = figure('Color','w','Position',[40 40 900 480]);
ax4  = axes(fig4); hold(ax4,'on'); grid(ax4,'on');

pct_total    = 100 * mean(isEvt);        % tasso eventi totale
pct_in_pc1   = zeros(1, nMethods);       % overlap con PC₁
pct_exclusive = zeros(1, nMethods);      % solo nel metodo (potenziali FP)

for m = 1:nMethods
    pct_in_pc1(m)    = 100 * mean(isEvt(:,m) &  isEvt(:,j_pc1));
    pct_exclusive(m) = 100 * mean(isEvt(:,m) & ~isEvt(:,j_pc1));
end

x_pos = 1:nMethods;
b1 = bar(ax4, x_pos, pct_in_pc1,    0.6, 'FaceAlpha',0.9);
b2 = bar(ax4, x_pos, pct_exclusive, 0.6, 'FaceAlpha',0.9, 'BottomOffset', pct_in_pc1);

% Colora le barre per metodo
for m = 1:nMethods
    b1.FaceColor = 'flat'; b1.CData(m,:) = colors(m,:) * 0.7;
    b2.FaceColor = 'flat'; b2.CData(m,:) = [0.92 0.15 0.08];
end
b1.FaceColor = 'flat'; b2.FaceColor = 'flat';

% Testo % sopra ogni barra
for m = 1:nMethods
    text(ax4, m, pct_total(m) + 0.3, sprintf('%.1f%%', pct_exclusive(m)), ...
        'HorizontalAlignment','center', 'FontSize',8, 'Color',[0.7 0 0], 'FontWeight','bold');
end

ax4.XTick = x_pos;
ax4.XTickLabel = strrep(labels,'_','\_');
ax4.XTickLabelRotation = 20;
ax4.FontSize = 10;
ylabel(ax4,'% campioni','FontSize',11);
title(ax4,sprintf('Sovrapposizione eventi con PC₁  (rosso = esclusivi del metodo, potenziali falsi positivi)'), ...
    'FontSize',11);
legend(ax4, {'Overlap con PC₁','Solo questo metodo (FP potenziali)'}, ...
    'Location','northwest','FontSize',9);

exportgraphics(fig4, fullfile(outDir,'event_overlap.png'), 'Resolution',300);
fprintf('Salvato: event_overlap.png\n');

%% ── RIEPILOGO ────────────────────────────────────────────────────────────
fprintf('\n======== RIEPILOGO ========\n');
fprintf('%-20s  %8s  %10s  %12s  %12s\n', ...
    'Metodo','% eventi','r(T)','Overlap PC₁','Solo metodo (FP)');
fprintf('%s\n', repmat('-',70,1));
for m = 1:nMethods
    fprintf('%-20s  %7.2f%%  %+10.3f  %11.2f%%  %12.2f%%\n', ...
        labels{m}, pct_total(m), rho(m), pct_in_pc1(m), pct_exclusive(m));
end
fprintf('%s\n', repmat('-',70,1));
fprintf('\n  Interpretazione: "Solo metodo" = eventi non confermati da PC₁\n');
fprintf('  Se r(T) >> r_PC1 → il metodo è contaminato dal drift termico\n');

% CSV
T_out = table(labels', pct_total', rho', pct_in_pc1', pct_exclusive', ...
    'VariableNames', {'Metodo','Pct_eventi','r_temperatura','Pct_overlap_PC1','Pct_esclusivi_FP'});
writetable(T_out, fullfile(outDir,'raw_vs_pca_stats.csv'));

fprintf('\n===== OUTPUT =====\n');
fprintf('  %s\n', outDir);
fprintf('  ├── weekly_event_rates.png       (confronto settimanale tutti metodi)\n');
fprintf('  ├── temperature_correlation.png  (scatter eventi vs T, r per metodo)\n');
fprintf('  ├── signal_comparison.png        (z-grezzo vs PC₁ nel tempo)\n');
fprintf('  ├── event_overlap.png            (sovrapposizione con PC₁)\n');
fprintf('  └── raw_vs_pca_stats.csv\n');
