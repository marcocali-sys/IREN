%% ELLONA_14_sensor_env_correlation.m
%
% Analisi della correlazione sensori MOX con variabili ambientali separate.
% Estende ELLONA_13: AH non spiega la deriva → testiamo T e RH separati
% e modelli combinati.
%
% Modelli testati per ciascun sensore:
%   M1: y = A * T^k1 + c                        (temperatura)
%   M2: y = A * RH^k1 + c                       (umidità relativa)
%   M3: y = A * AH^k1 + c                       (umidità assoluta, riferimento)
%   M4: y = A * T^k1 * RH^k2 + c               (moltiplicativo T×RH)
%   M5: y = A * exp(k1*T) * RH^k2 + c          (esponenziale T, power RH — tipico MOX)
%
% Focus: quale variabile ambientale spiega la deriva stagionale di cmos4?
%        Il timing di settembre è catturato da T, RH, o nessuno dei due?
%
% Output → IREN/output/env_correlation/
%
% Marco Calì — PoliMi, Aprile 2026

clear; clc; close all;

%% ══════════════════════════════════════════════════════════════════════════
%% CONFIG
%% ══════════════════════════════════════════════════════════════════════════
scriptDir = fileparts(mfilename('fullpath'));
baseDir   = fullfile(scriptDir, '..', '..');

dataFile  = fullfile(baseDir, 'data', 'processed', 'monitoring_all.mat');
outDir    = fullfile(baseDir, 'output', 'env_correlation');
if ~isfolder(outDir), mkdir(outDir); end

moxCols   = ["cmos1","cmos2","cmos3","cmos4"];
nMox      = numel(moxCols);
modelNames = {'T','RH','AH','T×RH','exp(T)×RH'};
nModels    = numel(modelNames);

% PoliMi palette
C_blu    = [0   56  102]/255;
C_azz    = [20  100 160]/255;
C_azzlt  = [107 163 214]/255;
C_grig   = [88  89  91 ]/255;
C_rosso  = [181 57  78 ]/255;
C_arancio= [232 163 61 ]/255;
C_verde  = [74  155 110]/255;

SENSOR_COLORS = [C_blu; C_azz; C_azzlt; C_rosso];
MODEL_COLORS  = [C_blu; C_azz; C_azzlt; C_arancio; C_verde];
MONTH_CMAP    = parula(10);

fprintf('=== ELLONA_14 — Sensor × Environment Correlation ===\n\n');

%% ══════════════════════════════════════════════════════════════════════════
%% 1. LOAD + PREPROCESSING (identico a ELLONA_13)
%% ══════════════════════════════════════════════════════════════════════════
fprintf('1. Caricamento dati...\n');
load(dataFile, 'DATA');
nRows = height(DATA);
fprintf('   Righe: %d  |  %s → %s\n\n', nRows, ...
    datestr(DATA.datetime(1),'dd-mmm-yyyy'), ...
    datestr(DATA.datetime(end),'dd-mmm-yyyy'));

T_C_raw = DATA.temperature;
RH_raw  = DATA.humidity;
X_raw   = DATA{:, cellstr(moxCols)};

% AH [g/m³] — formula corretta (e_s in hPa → ×100 per Pa, poi M_w/R = 2.1674)
e_s_raw = 6.112 .* exp(17.67 .* T_C_raw ./ (T_C_raw + 243.5));
AH_raw  = (RH_raw./100) .* e_s_raw .* 216.74 ./ (T_C_raw + 273.15);

% Timetable + resample @1h
TT_raw = timetable(DATA.datetime, T_C_raw, RH_raw, AH_raw, ...
    X_raw(:,1), X_raw(:,2), X_raw(:,3), X_raw(:,4), ...
    'VariableNames', {'T_C','RH','AH','cmos1','cmos2','cmos3','cmos4'});
TT_1h  = retime(TT_raw, 'hourly', 'mean');
TT_1h  = rmmissing(TT_1h);

t_h    = TT_1h.Properties.RowTimes;
T_C    = TT_1h.T_C;
RH_h   = TT_1h.RH;
AH_h   = TT_1h.AH;
X_1h   = TT_1h{:, cellstr(moxCols)};
months = month(t_h);
nH     = height(TT_1h);
fprintf('   Punti @1h: %d\n\n', nH);

% Baseline IQR weekly
week_id  = floor(datenum(t_h) / 7);
wks_uniq = unique(week_id);
bl_mask  = true(nH, 1);
for wk = wks_uniq'
    idx = week_id == wk;
    for j = 1:nMox
        y_wk = X_1h(idx,j);
        p25 = prctile(y_wk, 25);
        p75 = prctile(y_wk, 75);
        bl_mask(idx) = bl_mask(idx) & (y_wk >= p25) & (y_wk <= p75);
    end
end
nBL = sum(bl_mask);
fprintf('2. Baseline: %d punti @1h (%.1f%%)\n\n', nBL, 100*nBL/nH);

T_bl  = T_C(bl_mask);
RH_bl = RH_h(bl_mask);
AH_bl = AH_h(bl_mask);
X_bl  = X_1h(bl_mask, :);
t_bl  = t_h(bl_mask);
mon_bl = months(bl_mask);

%% ══════════════════════════════════════════════════════════════════════════
%% 2. CORRELAZIONE DI PEARSON (su baseline, scala mensile e oraria)
%% ══════════════════════════════════════════════════════════════════════════
fprintf('3. Correlazione di Pearson (baseline @1h)...\n');
vars_corr  = [T_bl, RH_bl, AH_bl];
var_labels = {'T [°C]','RH [%]','AH [g/m³]'};
nVars      = numel(var_labels);

r_bl   = nan(nMox, nVars);
p_bl   = nan(nMox, nVars);

for j = 1:nMox
    for v = 1:nVars
        [r_bl(j,v), p_bl(j,v)] = corr(X_bl(:,j), vars_corr(:,v), 'type','Pearson');
    end
end

fprintf('   Correlazione Pearson (baseline @1h):\n');
fprintf('   %-8s  %10s  %10s  %10s\n','Sensore','r(T)','r(RH)','r(AH)');
for j = 1:nMox
    fprintf('   %-8s  %+10.4f  %+10.4f  %+10.4f\n', ...
        moxCols(j), r_bl(j,1), r_bl(j,2), r_bl(j,3));
end
fprintf('\n');

% Correlazione su aggregazione mensile (cattura scala lenta)
months_avail = unique(months)';
nMon         = numel(months_avail);
month_labels = {'Mar','Apr','Mag','Giu','Lug','Ago','Set','Ott','Nov','Dic'};

T_mon  = nan(nMon,1); RH_mon = nan(nMon,1); AH_mon = nan(nMon,1);
X_mon  = nan(nMon, nMox);
for mi = 1:nMon
    idx_m = months == months_avail(mi);
    T_mon(mi)    = mean(T_C(idx_m), 'omitnan');
    RH_mon(mi)   = mean(RH_h(idx_m), 'omitnan');
    AH_mon(mi)   = mean(AH_h(idx_m), 'omitnan');
    X_mon(mi,:)  = mean(X_1h(idx_m,:), 'omitnan');
end

r_mon = nan(nMox, nVars);
fprintf('   Correlazione Pearson (medie MENSILI, n=%d mesi):\n', nMon);
fprintf('   %-8s  %10s  %10s  %10s\n','Sensore','r(T)','r(RH)','r(AH)');
vars_mon = [T_mon, RH_mon, AH_mon];
for j = 1:nMox
    for v = 1:nVars
        r_mon(j,v) = corr(X_mon(:,j), vars_mon(:,v), 'type','Pearson');
    end
    fprintf('   %-8s  %+10.4f  %+10.4f  %+10.4f\n', ...
        moxCols(j), r_mon(j,1), r_mon(j,2), r_mon(j,3));
end
fprintf('\n');

%% ══════════════════════════════════════════════════════════════════════════
%% 3. FIT POWER LAW / MODELLI per ciascun sensore
%% ══════════════════════════════════════════════════════════════════════════
fprintf('4. Fit modelli ambientali su baseline @1h...\n\n');

% Modelli (handle functions)
%   p(1)=A, p(2)=k1, p(3)=c  per M1/M2/M3
%   p(1)=A, p(2)=k1, p(3)=k2, p(4)=c  per M4/M5
M1 = @(p,x) p(1) .* x(:,1).^p(2) + p(3);            % T
M2 = @(p,x) p(1) .* x(:,2).^p(2) + p(3);            % RH
M3 = @(p,x) p(1) .* x(:,3).^p(2) + p(3);            % AH
M4 = @(p,x) p(1) .* x(:,1).^p(2) .* x(:,2).^p(3) + p(4);       % T×RH
M5 = @(p,x) p(1) .* exp(p(2).*x(:,1)) .* x(:,2).^p(3) + p(4);  % exp(T)×RH

models_fn = {M1, M2, M3, M4, M5};
X_pred_bl = [T_bl, RH_bl, AH_bl];   % matrice predittori su baseline

R2_all    = nan(nMox, nModels);
RMSE_all  = nan(nMox, nModels);
params_all= cell(nMox, nModels);

opts_nl = statset('nlinfit');
opts_nl.MaxIter = 3000;
opts_nl.TolFun  = 1e-10;
opts_nl.TolX    = 1e-10;
opts_nl.Robust  = 'on';

for j = 1:nMox
    y_bl  = X_bl(:, j);
    y_mu  = mean(y_bl);
    y_rng = max(y_bl) - min(y_bl);
    fprintf('  %s (media=%.0f, range=%.0f):\n', moxCols(j), y_mu, y_rng);

    for m = 1:nModels
        fn = models_fn{m};
        % Guess iniziale adattivo per dimensione del segnale
        if m <= 3
            % 3 parametri: [A, k1, c]
            p0 = [y_rng / 10, 1.0, y_mu * 0.5];
        else
            % 4 parametri: [A, k1, k2, c]
            p0 = [y_rng / 100, 0.5, 0.5, y_mu * 0.5];
        end

        try
            [phat, resid] = nlinfit(X_pred_bl, y_bl, fn, p0, opts_nl);
            SS_res = sum(resid.^2);
            SS_tot = sum((y_bl - mean(y_bl)).^2);
            R2  = 1 - SS_res / SS_tot;
            RMSE = sqrt(mean(resid.^2));
            R2_all(j,m)    = R2;
            RMSE_all(j,m)  = RMSE;
            params_all{j,m} = phat;
            fprintf('    M%-2d %-12s R²=%+7.4f  RMSE=%.2f\n', ...
                m, ['(' modelNames{m} ')'], R2, RMSE);
        catch ME
            fprintf('    M%-2d %-12s FALLITO: %s\n', m, ['(' modelNames{m} ')'], ME.message);
        end
    end
    fprintf('\n');
end

%% ══════════════════════════════════════════════════════════════════════════
%% 4. CORRELAZIONE MENSILE per variabile (cattura timing stagionale)
%% ══════════════════════════════════════════════════════════════════════════
fprintf('5. Correlazione mensile (r tra media mensile sensore e variabile)...\n');

% Per cmos4: quale mese diverge di più da ciascun predittore?
j4 = 4;
fprintf('\n   cmos4 — medie mensili:\n');
fprintf('   %-5s  %8s  %8s  %8s  %12s\n','Mese','T[°C]','RH[%%]','AH[g/m³]','cmos4[kΩ]');
for mi = 1:nMon
    fprintf('   %-5s  %8.2f  %8.2f  %8.2f  %12.1f\n', ...
        month_labels{months_avail(mi)-2}, ...
        T_mon(mi), RH_mon(mi), AH_mon(mi), X_mon(mi,j4)/1e3);
end
fprintf('\n');

% r mensile per tutti i sensori
fprintf('   r(mensile) per tutti i sensori:\n');
fprintf('   %-8s  %8s  %8s  %8s\n','Sensore','r(T)','r(RH)','r(AH)');
for j=1:nMox
    fprintf('   %-8s  %+8.4f  %+8.4f  %+8.4f\n', moxCols(j), r_mon(j,1), r_mon(j,2), r_mon(j,3));
end
fprintf('\n');

%% ══════════════════════════════════════════════════════════════════════════
%% FIGURE
%% ══════════════════════════════════════════════════════════════════════════

xl_mon = month_labels(months_avail - 2);

%% ─── FIG 1: Correlazione Pearson (1h baseline + mensile) ────────────────
fprintf('Plot Fig 1: correlazione Pearson...\n');
fig1 = figure('Position',[50 50 1200 500]);
xs = 1:nMox;
w  = 0.25;
var_colors = [C_rosso; C_azz; C_azzlt];

for panel = 1:2
    subplot(1,2,panel);
    hold on;
    if panel == 1
        r_data = r_bl;
        ttl    = 'Pearson r  —  baseline @1h';
    else
        r_data = r_mon;
        ttl    = 'Pearson r  —  medie mensili (n=10)';
    end
    for v = 1:3
        bar(xs + (v-2)*w, r_data(:,v), w*0.9, ...
            'FaceColor', var_colors(v,:), 'EdgeColor','white','LineWidth',1.2);
    end
    yline(0, '-', 'Color', C_grig, 'LineWidth', 0.8);
    yline( 0.5, ':', 'Color', C_grig, 'LineWidth', 1);
    yline(-0.5, ':', 'Color', C_grig, 'LineWidth', 1);
    set(gca,'XTick',xs,'XTickLabel',cellstr(moxCols),'FontSize',12);
    ylabel('Pearson r'); title(ttl,'FontWeight','bold');
    legend(var_labels,'Location','best','FontSize',10);
    ylim([-1 1]); grid on; box off;
end
sgtitle('Correlazione sensori × variabili ambientali', ...
    'FontWeight','bold','FontSize',14,'Color',C_blu);
saveas(fig1, fullfile(outDir,'fig01_pearson_correlation.png'));

%% ─── FIG 2: R² dei modelli per ciascun sensore ──────────────────────────
fprintf('Plot Fig 2: R² modelli...\n');
fig2 = figure('Position',[50 50 1200 500]);
w = 0.15;
for j = 1:nMox
    subplot(1,4,j);
    hold on;
    for m = 1:nModels
        bar(m, max(R2_all(j,m), -0.5), 0.7, ...
            'FaceColor', MODEL_COLORS(m,:), 'EdgeColor','white','LineWidth',1.2);
    end
    yline(0, '-', 'Color', C_grig, 'LineWidth', 1);
    yline(0.5, ':', 'Color', C_arancio, 'LineWidth', 1.2);
    set(gca,'XTick',1:nModels,'XTickLabel',modelNames,'FontSize',10, ...
        'XTickLabelRotation',30);
    ylabel('R²'); title(moxCols(j),'FontWeight','bold');
    ylim([-0.5 1]); grid on; box off;
    for m=1:nModels
        if ~isnan(R2_all(j,m))
            yp = max(R2_all(j,m),0) + 0.03;
            text(m, yp, sprintf('%.2f', R2_all(j,m)), ...
                'HorizontalAlignment','center','FontSize',9,'FontWeight','bold', ...
                'Color', MODEL_COLORS(m,:));
        end
    end
end
sgtitle('R² dei modelli ambientali per sensore (baseline @1h)', ...
    'FontWeight','bold','FontSize',14,'Color',C_blu);
saveas(fig2, fullfile(outDir,'fig02_R2_per_model.png'));

%% ─── FIG 3: Profilo mensile — T, RH, cmos1-4 normalizzati ───────────────
fprintf('Plot Fig 3: profili mensili normalizzati...\n');
fig3 = figure('Position',[50 50 1300 600]);

subplot(1,2,1);
hold on;
% Normalizza ogni serie alla propria media per confronto forma
T_n  = T_mon  / mean(T_mon);
RH_n = RH_mon / mean(RH_mon);
AH_n = AH_mon / mean(AH_mon);
plot(1:nMon, T_n,  'o-', 'Color', C_rosso,  'LineWidth',2.5,'MarkerSize',8,'DisplayName','T (norm.)');
plot(1:nMon, RH_n, 's-', 'Color', C_azz,    'LineWidth',2.5,'MarkerSize',8,'DisplayName','RH (norm.)');
plot(1:nMon, AH_n, '^-', 'Color', C_azzlt,  'LineWidth',2.5,'MarkerSize',8,'DisplayName','AH (norm.)');
set(gca,'XTick',1:nMon,'XTickLabel',xl_mon,'FontSize',11);
ylabel('Valore normalizzato (media=1)');
title('Variabili ambientali — profilo stagionale','FontWeight','bold');
legend('Location','best','FontSize',10); grid on; box off;
yline(1,'--','Color',C_grig,'LineWidth',0.8);

subplot(1,2,2);
hold on;
for j = 1:nMox
    x_n = X_mon(:,j) / mean(X_mon(:,j));
    plot(1:nMon, x_n, 'o-', 'Color', SENSOR_COLORS(j,:), ...
        'LineWidth', 2.5, 'MarkerSize', 8, 'DisplayName', moxCols(j));
end
set(gca,'XTick',1:nMon,'XTickLabel',xl_mon,'FontSize',11);
ylabel('Valore normalizzato (media=1)');
title('Sensori MOX — profilo stagionale','FontWeight','bold');
legend('Location','best','FontSize',10); grid on; box off;
yline(1,'--','Color',C_grig,'LineWidth',0.8);

sgtitle('Confronto forma del profilo stagionale — variabili vs sensori', ...
    'FontWeight','bold','FontSize',14,'Color',C_blu);
saveas(fig3, fullfile(outDir,'fig03_seasonal_profiles.png'));

%% ─── FIG 4: cmos4 — scatter vs T e vs RH (colorato per mese) ────────────
fprintf('Plot Fig 4: scatter cmos4 vs T e RH...\n');
fig4 = figure('Position',[50 50 1300 550]);

% Subsampling visivo baseline
idx_bl  = find(bl_mask);
stride  = max(1, floor(numel(idx_bl)/3000));
idx_vis = idx_bl(1:stride:end);
c_vis   = MONTH_CMAP(months(idx_vis)-2, :);

vars_x  = {T_C(idx_vis), RH_h(idx_vis), AH_h(idx_vis)};
xlabels = {'Temperatura [°C]','Umidità Relativa [%]','Absolute Humidity [g/m³]'};
j4 = 4;

for v = 1:3
    subplot(1,3,v);
    scatter(vars_x{v}, X_1h(idx_vis, j4)/1e3, 8, c_vis, ...
        'filled', 'MarkerFaceAlpha', 0.5);
    hold on;

    % Sovrapponi media mensile
    vars_mon_v = vars_mon(:,v);
    for mi = 1:nMon
        scatter(vars_mon_v(mi), X_mon(mi,j4)/1e3, 120, ...
            MONTH_CMAP(mi,:), 's', 'filled', 'MarkerEdgeColor','k','LineWidth',1.2);
        text(vars_mon_v(mi), X_mon(mi,j4)/1e3 + 20, xl_mon{mi}, ...
            'FontSize', 9, 'HorizontalAlignment','center','Color',C_grig);
    end

    xlabel(xlabels{v},'FontSize',11);
    ylabel('cmos4 [kΩ]','FontSize',11);
    r_v = corr(vars_mon(:,v), X_mon(:,j4));
    title(sprintf('cmos4 vs %s\nr_{mensile} = %+.3f', var_labels{v}, r_v), ...
        'FontWeight','bold','FontSize',12);
    grid on; box off; set(gca,'FontSize',11);
end

sgtitle('cmos4 — scatter vs variabili ambientali (baseline @1h, medie mensili evidenziate)', ...
    'FontWeight','bold','FontSize',13,'Color',C_blu);
colormap(parula); cb = colorbar('Location','eastoutside');
cb.Ticks = linspace(0,1,10); cb.TickLabels = xl_mon;
cb.Label.String = 'Mese';
saveas(fig4, fullfile(outDir,'fig04_cmos4_scatter_T_RH.png'));

%% ─── FIG 5: Heatmap r mensile per sensore × variabile ───────────────────
fprintf('Plot Fig 5: heatmap correlazione mensile per mese...\n');

% r(sensore, variabile) per singolo mese — identifica in quale mese la
% correlazione è più forte/debole
r_by_month = nan(nMon, nMox, nVars);
for mi = 1:nMon
    idx_m = months == months_avail(mi);
    for j = 1:nMox
        for v = 1:nVars
            xv = [T_C(idx_m), RH_h(idx_m), AH_h(idx_m)];
            ys = X_1h(idx_m, j);
            valid = ~isnan(ys) & ~isnan(xv(:,v));
            if sum(valid) > 10
                r_by_month(mi,j,v) = corr(xv(valid,v), ys(valid));
            end
        end
    end
end

fig5 = figure('Position',[50 50 1400 500]);
for v = 1:nVars
    subplot(1,nVars,v);
    imagesc(r_by_month(:,:,v)');
    colormap(gca, redblue_cmap());
    caxis([-1 1]);
    set(gca,'XTick',1:nMon,'XTickLabel',xl_mon,'XTickLabelRotation',45, ...
            'YTick',1:nMox,'YTickLabel',cellstr(moxCols),'FontSize',11);
    title(sprintf('r(sensore, %s)', var_labels{v}),'FontWeight','bold');
    colorbar;
    for mi=1:nMon
        for j=1:nMox
            if ~isnan(r_by_month(mi,j,v))
                text(mi, j, sprintf('%.2f', r_by_month(mi,j,v)), ...
                    'HorizontalAlignment','center','VerticalAlignment','middle', ...
                    'FontSize',9,'FontWeight','bold', ...
                    'Color', C_grig);
            end
        end
    end
end
sgtitle('r(sensore × variabile) per mese @1h — dove la correlazione è strutturale?', ...
    'FontWeight','bold','FontSize',13,'Color',C_blu);
saveas(fig5, fullfile(outDir,'fig05_correlation_heatmap_monthly.png'));

%% ─── FIG 6: Timeline cmos4 vs T, RH normalizzati ────────────────────────
fprintf('Plot Fig 6: timeline cmos4 vs T e RH...\n');
fig6 = figure('Position',[50 50 1400 450]);

TT_daily = retime(TT_1h, 'daily', 'mean');
TT_daily = rmmissing(TT_daily);
t_daily  = TT_daily.Properties.RowTimes;

% Normalizza per confronto su stesso grafico
c4_n  = TT_daily.cmos4  / mean(TT_daily.cmos4,  'omitnan');
T_n_d = TT_daily.T_C    / mean(TT_daily.T_C,     'omitnan');
RH_n_d= TT_daily.RH     / mean(TT_daily.RH,      'omitnan');

hold on;
plot(t_daily, c4_n,   '-', 'Color', C_rosso,  'LineWidth', 2.0, 'DisplayName', 'cmos4 (norm.)');
plot(t_daily, T_n_d,  '-', 'Color', C_arancio, 'LineWidth', 1.5, 'DisplayName', 'T (norm.)');
plot(t_daily, RH_n_d, '-', 'Color', C_azz,     'LineWidth', 1.5, 'DisplayName', 'RH (norm.)');
yline(1,'--','Color',C_grig,'LineWidth',0.8);

% Evidenzia settembre
set_start = datetime(2025,9,1);
set_end   = datetime(2025,9,30);
patch([set_start set_end set_end set_start], ...
    [0 0 max(c4_n)*1.1 max(c4_n)*1.1]*1.5, C_rosso, ...
    'FaceAlpha',0.08,'EdgeColor','none','HandleVisibility','off');
text(set_start + days(15), max(c4_n)*0.95, 'Settembre', ...
    'HorizontalAlignment','center','FontSize',11,'Color',C_rosso,'FontWeight','bold');

xlabel('Data'); ylabel('Valore normalizzato (media = 1)');
title('cmos4, T e RH — andamento giornaliero normalizzato', 'FontWeight','bold');
legend('Location','northwest','FontSize',11);
grid on; box off; set(gca,'FontSize',12);

saveas(fig6, fullfile(outDir,'fig06_cmos4_T_RH_timeline.png'));

%% ══════════════════════════════════════════════════════════════════════════
%% SALVATAGGIO
%% ══════════════════════════════════════════════════════════════════════════
fprintf('\nSalvataggio output...\n');

% Tabella R² modelli
T_r2 = array2table(R2_all, 'RowNames', cellstr(moxCols)', ...
    'VariableNames', strrep(modelNames, '×','x'));
writetable(T_r2, fullfile(outDir,'model_R2_summary.csv'), 'WriteRowNames',true);
fprintf('   ✓ model_R2_summary.csv\n');

% Tabella correlazioni mensili
T_rmon = array2table([months_avail(:), T_mon, RH_mon, AH_mon, X_mon], ...
    'VariableNames', [{'Mese','T_C','RH','AH'}, cellstr(moxCols)]);
writetable(T_rmon, fullfile(outDir,'monthly_means.csv'));
fprintf('   ✓ monthly_means.csv\n');

save(fullfile(outDir,'env_correlation.mat'), ...
    'R2_all','r_bl','r_mon','r_by_month','params_all', ...
    'T_mon','RH_mon','AH_mon','X_mon','months_avail');
fprintf('   ✓ env_correlation.mat\n\n');

%% ══════════════════════════════════════════════════════════════════════════
%% RIEPILOGO FINALE
%% ══════════════════════════════════════════════════════════════════════════
fprintf('══════════════════════════════════════════════════════════\n');
fprintf('RIEPILOGO — R² modelli ambientali (baseline @1h)\n');
fprintf('══════════════════════════════════════════════════════════\n');
fprintf('%-8s', 'Sensore');
for m = 1:nModels, fprintf('  %-12s', modelNames{m}); end
fprintf('\n%-8s', '--------');
for m = 1:nModels, fprintf('  %-12s', '------------'); end
fprintf('\n');
for j = 1:nMox
    fprintf('%-8s', moxCols(j));
    for m = 1:nModels
        if isnan(R2_all(j,m))
            fprintf('  %-12s', 'FALLITO');
        else
            fprintf('  %-12.4f', R2_all(j,m));
        end
    end
    fprintf('\n');
end
fprintf('\n');

fprintf('Correlazione Pearson mensile (n=%d mesi):\n', nMon);
fprintf('%-8s  %+8s  %+8s  %+8s\n','Sensore','r(T)','r(RH)','r(AH)');
for j=1:nMox
    fprintf('%-8s  %+8.4f  %+8.4f  %+8.4f\n', ...
        moxCols(j), r_mon(j,1), r_mon(j,2), r_mon(j,3));
end

fprintf('\nOutput: %s\n=== DONE ===\n', outDir);

%% ══════════════════════════════════════════════════════════════════════════
%% HELPER: colormap divergente rosso-bianco-blu
%% ══════════════════════════════════════════════════════════════════════════
function cmap = redblue_cmap(n)
    if nargin < 1, n = 256; end
    r = [linspace(0.7,1,n/2), ones(1,n/2)];
    g = [linspace(0.1,1,n/2), linspace(1,0.1,n/2)];
    b = [ones(1,n/2), linspace(1,0.1,n/2)];
    cmap = [r(:), g(:), b(:)];
end
