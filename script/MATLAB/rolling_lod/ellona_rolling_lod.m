function [lod_lo, lod_hi, mu_out, sigma_out] = ellona_rolling_lod( ...
    t, PC1, X_mox, pLow, pHigh, k, window_days, step_days, minPts, ...
    lod_lo_global, lod_hi_global)
%ELLONA_ROLLING_LOD  LOD mobile su PC1 con finestra scorrevole causale.
%
%   Per ogni step giornaliero calcola:
%     1. Finestra causale [t - window_days, t)
%     2. Selezione baseline IQR [pLow, pHigh] su tutti i MOX
%     3. μ(t) = mean(PC1_baseline),  σ(t) = std(PC1_baseline)
%     4. LOD_lo(t) = μ(t) - k·σ(t),  LOD_hi(t) = μ(t) + k·σ(t)
%
%   Cold start (primi window_days): fallback al LOD globale.
%   Gap (finestre con troppo pochi dati): carry-forward del valore precedente.
%
%   Inputs:
%     t, PC1        : N×1 datetime / double  (serie completa)
%     X_mox         : N×4 double  (valori raw cmos1-4, per selezione baseline)
%     pLow/pHigh    : percentili IQR (es. 25, 75)
%     k             : moltiplicatore LOD
%     window_days   : ampiezza finestra (es. 7)
%     step_days     : passo griglia giornaliera (es. 1)
%     minPts        : min punti baseline per validare la finestra (es. 100)
%     lod_lo/hi_global : LOD globale → fallback cold-start
%
%   Outputs:
%     lod_lo/hi   : N×1 — banda LOD interpolata ai punti originali
%     mu_out      : N×1 — μ rolling interpolata
%     sigma_out   : N×1 — σ rolling interpolata
%
%   Marco Calì — PoliMi, Aprile 2026

N    = numel(t);
nMox = size(X_mox, 2);

% Ricava μ e σ globali dal LOD globale (μ_pc1 ≈ 0, σ = LOD_range / 2k)
mu_global    = (lod_lo_global + lod_hi_global) / 2;
sigma_global = (lod_hi_global - lod_lo_global) / (2 * k);

%% ── GRIGLIA DI VALUTAZIONE ───────────────────────────────────────────────
% Primo punto valutabile: t(1) + window_days (serve la finestra piena)
t_grid_start = dateshift(t(1),   'start','day') + days(window_days);
t_grid_end   = dateshift(t(end), 'start','day');

if t_grid_start > t_grid_end
    warning('ellona_rolling_lod: dataset troppo corto per rolling LOD. Uso LOD globale.');
    lod_lo    = repmat(lod_lo_global, N, 1);
    lod_hi    = repmat(lod_hi_global, N, 1);
    mu_out    = repmat(mu_global,     N, 1);
    sigma_out = repmat(sigma_global,  N, 1);
    return;
end

t_grid  = (t_grid_start : days(step_days) : t_grid_end)';
n_grid  = numel(t_grid);

mu_grid    = NaN(n_grid, 1);
sigma_grid = NaN(n_grid, 1);

%% ── CALCOLO PER OGNI PASSO ───────────────────────────────────────────────
fprintf('  Griglia rolling: %d giorni × finestra %dd...  ', n_grid, window_days);
tic;

for i = 1:n_grid
    t_hi = t_grid(i);
    t_lo = t_hi - days(window_days);

    % Indici della finestra (t è ordinato → find con early exit)
    i_lo = find(t >= t_lo, 1, 'first');
    i_hi = find(t <  t_hi, 1, 'last');
    if isempty(i_lo) || isempty(i_hi) || i_hi < i_lo
        continue;
    end

    X_w   = X_mox(i_lo:i_hi, :);
    pc1_w = PC1(i_lo:i_hi);
    nW    = size(X_w, 1);

    if nW < minPts * 2, continue; end

    % Selezione baseline: intersezione IQR su tutti i MOX
    in_band = true(nW, 1);
    for j = 1:nMox
        x = X_w(:, j);
        x = x(isfinite(x));
        if numel(x) < 30
            in_band(:) = false; break;
        end
        p_lo = prctile(x, pLow);
        p_hi = prctile(x, pHigh);
        in_band = in_band & (X_w(:,j) >= p_lo) & (X_w(:,j) < p_hi);
    end

    pc1_bl = pc1_w(in_band);
    if numel(pc1_bl) < minPts, continue; end

    mu_grid(i)    = mean(pc1_bl, 'omitnan');
    sigma_grid(i) = std( pc1_bl, 'omitnan');
end

fprintf('%.1fs\n', toc);
n_valid = sum(~isnan(mu_grid));
fprintf('  Finestre valide: %d / %d  (%.0f%%)\n', n_valid, n_grid, 100*n_valid/n_grid);

%% ── INTERPOLAZIONE ALLA RISOLUZIONE ORIGINALE ───────────────────────────
% 1. Riempi NaN con carry-forward (poi carry-backward per i buchi iniziali)
mu_grid    = fillmissing(mu_grid,    'previous');
sigma_grid = fillmissing(sigma_grid, 'previous');
mu_grid    = fillmissing(mu_grid,    'next');
sigma_grid = fillmissing(sigma_grid, 'next');

% 2. Se ancora NaN (dataset vuoto), usa globale
mu_grid(isnan(mu_grid))       = mu_global;
sigma_grid(isnan(sigma_grid)) = sigma_global;

% 3. LOD sulla griglia giornaliera
%    Opzione B: solo μ è rolling (correzione drift), σ rimane globale
%    → larghezza banda fissa = stesso noise-floor del LOD fisso
lod_lo_grid = mu_grid - k * sigma_global;
lod_hi_grid = mu_grid + k * sigma_global;

% 4. Interpolazione lineare ai punti originali (dentro il range)
t_num   = datenum(t);
tg_num  = datenum(t_grid);

lod_lo_i  = interp1(tg_num, lod_lo_grid, t_num, 'linear');
lod_hi_i  = interp1(tg_num, lod_hi_grid, t_num, 'linear');
mu_i      = interp1(tg_num, mu_grid,     t_num, 'linear');
sigma_i   = interp1(tg_num, sigma_grid,  t_num, 'linear');

% 5. Cold start (prima della prima finestra valida): LOD globale
mask_cold = t < t_grid(1);
lod_lo_i(mask_cold) = lod_lo_global;
lod_hi_i(mask_cold) = lod_hi_global;
mu_i(mask_cold)     = mu_global;
sigma_i(mask_cold)  = sigma_global;

% 6. Eventuali NaN residui (dopo t_grid(end)): carry-forward ultimo valore
mask_nan = isnan(lod_lo_i);
if any(mask_nan)
    lod_lo_i(mask_nan) = lod_lo_grid(end);
    lod_hi_i(mask_nan) = lod_hi_grid(end);
    mu_i(mask_nan)     = mu_grid(end);
    sigma_i(mask_nan)  = sigma_grid(end);
end

lod_lo    = lod_lo_i;
lod_hi    = lod_hi_i;
mu_out    = mu_i;
sigma_out = sigma_i;

end
