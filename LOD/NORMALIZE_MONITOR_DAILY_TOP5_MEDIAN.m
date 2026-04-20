function NORMALIZE_MONITOR_DAILY_TOP5_MEDIAN()
% NORMALIZE_MONITOR_DAILY_TOP5_MEDIAN
% Normalizzazione per file di monitoraggio con baseline giornaliera R0.
%
% Per ogni GIORNO e per ogni sensore R (es. MAG2..MAG7):
%   1) prendi tutti i valori del giorno
%   2) calcola P95 e P99
%   3) prendi la banda alta: [P95, P99)  (top 5% meno top 1%)
%   4) R0(giorno) = mediana della banda
%   5) normalizza:
%       - "RR0"    : Rnorm = R / R0(giorno)
%       - "Rminus" : Rnorm = R - R0(giorno)
%
% Input : CSV con colonna timestamp e colonne MAG*
% Output:
%   - CSV normalizzato
%   - CSV con R0 giornalieri per sensore
%
% Script scritto in modo "legacy-safe":
% - usa char ('...') e non string ("...")
% - evita nomi variabili con __
% - evita dateshift (usa datetime(year,month,day))

clc; close all;

%% ===================== CONFIG =====================
cfg = struct();

% Colonna tempo nel CSV
cfg.timeCol = 'timestamp';

% Colonne da normalizzare:
% - se vuoto: autodetect prefix 'MAG'
cfg.autoDetectPrefix = 'MAG';
cfg.explicitCols = {};   % es: {'MAG2','MAG3','MAG4','MAG5','MAG6','MAG7'}

% Normalizzazione: 'RR0' oppure 'Rminus'
cfg.normType = 'RR0';

% Output:
%  - 'replace' sovrascrive MAG*
%  - 'add' crea MAG*_NORM
cfg.outputMode = 'replace';

% Percentili (top 5% e togli top 1%)
cfg.pLow  = 95;
cfg.pHigh = 99;

% Soglie di robustezza
cfg.minPointsDay  = 200;  % se un giorno ha pochi punti, il R0 puo' essere instabile
cfg.minPointsBand = 30;   % min punti richiesti nella banda [P95,P99)

% Fallback se banda troppo piccola:
% - winsorize: prendi top>=P95, taglia a P99, poi mediana
cfg.useWinsorFallback = true;

% Salvataggi
cfg.saveR0Table = true;
cfg.saveDiagnosticPlot = true; % salva un plot di R0 per il primo sensore

%% ===================== INPUT =====================
[inFile, inPath] = uigetfile('*.csv', 'Seleziona CSV di monitoraggio');
if isequal(inFile,0)
    disp('Operazione annullata.');
    return;
end
inCsv = fullfile(inPath, inFile);

outDir = uigetdir(inPath, 'Seleziona cartella OUTPUT');
if isequal(outDir,0)
    outDir = inPath;
end
if ~isfolder(outDir)
    mkdir(outDir);
end

%% ===================== LOAD =====================
T = readtable(inCsv, 'PreserveVariableNames', true);

% Check colonna tempo
if ~ismember(cfg.timeCol, T.Properties.VariableNames)
    error('Manca la colonna tempo "%s" nel CSV.', cfg.timeCol);
end

% Parse timestamp -> datetime
t = local_parse_timestamp(T.(cfg.timeCol));

% Costruisci "day" robusto senza dateshift
dayVec = datetime(year(t), month(t), day(t));

% Aggiungi colonne helper (nomi semplici, senza __)
T.dt  = t;
T.day = dayVec;

%% ===================== SELECT COLS =====================
varNames = T.Properties.VariableNames;

if ~isempty(cfg.explicitCols)
    cols = cfg.explicitCols;
else
    % autodetect prefix MAG
    cols = {};
    for i = 1:numel(varNames)
        vn = varNames{i};
        if strncmp(vn, cfg.autoDetectPrefix, length(cfg.autoDetectPrefix))
            cols{end+1} = vn; %#ok<AGROW>
        end
    end
end

% Rimuovi colonna tempo se per caso matcha
cols = cols(~strcmp(cols, cfg.timeCol));

if isempty(cols)
    error('Nessuna colonna trovata da normalizzare (prefix "%s").', cfg.autoDetectPrefix);
end

% Check numerico
for i = 1:numel(cols)
    if ~isnumeric(T.(cols{i}))
        error('La colonna "%s" non e'' numerica.', cols{i});
    end
end

fprintf('Colonne da normalizzare (%d): %s\n', numel(cols), strjoin(cols, ', '));

%% ===================== CALCOLO R0 DAILY =====================
days = unique(T.day);
nDays = numel(days);
nCols = numel(cols);

% Tabella R0: Day + una colonna per ogni sensore
R0 = array2table(nan(nDays, nCols), 'VariableNames', cols);
R0.Day = days;
R0 = movevars(R0, 'Day', 'Before', 1);

% (opzionale) info diagnostica minima
Nday  = nan(nDays,1);
Nband = nan(nDays,1);

for d = 1:nDays
    idxDay = (T.day == days(d));
    Nday(d) = sum(idxDay);

    for j = 1:nCols
        y = T.(cols{j});
        yDay = y(idxDay);
        yDay = yDay(~isnan(yDay) & isfinite(yDay));

        if numel(yDay) < max(10, round(cfg.minPointsDay/10))
            R0{d, cols{j}} = NaN;
            continue;
        end

        p95 = prctile(yDay, cfg.pLow);
        p99 = prctile(yDay, cfg.pHigh);

        band = yDay(yDay >= p95 & yDay < p99);
        Nband(d) = max(Nband(d), numel(band));

        if numel(band) >= cfg.minPointsBand
            R0{d, cols{j}} = median(band);
        else
            if cfg.useWinsorFallback
                yTop = yDay(yDay >= p95);
                yTop(yTop > p99) = p99; % cap a P99
                R0{d, cols{j}} = median(yTop);
            else
                R0{d, cols{j}} = p95;
            end
        end
    end
end

% Fill missing: forward poi backward
for j = 1:nCols
    v = R0.(cols{j});
    v = fillmissing(v, 'previous');
    v = fillmissing(v, 'next');
    R0.(cols{j}) = v;
end

%% ===================== APPLICA NORMALIZZAZIONE =====================
% Mappa ogni riga del CSV al suo giorno
[~, dayIdx] = ismember(T.day, R0.Day);

for j = 1:nCols
    colName = cols{j};

    r0_by_day = R0.(colName);
    r0_per_row = r0_by_day(dayIdx);

    y = T.(colName);

    if strcmpi(cfg.normType, 'RR0')
        yN = y ./ r0_per_row;
    elseif strcmpi(cfg.normType, 'Rminus')
        yN = y - r0_per_row;
    else
        error('cfg.normType deve essere "RR0" oppure "Rminus".');
    end

    if strcmpi(cfg.outputMode, 'replace')
        T.(colName) = yN;
    else
        T.([colName '_NORM']) = yN;
    end
end

%% ===================== SALVATAGGIO =====================
base = inFile;
if length(base) >= 4 && strcmpi(base(end-3:end), '.csv')
    base = base(1:end-4);
end

suffix = sprintf('_DAILY_R0_P%dtoP%d_%s_%s', cfg.pLow, cfg.pHigh, upper(cfg.normType), cfg.outputMode);
outCsv = fullfile(outDir, [base suffix '.csv']);

% Rimuovi helper columns prima di salvare
Tout = T;
Tout.dt  = [];
Tout.day = [];

writetable(Tout, outCsv);
fprintf('\nSalvato CSV normalizzato:\n  %s\n', outCsv);

if cfg.saveR0Table
    outR0 = fullfile(outDir, [base suffix '_R0_daily.csv']);

    R0out = R0;
    R0out.N_day  = Nday;
    R0out.N_band = Nband;

    writetable(R0out, outR0);
    fprintf('Salvata tabella R0 giornalieri:\n  %s\n', outR0);
end

%% ===================== PLOT DIAGNOSTICO =====================
if cfg.saveDiagnosticPlot
    try
        firstCol = cols{1};
        figure('Color','w');
        plot(R0.Day, R0.(firstCol), '-o'); grid on;
        xlabel('Day');
        ylabel('R0');
        title(sprintf('R0 giornaliero (%s) - banda P%d-P%d', firstCol, cfg.pLow, cfg.pHigh));
        outPng = fullfile(outDir, [base suffix '_R0plot_' firstCol '.png']);
        exportgraphics(gcf, outPng, 'Resolution', 180);
        close(gcf);
        fprintf('Salvato plot diagnostico:\n  %s\n', outPng);
    catch ME
        warning('Plot diagnostico non riuscito: %s', ME.message);
    end
end

disp('Fatto.');

end

%% =====================================================================
function t = local_parse_timestamp(x)
% local_parse_timestamp
% Prova a convertire la colonna timestamp in datetime.
% Supporta:
% - datetime gia'
% - string/cellstr con formati comuni
% - numerico epoch in ms o s
% - numerico "secondi da inizio" (fallback)

if isdatetime(x)
    t = x;
    return;
end

% cell -> string
if iscell(x)
    xs = string(x);
    t = local_try_datetime_from_string(xs);
    return;
end

% string/char
if isstring(x) || ischar(x)
    xs = string(x);
    t = local_try_datetime_from_string(xs);
    return;
end

% numerico
if isnumeric(x)
    v = double(x(:));
    v = v(~isnan(v) & isfinite(v));
    if isempty(v)
        error('Timestamp numerico ma tutti NaN/Inf.');
    end
    medv = median(v);

    if medv > 1e12
        % epoch in ms
        t = datetime(double(x)/1000, 'ConvertFrom', 'posixtime');
    elseif medv > 1e9
        % epoch in s
        t = datetime(double(x), 'ConvertFrom', 'posixtime');
    else
        % fallback: assume seconds from start
        v0 = double(x(1));
        t0 = datetime('now');
        t = t0 + seconds(double(x) - v0);
    end
    return;
end

error('Formato timestamp non riconosciuto.');
end

function t = local_try_datetime_from_string(xs)
% prova vari formati comuni

% 1) datetime auto
try
    t = datetime(xs);
    if ~any(isnat(t))
        return;
    end
catch
end

% 2) formati tipici
fmts = { ...
    'yyyy-MM-dd HH:mm:ss', ...
    'yyyy-MM-dd HH:mm:ss.SSS', ...
    'yyyy/MM/dd HH:mm:ss', ...
    'dd/MM/yyyy HH:mm:ss', ...
    'dd-MM-yyyy HH:mm:ss', ...
    'yyyy-MM-dd''T''HH:mm:ss', ...
    'yyyy-MM-dd''T''HH:mm:ss.SSS' ...
    };

for i = 1:numel(fmts)
    try
        t = datetime(xs, 'InputFormat', fmts{i});
        if ~any(isnat(t))
            return;
        end
    catch
    end
end

% se fallisce
error('Impossibile convertire timestamp da stringa. Esempio: %s', xs(1));
end