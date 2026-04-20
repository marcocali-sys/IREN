function [isBaseline, R0, P95_row, P99_row] = ellona_select_baseline( ...
    X_mox, datetimes, pLow, pHigh, minBandPts, mode)
% ELLONA_SELECT_BASELINE
%   Seleziona i punti di "aria pulita" (baseline) dai dati di monitoraggio
%   continuo ELLONA usando la banda alta [P_low, P_high) del segnale MOX.
%
%   Logica:
%     - I sensori MOX hanno risposta NEGATIVA agli odori (resistenza cala
%       con la presenza di gas). Quindi i valori ALTI corrispondono ad
%       aria pulita.
%     - Per ogni periodo (giorno/settimana/mese/globale) e per ogni sensore,
%       si calcola la banda [P95, P99). Un punto è baseline se TUTTI i MOX
%       rientrano nella propria banda (intersezione).
%     - R0(periodo, sensore) = mediana dei punti nella banda = valore di
%       riferimento per quella finestra temporale.
%
%   Inputs:
%     X_mox      : [N x 4] double  — valori raw cmos1,cmos2,cmos3,cmos4
%     datetimes  : [N x 1] datetime
%     pLow       : scalar (es. 95)  — percentile inferiore banda baseline
%     pHigh      : scalar (es. 99)  — percentile superiore (outlier threshold)
%     minBandPts : scalar (es. 20)  — min punti [P95,P99) per periodo valido
%     mode       : char/string — 'daily' | 'weekly' | 'monthly' | 'global'
%
%   Outputs:
%     isBaseline : [N x 1] logical  — true se il punto è baseline
%     R0         : [N x 4] double   — R0 per ogni riga e sensore (via periodo)
%     P95_row    : [N x 4] double   — soglia P95 per ogni riga
%     P99_row    : [N x 4] double   — soglia P99 per ogni riga

nRows = size(X_mox, 1);
nMox  = size(X_mox, 2);

%% Vettore periodo di raggruppamento
switch lower(char(mode))
    case 'daily'
        period = dateshift(datetimes, 'start', 'day');
    case 'weekly'
        period = dateshift(datetimes, 'start', 'week');
    case 'monthly'
        period = dateshift(datetimes, 'start', 'month');
    case 'global'
        period = repmat(datetimes(1), nRows, 1);
    otherwise
        error('ellona_select_baseline: mode non valido: "%s"', mode);
end

%% Indici periodo
[uniqPeriods, ~, period_idx] = unique(period);
nPeriods = numel(uniqPeriods);

%% Pre-alloca tabelle per periodo
P95_by_period = NaN(nPeriods, nMox);
P99_by_period = NaN(nPeriods, nMox);
R0_by_period  = NaN(nPeriods, nMox);

for p = 1:nPeriods
    mask_p = (period_idx == p);

    for j = 1:nMox
        x = X_mox(mask_p, j);
        x = x(isfinite(x));

        if numel(x) < 50
            % Troppo pochi dati: periodo saltato
            continue;
        end

        p95 = prctile(x, pLow);
        p99 = prctile(x, pHigh);

        P95_by_period(p, j) = p95;
        P99_by_period(p, j) = p99;

        % R0 = mediana dei punti nella banda [P95, P99)
        band = x(x >= p95 & x < p99);

        if numel(band) >= minBandPts
            R0_by_period(p, j) = median(band);
        else
            % Fallback: top >= P95 con cap a P99, poi mediana
            topVals = x(x >= p95);
            topVals(topVals > p99) = p99;
            R0_by_period(p, j) = median(topVals);
        end
    end
end

%% Propaga per riga
P95_row = P95_by_period(period_idx, :);   % N x 4
P99_row = P99_by_period(period_idx, :);   % N x 4
R0      = R0_by_period(period_idx, :);    % N x 4

%% Flag baseline: tutti i MOX nel range [P95, P99) e soglie valide
in_band    = (X_mox >= P95_row) & (X_mox <  P99_row);
valid_thr  = all(isfinite(P95_row), 2);
isBaseline = all(in_band, 2) & valid_thr;

end
