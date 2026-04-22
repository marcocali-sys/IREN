%% ELLONA_13_humidity_compensation.m
%
% Analisi della correlazione tra sensori MOX e umidità assoluta (AH).
% Modello power law per compensazione dell'umidità:
%
%       y_ref = A * AH^k1 + c
%
% Procedura:
%   1. Calcolo Absolute Humidity [g/m³] da T [°C] e RH [%]
%   2. Resample @1h (per fitting efficiente)
%   3. Selezione baseline (IQR weekly [P25,P75]) — dati senza odore dominante
%   4. Fit power law con nlinfit per ciascun sensore MOX
%   5. Valutazione bontà del fit: R², RMSE, residui
%   6. Analisi mensile: quanto AH spiega la deriva stagionale?
%   7. Segnale compensato: confronto stagionale prima/dopo
%
% Domanda chiave: la deriva ×59 di cmos4 (mar→set) è spiegata dall'AH,
%   o c'è una componente non riconducibile all'umidità (es. O₃/NOₓ estivi)?
%
% Output → IREN/output/humidity_compensation/
%
% Marco Calì — PoliMi, Aprile 2026

clear; clc; close all;

%% ══════════════════════════════════════════════════════════════════════════
%% CONFIG
%% ══════════════════════════════════════════════════════════════════════════
scriptDir = fileparts(mfilename('fullpath'));
baseDir   = fullfile(scriptDir, '..', '..');

dataFile  = fullfile(baseDir, 'data', 'processed', 'monitoring_all.mat');
outDir    = fullfile(baseDir, 'output', 'humidity_compensation');
if ~isfolder(outDir), mkdir(outDir); end

moxCols = ["cmos1", "cmos2", "cmos3", "cmos4"];
nMox    = numel(moxCols);

% Parametri baseline
pLow  = 25;
pHigh = 75;

% PoliMi palette
C_blu    = [0   56  102]/255;
C_azz    = [20  100 160]/255;
C_azzlt  = [107 163 214]/255;
C_grig   = [88  89  91 ]/255;
C_rosso  = [181 57  78 ]/255;
C_arancio= [232 163 61 ]/255;
C_verde  = [74  155 110]/255;
C_bianco = [1   1   1  ];

SENSOR_COLORS = [C_blu; C_azz; C_azzlt; C_rosso];
MONTH_CMAP    = parula(10);   % mar(1) → dic(10)

fprintf('=== ELLONA_13 — Humidity Compensation Analysis ===\n\n');

%% ══════════════════════════════════════════════════════════════════════════
%% 1. LOAD DATI
%% ══════════════════════════════════════════════════════════════════════════
fprintf('1. Caricamento dati...\n');
t0 = tic;
load(dataFile, 'DATA');
nRows = height(DATA);
fprintf('   Righe: %d  |  %s → %s  (%.1fs)\n\n', nRows, ...
    datestr(DATA.datetime(1),'dd-mmm-yyyy'), ...
    datestr(DATA.datetime(end),'dd-mmm-yyyy'), toc(t0));

t_raw   = DATA.datetime;
T_C_raw = DATA.temperature;
RH_raw  = DATA.humidity;
X_raw   = DATA{:, cellstr(moxCols)};  % N×4

%% ══════════════════════════════════════════════════════════════════════════
%% 2. CALCOLO ABSOLUTE HUMIDITY
%% ══════════════════════════════════════════════════════════════════════════
% Formula di Magnus → vapore saturo → AH [g/m³]
%   e_s  = 6.112 * exp(17.67 * T / (T + 243.5))  [hPa]
%   e    = (RH/100) * e_s                          [hPa]
%   AH   = (e * 1000 * M_w) / (R * T_K)           [g/m³]
%        = e * 2165.0 / (T_K)
%   con M_w = 18.016 g/mol, R = 8.314 J/(mol·K)
fprintf('2. Calcolo Absolute Humidity (AH)...\n');
e_s_raw  = 6.112 .* exp(17.67 .* T_C_raw ./ (T_C_raw + 243.5));
% e_s è in hPa → moltiplico per 100 per avere Pa, poi AH = M_w/R * e_Pa / T_K
% M_w/R = 18.016/8.314 = 2.1674  →  coefficiente = 2.1674 * 100 = 216.74
AH_raw   = (RH_raw./100) .* e_s_raw .* 216.74 ./ (T_C_raw + 273.15);

fprintf('   AH range: %.2f – %.2f g/m³   media: %.2f   mediana: %.2f\n\n', ...
    min(AH_raw), max(AH_raw), mean(AH_raw), median(AH_raw));

%% ══════════════════════════════════════════════════════════════════════════
%% 3. RESAMPLE @1h (fitting efficiente)
%% ══════════════════════════════════════════════════════════════════════════
fprintf('3. Resample @1h...\n');
TT_raw = timetable(t_raw, T_C_raw, RH_raw, AH_raw, ...
    X_raw(:,1), X_raw(:,2), X_raw(:,3), X_raw(:,4), ...
    'VariableNames', {'T_C','RH','AH','cmos1','cmos2','cmos3','cmos4'});
TT_1h  = retime(TT_raw, 'hourly', 'mean');
TT_1h  = rmmissing(TT_1h);

t_h    = TT_1h.Properties.RowTimes;
T_C    = TT_1h.T_C;
RH_h   = TT_1h.RH;
AH     = TT_1h.AH;
X_1h   = TT_1h{:, cellstr(moxCols)};  % N_h × 4
months = month(t_h);
nH     = height(TT_1h);

fprintf('   Punti @1h: %d  (%.1f%% dei dati originali)\n\n', ...
    nH, 100*nH/(nRows/360));

%% ══════════════════════════════════════════════════════════════════════════
%% 4. SELEZIONE BASELINE (IQR weekly [P25,P75])
%% ══════════════════════════════════════════════════════════════════════════
fprintf('4. Selezione baseline IQR weekly...\n');
week_id   = floor(datenum(t_h) / 7);      % indice unico per settimana
wks_uniq  = unique(week_id);
bl_mask   = true(nH, 1);

for wk = wks_uniq'
    idx = week_id == wk;
    for j = 1:nMox
        y_wk  = X_1h(idx, j);
        p25   = prctile(y_wk, pLow);
        p75   = prctile(y_wk, pHigh);
        bl_mask(idx) = bl_mask(idx) & (y_wk >= p25) & (y_wk <= p75);
    end
end

nBL = sum(bl_mask);
fprintf('   Baseline: %d punti @1h (%.1f%% del totale)\n\n', ...
    nBL, 100*nBL/nH);

AH_bl  = AH(bl_mask);
X_bl   = X_1h(bl_mask, :);
t_bl   = t_h(bl_mask);
mon_bl = months(bl_mask);

%% ══════════════════════════════════════════════════════════════════════════
%% 5. FIT POWER LAW: y = A * AH^k1 + c   (per ogni sensore, su baseline)
%% ══════════════════════════════════════════════════════════════════════════
fprintf('5. Fit power law per ciascun sensore...\n');
fprintf('   Modello: y = A * AH^k1 + c\n');
fprintf('   Fitting su baseline @1h con nlinfit\n\n');

powlaw = @(p, ah) p(1) .* ah.^p(2) + p(3);

fit_params = nan(nMox, 3);   % [A, k1, c]
fit_R2     = nan(nMox, 1);
fit_RMSE   = nan(nMox, 1);
fit_pval   = nan(nMox, 1);

% Predizioni sul DATASET COMPLETO (non solo baseline) → per confronto stagionale
Y_pred_full = nan(nH, nMox);

opts_nl = statset('nlinfit');
opts_nl.MaxIter  = 2000;
opts_nl.TolFun   = 1e-8;
opts_nl.TolX     = 1e-8;
opts_nl.Robust   = 'on';   % LAR robusto agli outlier residui

for j = 1:nMox
    sname = moxCols(j);
    y_bl  = X_bl(:, j);
    y_all = X_1h(:, j);

    % Guess iniziale:
    %   c ≈ min(y) - piccola franchigia
    %   A ≈ range(y)
    %   k1 = 1 (proporzionalità lineare come punto di partenza)
    c0  = min(y_bl) * 0.9;
    A0  = (max(y_bl) - min(y_bl)) / (max(AH_bl) - min(AH_bl));
    k0  = 1;
    p0  = [A0, k0, c0];

    try
        [phat, resid, ~, covarMat] = nlinfit(AH_bl, y_bl, powlaw, p0, opts_nl);
        y_bl_pred = powlaw(phat, AH_bl);

        SS_res = sum(resid.^2);
        SS_tot = sum((y_bl - mean(y_bl)).^2);
        R2     = 1 - SS_res / SS_tot;
        RMSE   = sqrt(mean(resid.^2));

        fit_params(j,:) = phat;
        fit_R2(j)       = R2;
        fit_RMSE(j)     = RMSE;

        % Proietta il modello su tutto il dataset
        Y_pred_full(:, j) = powlaw(phat, AH);

        fprintf('   %s:  A=%+.4g  k1=%+.4f  c=%+.4g  |  R²=%.4f  RMSE=%.2f\n', ...
            sname, phat(1), phat(2), phat(3), R2, RMSE);
    catch ME
        fprintf('   %s: FIT FALLITO — %s\n', sname, ME.message);
    end
end
fprintf('\n');

%% ══════════════════════════════════════════════════════════════════════════
%% 6. SEGNALE COMPENSATO  y_comp = y - y_pred(AH) + y_pred(AH_ref)
%% ══════════════════════════════════════════════════════════════════════════
AH_ref      = median(AH_bl);          % valore di riferimento: mediana baseline
Y_comp_full = nan(nH, nMox);

for j = 1:nMox
    p = fit_params(j,:);
    if any(isnan(p)), continue; end
    Y_comp_full(:,j) = X_1h(:,j) - Y_pred_full(:,j) + powlaw(p, AH_ref);
end

%% ══════════════════════════════════════════════════════════════════════════
%% 7. ANALISI MENSILE
%% ══════════════════════════════════════════════════════════════════════════
fprintf('7. Analisi mensile...\n');
months_avail = unique(months)';
nMon         = numel(months_avail);
month_labels = {'Mar','Apr','Mag','Giu','Lug','Ago','Set','Ott','Nov','Dic'};

% Per ogni mese: media AH, media segnale, media predetto, media residuo, R² locale
AH_monthly   = nan(nMon, 1);
Y_monthly    = nan(nMon, nMox);
Yp_monthly   = nan(nMon, nMox);
Yr_monthly   = nan(nMon, nMox);   % residuo = y - y_pred
R2_monthly   = nan(nMon, nMox);

for mi = 1:nMon
    m_idx = (months == months_avail(mi));
    AH_monthly(mi) = mean(AH(m_idx), 'omitnan');

    for j = 1:nMox
        y_m  = X_1h(m_idx, j);
        yp_m = Y_pred_full(m_idx, j);
        valid = ~isnan(y_m) & ~isnan(yp_m);
        Y_monthly(mi, j)  = mean(y_m(valid));
        Yp_monthly(mi, j) = mean(yp_m(valid));
        Yr_monthly(mi, j) = mean(y_m(valid) - yp_m(valid));  % residuo medio mensile

        if sum(valid) > 5
            SS_r = sum((y_m(valid) - yp_m(valid)).^2);
            SS_t = sum((y_m(valid) - mean(y_m(valid))).^2);
            R2_monthly(mi, j) = 1 - SS_r/SS_t;
        end
    end
end

fprintf('   Mese  | AH[g/m³] | cmos1-R²  cmos2-R²  cmos3-R²  cmos4-R²\n');
fprintf('   ------+----------+------------------------------------------\n');
for mi = 1:nMon
    fprintf('   %-5s | %8.2f | ', month_labels{months_avail(mi)-2}, AH_monthly(mi));
    for j = 1:nMox
        fprintf('%6.3f    ', R2_monthly(mi,j));
    end
    fprintf('\n');
end
fprintf('\n');

%% ══════════════════════════════════════════════════════════════════════════
%% FIGURE
%% ══════════════════════════════════════════════════════════════════════════

%% ─── FIG 1: AH time series mensile ───────────────────────────────────────
fprintf('Plot Fig 1: AH mensile...\n');
fig1 = figure('Position',[50 50 1200 400]);
TT_daily = retime(TT_1h, 'daily', 'mean');
TT_daily = rmmissing(TT_daily);
t_daily  = TT_daily.Properties.RowTimes;
plot(t_daily, TT_daily.AH, '-', 'Color', [C_azzlt 0.5], 'LineWidth', 0.8);
hold on;

% Media mensile sopra
for mi = 1:nMon
    m_idx_d = month(t_daily) == months_avail(mi);
    x_m = t_daily(m_idx_d);
    y_m = TT_daily.AH(m_idx_d);
    plot(x_m, y_m, '-', 'Color', MONTH_CMAP(mi,:), 'LineWidth', 2.5);
end

xlabel('Data'); ylabel('Absolute Humidity [g/m³]');
title('Umidità Assoluta (AH) — andamento temporale', 'FontWeight','bold');
grid on; box off;
set(gca,'FontSize',12);
yline(AH_ref, '--', sprintf('Riferimento (mediana BL) = %.1f g/m³', AH_ref), ...
    'Color', C_rosso, 'LineWidth', 1.5, 'FontSize', 10);

saveas(fig1, fullfile(outDir, 'fig01_AH_timeseries.png'));

%% ─── FIG 2: Scatter y vs AH per sensore (colorato per mese) ─────────────
fprintf('Plot Fig 2: scatter y vs AH per sensore...\n');
fig2 = figure('Position',[50 50 1400 900]);
AH_fit_vec = linspace(min(AH_bl)*0.9, max(AH_bl)*1.05, 200)';

for j = 1:nMox
    ax = subplot(2,2,j);
    hold on;

    % Scatter baseline colorato per mese (subsampling visivo per densità)
    idx_bl = find(bl_mask);
    stride = max(1, floor(numel(idx_bl)/3000));   % max 3000 punti visivi
    idx_plot = idx_bl(1:stride:end);
    scatter(AH(idx_plot), X_1h(idx_plot,j), 6, ...
        MONTH_CMAP(month(t_h(idx_plot))-2, :), ...
        'filled', 'MarkerFaceAlpha', 0.5);

    % Curva fit
    if ~any(isnan(fit_params(j,:)))
        y_fit = powlaw(fit_params(j,:), AH_fit_vec);
        plot(AH_fit_vec, y_fit, '-', 'Color', C_rosso, 'LineWidth', 2.5);
    end

    xlabel('AH [g/m³]', 'FontSize', 11);
    ylabel(sprintf('%s [raw]', moxCols(j)), 'FontSize', 11);
    title(sprintf('%s   |   R²=%.4f   k₁=%.3f', ...
        moxCols(j), fit_R2(j), fit_params(j,2)), ...
        'FontWeight','bold', 'FontSize', 12);
    grid on; box off;
    set(gca, 'FontSize', 11);

    % Colorbar mese
    if j == nMox
        colormap(ax, parula(10));
        cb = colorbar(ax);
        cb.Ticks = linspace(0,1,10);
        cb.TickLabels = month_labels;
        cb.Label.String = 'Mese';
    end
end
sgtitle('Scatter: segnale sensore vs Umidità Assoluta (baseline @1h)', ...
    'FontWeight','bold', 'FontSize', 14, 'Color', C_blu);
saveas(fig2, fullfile(outDir, 'fig02_scatter_y_vs_AH.png'));

%% ─── FIG 3: R² e RMSE riepilogo ──────────────────────────────────────────
fprintf('Plot Fig 3: R² e RMSE riepilogo...\n');
fig3 = figure('Position',[50 50 900 400]);
xs = 1:nMox;

subplot(1,2,1);
bar(xs, fit_R2, 0.6, 'FaceColor', C_blu, 'EdgeColor','white', 'LineWidth',1.5);
hold on;
yline(0.5, '--', 'Color', C_arancio, 'LineWidth', 1.5, 'DisplayName','R²=0.5');
set(gca,'XTick',xs,'XTickLabel',cellstr(moxCols),'FontSize',12);
ylabel('R²'); title('R² del fit power law (baseline)', 'FontWeight','bold');
ylim([0 1]); grid on; box off;
for k=1:nMox
    text(k, fit_R2(k)+0.02, sprintf('%.3f', fit_R2(k)), ...
        'HorizontalAlignment','center','FontWeight','bold','FontSize',11,'Color',C_blu);
end

subplot(1,2,2);
RMSE_pct = 100 * fit_RMSE ./ mean(X_bl, 1)';   % RMSE relativo
bar(xs, RMSE_pct, 0.6, 'FaceColor', C_azz, 'EdgeColor','white','LineWidth',1.5);
set(gca,'XTick',xs,'XTickLabel',cellstr(moxCols),'FontSize',12);
ylabel('RMSE relativo (%)');
title('RMSE / media sensore (%)', 'FontWeight','bold');
grid on; box off;
for k=1:nMox
    text(k, RMSE_pct(k)+0.3, sprintf('%.1f%%', RMSE_pct(k)), ...
        'HorizontalAlignment','center','FontWeight','bold','FontSize',11,'Color',C_azz);
end

sgtitle('Bontà del fit power law per sensore', ...
    'FontWeight','bold','FontSize',14,'Color',C_blu);
saveas(fig3, fullfile(outDir, 'fig03_fit_quality.png'));

%% ─── FIG 4: Analisi mensile — actual vs predicted per cmos4 ─────────────
fprintf('Plot Fig 4: analisi mensile cmos4...\n');
fig4 = figure('Position',[50 50 1300 500]);
x_ticks = 1:nMon;
xl = {'Mar','Apr','Mag','Giu','Lug','Ago','Set','Ott','Nov','Dic'};
xl = xl(months_avail - 2);

subplot(1,2,1);
j = 4;  % cmos4
hold on;
b1 = bar(x_ticks - 0.2, Y_monthly(:,j)/1e3,  0.35, ...
    'FaceColor', C_rosso, 'EdgeColor','white','LineWidth',1.5);
b2 = bar(x_ticks + 0.2, Yp_monthly(:,j)/1e3, 0.35, ...
    'FaceColor', C_azzlt, 'EdgeColor','white','LineWidth',1.5);
set(gca,'XTick',x_ticks,'XTickLabel',xl,'FontSize',11);
legend([b1,b2],{'Effettivo','Predetto da AH'},'Location','northwest','FontSize',10);
ylabel('cmos4 [kΩ]'); title('cmos4: effettivo vs predetto da AH','FontWeight','bold');
grid on; box off;

subplot(1,2,2);
% Residuo mensile (kΩ) per tutti i sensori
for j=1:nMox
    plot(x_ticks, Yr_monthly(:,j)/1e3, 'o-', ...
        'Color', SENSOR_COLORS(j,:), 'LineWidth', 2.2, ...
        'MarkerSize', 7, 'DisplayName', moxCols(j));
    hold on;
end
yline(0,'--','Color',C_grig,'LineWidth',1);
set(gca,'XTick',x_ticks,'XTickLabel',xl,'FontSize',11);
legend(cellstr(moxCols),'Location','best','FontSize',10);
ylabel('Residuo [kΩ]  (effettivo − predetto)');
title('Residuo mensile: deriva NON spiegata da AH','FontWeight','bold');
grid on; box off;

sgtitle('Analisi mensile — il modello AH spiega la deriva stagionale?', ...
    'FontWeight','bold','FontSize',13,'Color',C_blu);
saveas(fig4, fullfile(outDir, 'fig04_monthly_actual_vs_predicted.png'));

%% ─── FIG 5: R² mensile per sensore (heatmap) ────────────────────────────
fprintf('Plot Fig 5: R² mensile heatmap...\n');
fig5 = figure('Position',[50 50 1000 350]);
imagesc(R2_monthly');
colormap(flipud(hot));
caxis([0 1]);
cb = colorbar; cb.Label.String = 'R² locale';
set(gca,'XTick',1:nMon,'XTickLabel',xl, ...
        'YTick',1:nMox,'YTickLabel',cellstr(moxCols),'FontSize',12);
xlabel('Mese'); title('R² del modello AH per mese e sensore','FontWeight','bold');
for mi=1:nMon
    for j=1:nMox
        text(mi, j, sprintf('%.2f', R2_monthly(mi,j)), ...
            'HorizontalAlignment','center','VerticalAlignment','middle', ...
            'FontSize', 10, 'FontWeight','bold', ...
            'Color', 'white');
    end
end
saveas(fig5, fullfile(outDir, 'fig05_R2_monthly_heatmap.png'));

%% ─── FIG 6: Segnale originale vs compensato (media mensile) ─────────────
fprintf('Plot Fig 6: segnale originale vs compensato...\n');
fig6 = figure('Position',[50 50 1400 900]);

% Media mensile del segnale compensato
Yc_monthly = nan(nMon, nMox);
for mi = 1:nMon
    m_idx = months == months_avail(mi);
    for j = 1:nMox
        Yc_monthly(mi,j) = mean(Y_comp_full(m_idx,j), 'omitnan');
    end
end

for j = 1:nMox
    subplot(2, 2, j);
    % Normalizza alla media del primo mese per mostrare la forma del drift
    y_orig = Y_monthly(:,j)  / Y_monthly(1,j);
    y_comp = Yc_monthly(:,j) / Yc_monthly(1,j);

    hold on;
    plot(x_ticks, y_orig, 'o-', 'Color', SENSOR_COLORS(j,:), ...
        'LineWidth', 2.5, 'MarkerSize', 8, 'DisplayName','Originale');
    plot(x_ticks, y_comp, 's--', 'Color', C_verde, ...
        'LineWidth', 2.2, 'MarkerSize', 8, 'DisplayName','Compensato (AH)');
    yline(1, ':', 'Color', C_grig, 'LineWidth', 1);

    set(gca,'XTick',x_ticks,'XTickLabel',xl,'FontSize',11);
    ylabel('Valore normalizzato (marzo = 1)');
    title(moxCols(j), 'FontWeight','bold');
    legend('Location','best','FontSize',10);
    grid on; box off;

    % Annotazione riduzione drift
    drift_orig = max(y_orig) - min(y_orig);
    drift_comp = max(y_comp) - min(y_comp);
    reduction  = 100 * (1 - drift_comp/drift_orig);
    text(0.98, 0.95, sprintf('Riduzione drift: %.0f%%', reduction), ...
        'Units','normalized','HorizontalAlignment','right', ...
        'VerticalAlignment','top','FontSize',10,'FontWeight','bold', ...
        'Color', C_verde, ...
        'BackgroundColor','white','EdgeColor',C_verde);
end

sgtitle('Segnale originale vs compensato per AH — deriva stagionale normalizzata', ...
    'FontWeight','bold','FontSize',14,'Color',C_blu);
saveas(fig6, fullfile(outDir, 'fig06_drift_before_after_compensation.png'));

%% ─── FIG 7: Residui nel tempo (raw - predicted) su tutto il dataset ──────
fprintf('Plot Fig 7: residui nel tempo...\n');
fig7 = figure('Position',[50 50 1400 700]);
for j = 1:nMox
    subplot(2,2,j);
    resid_full = X_1h(:,j) - Y_pred_full(:,j);

    % Media mobile 7 giorni sui residui
    resid_7d = movmean(resid_full, 7*24, 'omitnan');

    plot(t_h, resid_full/1e3, '-', 'Color', [SENSOR_COLORS(j,:) 0.15], 'LineWidth', 0.5);
    hold on;
    plot(t_h, resid_7d/1e3, '-', 'Color', SENSOR_COLORS(j,:), 'LineWidth', 2);
    yline(0,'--','Color',C_grig,'LineWidth',1);

    xlabel('Data'); ylabel('Residuo [kΩ]');
    title(sprintf('%s — residui (y − ŷ_{AH})', moxCols(j)), 'FontWeight','bold');
    grid on; box off; set(gca,'FontSize',11);

    % Annotazione varianza spiegata
    var_orig  = var(X_1h(:,j), 'omitnan');
    var_resid = var(resid_full, 'omitnan');
    var_expl  = 100*(1 - var_resid/var_orig);
    text(0.02, 0.95, sprintf('Varianza spiegata: %.1f%%', var_expl), ...
        'Units','normalized','VerticalAlignment','top', ...
        'FontSize',10,'FontWeight','bold','Color',SENSOR_COLORS(j,:), ...
        'BackgroundColor','white','EdgeColor',SENSOR_COLORS(j,:));
end
sgtitle('Residui nel tempo: componente non spiegata dall''AH', ...
    'FontWeight','bold','FontSize',14,'Color',C_blu);
saveas(fig7, fullfile(outDir, 'fig07_residuals_timeseries.png'));

%% ══════════════════════════════════════════════════════════════════════════
%% SALVATAGGIO RISULTATI
%% ══════════════════════════════════════════════════════════════════════════
fprintf('Salvataggio output...\n');

% Tabella parametri fit
T_fit = table(cellstr(moxCols)', fit_params(:,1), fit_params(:,2), fit_params(:,3), ...
    fit_R2, fit_RMSE, ...
    'VariableNames', {'Sensore','A','k1','c','R2','RMSE'});
writetable(T_fit, fullfile(outDir, 'powerlaw_fit_params.csv'));
fprintf('   ✓ powerlaw_fit_params.csv\n');

% Tabella R² mensile
mon_lab_cell = xl(:);
T_r2m = array2table([months_avail(:), AH_monthly, R2_monthly], ...
    'VariableNames', [{'Mese','AH_medio'}, cellstr(moxCols + "_R2")]);
writetable(T_r2m, fullfile(outDir, 'R2_monthly.csv'));
fprintf('   ✓ R2_monthly.csv\n');

% Salva segnali compensati nel MAT
save(fullfile(outDir, 'humidity_compensation.mat'), ...
    'fit_params', 'fit_R2', 'fit_RMSE', 'AH_ref', ...
    'Y_pred_full', 'Y_comp_full', 'AH', 't_h', ...
    'R2_monthly', 'AH_monthly', 'Y_monthly', 'Yp_monthly', 'Yr_monthly');
fprintf('   ✓ humidity_compensation.mat\n\n');

%% ══════════════════════════════════════════════════════════════════════════
%% RIEPILOGO A SCHERMO
%% ══════════════════════════════════════════════════════════════════════════
fprintf('═══════════════════════════════════════════════════\n');
fprintf('RIEPILOGO — Power law: y = A·AH^k1 + c\n');
fprintf('═══════════════════════════════════════════════════\n');
fprintf('%-8s  %+12s  %8s  %+12s  %8s  %8s\n', ...
    'Sensore','A','k1','c','R²','RMSE%');
fprintf('%-8s  %12s  %8s  %12s  %8s  %8s\n', ...
    repmat('-',1,8), repmat('-',1,12), repmat('-',1,8), ...
    repmat('-',1,12), repmat('-',1,8), repmat('-',1,8));
for j = 1:nMox
    RMSE_pct_j = 100 * fit_RMSE(j) / mean(X_bl(:,j));
    fprintf('%-8s  %+12.4g  %8.4f  %+12.4g  %8.4f  %7.1f%%\n', ...
        moxCols(j), fit_params(j,1), fit_params(j,2), fit_params(j,3), ...
        fit_R2(j), RMSE_pct_j);
end
fprintf('\n');

% Verifica settembre di cmos4
set_idx = months_avail == 9;
if any(set_idx)
    fprintf('--- Settembre (cmos4) ---\n');
    fprintf('   AH media settembre:      %.2f g/m³\n', AH_monthly(set_idx));
    fprintf('   cmos4 effettivo:         %.0f Ω\n', Y_monthly(set_idx, 4));
    fprintf('   cmos4 predetto da AH:    %.0f Ω\n', Yp_monthly(set_idx, 4));
    fprintf('   Residuo (non spiegato):  %.0f Ω  (%.1f%% del valore effettivo)\n', ...
        Yr_monthly(set_idx, 4), ...
        100*abs(Yr_monthly(set_idx, 4))/Y_monthly(set_idx, 4));
    fprintf('   R² locale settembre:     %.4f\n\n', R2_monthly(set_idx, 4));
end

fprintf('Output salvati in: %s\n', outDir);
fprintf('\n=== DONE ===\n');
