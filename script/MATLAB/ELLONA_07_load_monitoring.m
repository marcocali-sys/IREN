%% ELLONA_07_load_monitoring.m
% Carica e preprocessa tutti i CSV mensili di monitoraggio ELLONA.
%
% Input : IREN/data/raw/monitoraggio2025/*.csv
%   Formato colonne: date;time;cmos1;cmos2;cmos3;cmos4;temperature;humidity;nh3;h2s;pid
%   Delimitatore   : ;
%   Frequenza      : 10s
%   Periodo        : marzo–dicembre 2025
%
% Output: IREN/data/processed/monitoring_all.mat  (variabile: DATA, table)
%
% Marco Calì — PoliMi, Aprile 2026

clear; clc;

%% ===== CONFIG =====
scriptDir = fileparts(mfilename('fullpath'));
baseDir   = fullfile(scriptDir, '..', '..');        % IREN/

dataDir = fullfile(baseDir, 'data', 'raw', 'monitoraggio2025');
outDir  = fullfile(baseDir, 'data', 'processed');

% Colonne numeriche da conservare (PID escluso: tutti zero nel dataset)
keepCols = {'cmos1','cmos2','cmos3','cmos4','temperature','humidity','nh3','h2s'};

%% ===== LOAD FILES =====
files = dir(fullfile(dataDir, '*.csv'));
if isempty(files)
    error('Nessun file CSV trovato in: %s', dataDir);
end
fprintf('Trovati %d file CSV mensili\n\n', numel(files));

allT = cell(numel(files), 1);

for i = 1:numel(files)
    fpath = fullfile(files(i).folder, files(i).name);
    [~, fname] = fileparts(files(i).name);
    fprintf('  Caricamento: %-22s', files(i).name);
    tic;

    % Forza 'date' e 'time' come stringhe prima di leggere:
    % readtable altrimenti auto-detecta 'time' come duration e 'date'
    % come datetime con formato sbagliato → range temporale errato.
    opts = detectImportOptions(fpath, 'Delimiter', ';');
    opts.VariableNamingRule = 'preserve';   % va su opts, non su readtable
    for cname = {'date','time'}
        idx = find(strcmpi(opts.VariableNames, cname{1}), 1);
        if ~isempty(idx), opts.VariableTypes{idx} = 'char'; end
    end
    T = readtable(fpath, opts);

    % Costruisci datetime da colonne separate "date" e "time"
    % Formato atteso: "14/03/2025" e "00:00:00"
    dateStr = strtrim(string(T.('date')));
    timeStr = strtrim(string(T.('time')));
    T.datetime = datetime(dateStr + " " + timeStr, ...
        'InputFormat', 'dd/MM/yyyy HH:mm:ss');

    % Rimuovi pid (tutti zero) e colonne temporali originali
    dropCols = intersect({'date','time','pid'}, T.Properties.VariableNames);
    T = removevars(T, dropCols);

    % Tag mese
    T.month_tag = repmat(string(fname), height(T), 1);

    fprintf('  %7d righe   (%.1f s)\n', height(T), toc);
    allT{i} = T;
end

%% ===== CONCATENAZIONE =====
fprintf('\nConcatenazione...\n');
DATA = vertcat(allT{:});

% Sort per tempo
% ATTENZIONE: usare ~ per scartare i valori ordinati; assegnare
% DATA.datetime direttamente altera la colonna PRIMA di riordinare
% la tabella → doppio sort → ordine errato.
[~, ord] = sort(DATA.datetime, 'ascend');
DATA = DATA(ord, :);

% Rimuovi timestamp duplicati (es. sovrapposizioni tra file mensili)
[~, ia] = unique(DATA.datetime, 'stable');
nDup = height(DATA) - numel(ia);
DATA = DATA(ia, :);
if nDup > 0
    fprintf('  Rimossi %d timestamp duplicati\n', nDup);
end

% Rimuovi righe con NaN nei canali principali
checkCols = {'cmos1','cmos2','cmos3','cmos4','temperature','humidity'};
validRows = all(isfinite(DATA{:, checkCols}), 2);
nNaN = sum(~validRows);
DATA = DATA(validRows, :);
if nNaN > 0
    fprintf('  Rimosse %d righe con NaN/Inf nei sensori principali\n', nNaN);
end

%% ===== REPORT =====
fprintf('\n======== RIEPILOGO DATASET ========\n');
fprintf('Righe totali       : %d\n', height(DATA));

% Usa string() di datetime invece di datestr() per evitare ambiguità
% nel formato (in datestr 'MM'=mese, 'mm'=minuti — confuso)
t_ini = DATA.datetime(1);
t_fin = DATA.datetime(end);
fprintf('Range temporale    : %s  -->  %s\n', ...
    char(t_ini, 'dd-MMM-yyyy HH:mm'), ...
    char(t_fin, 'dd-MMM-yyyy HH:mm'));

% Conta NaT nel datetime (parsing fallito)
nNaT = sum(isnat(DATA.datetime));
if nNaT > 0
    fprintf('  ATTENZIONE: %d righe con datetime NaT (parsing fallito)\n', nNaT);
end

% Stima frequenza reale
dt_sec = seconds(median(diff(DATA.datetime(1:min(10000,height(DATA))))));
fprintf('Frequenza campion. : %.1f s (nominale: 10 s)\n\n', dt_sec);

fprintf('%-14s  %10s  %10s  %10s  %10s\n', 'Sensore', 'Min', 'Max', 'Media', 'NaN');
fprintf('%s\n', repmat('-', 58, 1));
for c = checkCols
    v = DATA.(c{1});
    vf = v(isfinite(v));   % omitnan-safe per min/max
    fprintf('%-14s  %10.2f  %10.2f  %10.2f  %10d\n', ...
        c{1}, min(vf), max(vf), mean(v,'omitnan'), sum(isnan(v)));
end

% NH3 e H2S separati (sensori specifici, non usati per baseline PCA)
for c = {'nh3','h2s'}
    v = DATA.(c{1});
    vf = v(isfinite(v));
    fprintf('%-14s  %10.4f  %10.4f  %10.4f  %10d  [non usato per baseline]\n', ...
        c{1}, min(vf), max(vf), mean(v,'omitnan'), sum(isnan(v)));
end

% Segnala outlier estremi nei MOX (valore > 10x mediana → probabile saturazione/guasto)
moxCols = {'cmos1','cmos2','cmos3','cmos4'};
fprintf('\nCheck outlier MOX (valori > 10 × mediana):\n');
for c = moxCols
    v   = DATA.(c{1});
    med = median(v, 'omitnan');
    n99 = sum(v > 10*med);
    if n99 > 0
        fprintf('  %-6s: %d punti > 10×mediana (mediana=%.0f, max=%.0f)  ← VERIFICA\n', ...
            c{1}, n99, med, max(v));
    end
end

%% ===== SALVATAGGIO =====
if ~isfolder(outDir), mkdir(outDir); end
outFile = fullfile(outDir, 'monitoring_all.mat');
fprintf('\nSalvataggio: %s\n', outFile);
save(outFile, 'DATA', '-v7.3');
fprintf('Fatto.\n');
