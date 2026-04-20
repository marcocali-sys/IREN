"""
09_monitoraggio_explorer.py
===========================
GUI interattiva per esplorare i dati di monitoraggio IREN 2025.

Funzionalità:
  - Caricamento automatico di tutti i file CSV nella cartella monitoraggio2025
  - Normalizzazione dei nomi colonna (gestisce la diversa colonna di dicembre_2025.csv)
  - Selezione variabili da plottare (MOX, ECS, T, RH)
  - Selezione libera della finestra temporale (data/ora inizio e fine)
  - Plot multiplo su assi separati per variabili con scale molto diverse

Assunzioni:
  - Separatore CSV: semicolon (;)
  - Formato data: DD/MM/YYYY (italiano)
  - Formato ora: HH:MM:SS
  - Risoluzione temporale: 10 secondi
  - Le 11 colonne sono sempre presenti ma possono essere in ordine diverso
  - Encoding: UTF-8

Dipendenze: pandas, matplotlib (tkinter incluso nella stdlib)

Autore: [Marco Cali] — Progetto IREN
"""

import os
import glob
import tkinter as tk
from tkinter import ttk, messagebox

import pandas as pd
import matplotlib
matplotlib.use("TkAgg")
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg, NavigationToolbar2Tk

# ─────────────────────────────────────────────────────────────────
# CONFIGURAZIONE
# ─────────────────────────────────────────────────────────────────

DATA_DIR = os.path.join(
    os.path.dirname(__file__), "../../data/raw/monitoraggio2025"
)

# Nomi canonici delle variabili (come appaiono nelle colonne CSV)
VARIABLE_DEFS = {
    # label GUI     : nome colonna CSV
    "MOX 1 (cmos1)": "cmos1",
    "MOX 2 (cmos2)": "cmos2",
    "MOX 3 (cmos3)": "cmos3",
    "MOX 4 (cmos4)": "cmos4",
    "ECS NH3 (nh3)": "nh3",
    "ECS H2S (h2s)": "h2s",
    "Temperatura (T)": "temperature",
    "Umidità (RH)":  "humidity",
}

# Colori di default per ciascuna variabile
VAR_COLORS = {
    "cmos1":       "#1f77b4",
    "cmos2":       "#ff7f0e",
    "cmos3":       "#2ca02c",
    "cmos4":       "#d62728",
    "nh3":         "#9467bd",
    "h2s":         "#8c564b",
    "temperature": "#e377c2",
    "humidity":    "#17becf",
}

# ─────────────────────────────────────────────────────────────────
# CARICAMENTO DATI
# ─────────────────────────────────────────────────────────────────

def load_all_files(data_dir: str) -> pd.DataFrame:
    """
    Legge tutti i file CSV nella cartella data_dir, li normalizza e li unisce.

    Gestisce:
      - ordine delle colonne diverso tra file (es. dicembre_2025.csv)
      - float precision artifacts (es. 19.29999924 → letti così ma usati as-is)
      - duplicati di timestamp (rimossi tenendo il primo)
    """
    csv_files = sorted(glob.glob(os.path.join(data_dir, "*.csv")))
    if not csv_files:
        raise FileNotFoundError(f"Nessun file CSV trovato in: {data_dir}")

    frames = []
    for fpath in csv_files:
        fname = os.path.basename(fpath)
        try:
            df = pd.read_csv(
                fpath,
                sep=";",
                encoding="utf-8",
                dtype=str,           # leggi tutto come stringa per sicurezza
                low_memory=False,
            )
            # Normalizza nomi colonna: strip e lowercase
            df.columns = [c.strip().lower() for c in df.columns]

            # Verifica che le colonne attese siano presenti
            required = {"date", "time", "cmos1", "cmos2", "cmos3", "cmos4",
                        "temperature", "humidity", "nh3", "h2s"}
            missing = required - set(df.columns)
            if missing:
                print(f"[WARN] {fname}: colonne mancanti {missing} — saltato")
                continue

            frames.append(df)
            print(f"[OK] Caricato {fname} ({len(df):,} righe)")

        except Exception as e:
            print(f"[ERR] Impossibile leggere {fname}: {e}")

    if not frames:
        raise ValueError("Nessun file caricato correttamente.")

    # Concatenazione
    combined = pd.concat(frames, ignore_index=True)

    # Parsing del timestamp
    combined["datetime"] = pd.to_datetime(
        combined["date"].str.strip() + " " + combined["time"].str.strip(),
        format="%d/%m/%Y %H:%M:%S",
        errors="coerce",
    )

    # Rimuovi righe con timestamp non parsabile
    n_bad = combined["datetime"].isna().sum()
    if n_bad > 0:
        print(f"[WARN] {n_bad} righe con timestamp non valido rimosse.")
    combined = combined.dropna(subset=["datetime"])

    # Conversione numerica delle colonne sensore
    numeric_cols = ["cmos1", "cmos2", "cmos3", "cmos4",
                    "temperature", "humidity", "nh3", "h2s", "pid"]
    for col in numeric_cols:
        if col in combined.columns:
            combined[col] = pd.to_numeric(combined[col], errors="coerce")

    # Ordinamento cronologico
    combined = combined.sort_values("datetime").reset_index(drop=True)

    # Rimozione duplicati di timestamp (tieni primo)
    n_dup = combined.duplicated(subset="datetime").sum()
    if n_dup > 0:
        print(f"[INFO] {n_dup} timestamp duplicati rimossi.")
    combined = combined.drop_duplicates(subset="datetime", keep="first")

    print(f"\n[INFO] Dataset totale: {len(combined):,} righe | "
          f"da {combined['datetime'].min()} a {combined['datetime'].max()}\n")

    return combined


# ─────────────────────────────────────────────────────────────────
# APPLICAZIONE GUI
# ─────────────────────────────────────────────────────────────────

class MonitoraggioExplorer(tk.Tk):
    """Finestra principale dell'applicazione."""

    def __init__(self, df: pd.DataFrame):
        super().__init__()
        self.df = df
        self.title("IREN — Monitoraggio 2025 Explorer")
        self.configure(bg="#f5f5f5")
        self.minsize(1100, 650)

        # Stato variabili selezionabili
        self.var_checks: dict[str, tk.BooleanVar] = {
            label: tk.BooleanVar(value=False)
            for label in VARIABLE_DEFS
        }

        # ── Layout principale ──────────────────────────────────
        self._build_sidebar()
        self._build_plot_area()

        # Imposta il range temporale completo come default
        t_min = self.df["datetime"].min()
        t_max = self.df["datetime"].max()
        self.entry_start_date.insert(0, t_min.strftime("%d/%m/%Y"))
        self.entry_start_time.insert(0, t_min.strftime("%H:%M:%S"))
        self.entry_end_date.insert(0, t_max.strftime("%d/%m/%Y"))
        self.entry_end_time.insert(0, t_max.strftime("%H:%M:%S"))

    # ──────────────────────────────────────────────────────────
    # COSTRUZIONE INTERFACCIA
    # ──────────────────────────────────────────────────────────

    def _build_sidebar(self):
        """Pannello sinistro: controlli."""
        sidebar = tk.Frame(self, bg="#2c3e50", width=260)
        sidebar.pack(side=tk.LEFT, fill=tk.Y, padx=0, pady=0)
        sidebar.pack_propagate(False)

        # Titolo sidebar
        tk.Label(
            sidebar, text="IREN Explorer", bg="#2c3e50", fg="white",
            font=("Helvetica", 14, "bold"), pady=12
        ).pack(fill=tk.X)

        separator = tk.Frame(sidebar, bg="#4a6278", height=1)
        separator.pack(fill=tk.X, padx=10)

        # ── Sezione variabili ──────────────────────────────────
        self._sidebar_section(sidebar, "VARIABILI")

        # MOX
        self._sidebar_label(sidebar, "MOX")
        for label in ["MOX 1 (cmos1)", "MOX 2 (cmos2)",
                      "MOX 3 (cmos3)", "MOX 4 (cmos4)"]:
            self._var_checkbox(sidebar, label)

        self._sidebar_label(sidebar, "ECS")
        for label in ["ECS NH3 (nh3)", "ECS H2S (h2s)"]:
            self._var_checkbox(sidebar, label)

        self._sidebar_label(sidebar, "Ambiente")
        for label in ["Temperatura (T)", "Umidità (RH)"]:
            self._var_checkbox(sidebar, label)

        # Bottoni seleziona/deseleziona tutto
        btn_frame = tk.Frame(sidebar, bg="#2c3e50")
        btn_frame.pack(fill=tk.X, padx=10, pady=(6, 0))
        tk.Button(
            btn_frame, text="Seleziona tutto", bg="#4a6278", fg="white",
            bd=0, relief=tk.FLAT, cursor="hand2", font=("Helvetica", 9),
            command=self._select_all
        ).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=(0, 3))
        tk.Button(
            btn_frame, text="Deseleziona tutto", bg="#4a6278", fg="white",
            bd=0, relief=tk.FLAT, cursor="hand2", font=("Helvetica", 9),
            command=self._deselect_all
        ).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=(3, 0))

        separator2 = tk.Frame(sidebar, bg="#4a6278", height=1)
        separator2.pack(fill=tk.X, padx=10, pady=10)

        # ── Sezione finestra temporale ─────────────────────────
        self._sidebar_section(sidebar, "FINESTRA TEMPORALE")

        # Inizio
        self._sidebar_label(sidebar, "Inizio")
        row1 = tk.Frame(sidebar, bg="#2c3e50")
        row1.pack(fill=tk.X, padx=10, pady=2)
        self.entry_start_date = self._entry(row1, placeholder="DD/MM/YYYY", width=11)
        self.entry_start_date.pack(side=tk.LEFT)
        tk.Label(row1, text=" ", bg="#2c3e50").pack(side=tk.LEFT)
        self.entry_start_time = self._entry(row1, placeholder="HH:MM:SS", width=9)
        self.entry_start_time.pack(side=tk.LEFT)

        # Fine
        self._sidebar_label(sidebar, "Fine")
        row2 = tk.Frame(sidebar, bg="#2c3e50")
        row2.pack(fill=tk.X, padx=10, pady=2)
        self.entry_end_date = self._entry(row2, placeholder="DD/MM/YYYY", width=11)
        self.entry_end_date.pack(side=tk.LEFT)
        tk.Label(row2, text=" ", bg="#2c3e50").pack(side=tk.LEFT)
        self.entry_end_time = self._entry(row2, placeholder="HH:MM:SS", width=9)
        self.entry_end_time.pack(side=tk.LEFT)

        # Shortcut: tutto il mese corrente / ultima settimana
        shortcut_frame = tk.Frame(sidebar, bg="#2c3e50")
        shortcut_frame.pack(fill=tk.X, padx=10, pady=(8, 0))
        tk.Button(
            shortcut_frame, text="Tutto", bg="#4a6278", fg="white",
            bd=0, relief=tk.FLAT, cursor="hand2", font=("Helvetica", 9),
            command=self._range_all
        ).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=(0, 3))
        tk.Button(
            shortcut_frame, text="Ultimo mese", bg="#4a6278", fg="white",
            bd=0, relief=tk.FLAT, cursor="hand2", font=("Helvetica", 9),
            command=self._range_last_month
        ).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=(3, 0))

        shortcut_frame2 = tk.Frame(sidebar, bg="#2c3e50")
        shortcut_frame2.pack(fill=tk.X, padx=10, pady=(4, 0))
        tk.Button(
            shortcut_frame2, text="Ultima settimana", bg="#4a6278", fg="white",
            bd=0, relief=tk.FLAT, cursor="hand2", font=("Helvetica", 9),
            command=self._range_last_week
        ).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=(0, 3))
        tk.Button(
            shortcut_frame2, text="Ultimo giorno", bg="#4a6278", fg="white",
            bd=0, relief=tk.FLAT, cursor="hand2", font=("Helvetica", 9),
            command=self._range_last_day
        ).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=(3, 0))

        # ── Opzioni downsampling ───────────────────────────────
        separator3 = tk.Frame(sidebar, bg="#4a6278", height=1)
        separator3.pack(fill=tk.X, padx=10, pady=10)

        self._sidebar_section(sidebar, "OPZIONI")
        ds_frame = tk.Frame(sidebar, bg="#2c3e50")
        ds_frame.pack(fill=tk.X, padx=10, pady=4)
        tk.Label(ds_frame, text="Resampling:", bg="#2c3e50", fg="#bdc3c7",
                 font=("Helvetica", 9)).pack(side=tk.LEFT)
        self.resample_var = tk.StringVar(value="nessuno")
        options = ["nessuno", "1 min", "5 min", "15 min", "1 h"]
        resample_menu = ttk.Combobox(
            ds_frame, textvariable=self.resample_var,
            values=options, width=8, state="readonly"
        )
        resample_menu.pack(side=tk.LEFT, padx=(6, 0))

        # ── Bottone plotta ─────────────────────────────────────
        separator4 = tk.Frame(sidebar, bg="#4a6278", height=1)
        separator4.pack(fill=tk.X, padx=10, pady=10)

        tk.Button(
            sidebar, text="PLOTTA", bg="#27ae60", fg="white",
            font=("Helvetica", 12, "bold"), bd=0, relief=tk.FLAT,
            cursor="hand2", pady=10,
            command=self._do_plot
        ).pack(fill=tk.X, padx=10)

        # Barra di stato
        self.status_var = tk.StringVar(value="Pronto.")
        tk.Label(
            sidebar, textvariable=self.status_var,
            bg="#2c3e50", fg="#95a5a6",
            font=("Helvetica", 8), wraplength=240, justify=tk.LEFT
        ).pack(fill=tk.X, padx=10, pady=(8, 4))

    def _build_plot_area(self):
        """Pannello destro: area grafico."""
        plot_frame = tk.Frame(self, bg="#f5f5f5")
        plot_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        self.fig, self.ax_main = plt.subplots(figsize=(10, 6))
        self.fig.patch.set_facecolor("#f5f5f5")
        self.ax_main.set_visible(False)  # nascosto finché non si plotta

        self.canvas = FigureCanvasTkAgg(self.fig, master=plot_frame)
        self.canvas.get_tk_widget().pack(fill=tk.BOTH, expand=True)

        toolbar = NavigationToolbar2Tk(self.canvas, plot_frame)
        toolbar.update()

        # Messaggio placeholder
        self.fig.text(
            0.5, 0.5,
            "Seleziona variabili e finestra temporale,\npoi premi PLOTTA",
            ha="center", va="center",
            fontsize=14, color="#95a5a6",
            transform=self.fig.transFigure
        )
        self.canvas.draw()

    # ──────────────────────────────────────────────────────────
    # HELPER WIDGET
    # ──────────────────────────────────────────────────────────

    def _sidebar_section(self, parent, text):
        tk.Label(
            parent, text=text, bg="#2c3e50", fg="#ecf0f1",
            font=("Helvetica", 10, "bold"), anchor="w", pady=4, padx=10
        ).pack(fill=tk.X)

    def _sidebar_label(self, parent, text):
        tk.Label(
            parent, text=text, bg="#2c3e50", fg="#bdc3c7",
            font=("Helvetica", 8, "italic"), anchor="w", padx=14
        ).pack(fill=tk.X)

    def _var_checkbox(self, parent, label):
        col = VARIABLE_DEFS[label]
        color = VAR_COLORS.get(col, "white")
        cb = tk.Checkbutton(
            parent, text=label,
            variable=self.var_checks[label],
            bg="#2c3e50", fg="white", selectcolor="#34495e",
            activebackground="#2c3e50", activeforeground=color,
            font=("Helvetica", 9), anchor="w", padx=20,
            indicatoron=True,
        )
        cb.pack(fill=tk.X)

    @staticmethod
    def _entry(parent, placeholder="", width=12):
        e = tk.Entry(
            parent, width=width, bg="#34495e", fg="#ecf0f1",
            insertbackground="white", bd=1, relief=tk.FLAT,
            font=("Helvetica", 10)
        )
        return e

    # ──────────────────────────────────────────────────────────
    # SHORTCUT RANGE
    # ──────────────────────────────────────────────────────────

    def _set_range(self, t_start: pd.Timestamp, t_end: pd.Timestamp):
        for e in [self.entry_start_date, self.entry_start_time,
                  self.entry_end_date, self.entry_end_time]:
            e.delete(0, tk.END)
        self.entry_start_date.insert(0, t_start.strftime("%d/%m/%Y"))
        self.entry_start_time.insert(0, t_start.strftime("%H:%M:%S"))
        self.entry_end_date.insert(0, t_end.strftime("%d/%m/%Y"))
        self.entry_end_time.insert(0, t_end.strftime("%H:%M:%S"))

    def _range_all(self):
        self._set_range(self.df["datetime"].min(), self.df["datetime"].max())

    def _range_last_month(self):
        t_end = self.df["datetime"].max()
        t_start = t_end - pd.DateOffset(months=1)
        self._set_range(max(t_start, self.df["datetime"].min()), t_end)

    def _range_last_week(self):
        t_end = self.df["datetime"].max()
        t_start = t_end - pd.Timedelta(days=7)
        self._set_range(max(t_start, self.df["datetime"].min()), t_end)

    def _range_last_day(self):
        t_end = self.df["datetime"].max()
        t_start = t_end - pd.Timedelta(days=1)
        self._set_range(max(t_start, self.df["datetime"].min()), t_end)

    def _select_all(self):
        for v in self.var_checks.values():
            v.set(True)

    def _deselect_all(self):
        for v in self.var_checks.values():
            v.set(False)

    # ──────────────────────────────────────────────────────────
    # LOGICA DI PLOT
    # ──────────────────────────────────────────────────────────

    def _parse_datetime_input(self) -> tuple[pd.Timestamp, pd.Timestamp]:
        """Legge e valida i campi data/ora. Ritorna (t_start, t_end)."""
        start_str = (self.entry_start_date.get().strip() + " " +
                     self.entry_start_time.get().strip())
        end_str   = (self.entry_end_date.get().strip() + " " +
                     self.entry_end_time.get().strip())
        try:
            t_start = pd.to_datetime(start_str, format="%d/%m/%Y %H:%M:%S")
        except Exception:
            raise ValueError(f"Formato data/ora inizio non valido: '{start_str}'\n"
                             "Usare DD/MM/YYYY HH:MM:SS")
        try:
            t_end = pd.to_datetime(end_str, format="%d/%m/%Y %H:%M:%S")
        except Exception:
            raise ValueError(f"Formato data/ora fine non valido: '{end_str}'\n"
                             "Usare DD/MM/YYYY HH:MM:SS")
        if t_start >= t_end:
            raise ValueError("La data/ora di inizio deve essere precedente alla fine.")
        return t_start, t_end

    def _get_selected_vars(self) -> list[tuple[str, str]]:
        """Ritorna lista di (label, colonna) delle variabili selezionate."""
        return [
            (label, VARIABLE_DEFS[label])
            for label, bvar in self.var_checks.items()
            if bvar.get()
        ]

    def _do_plot(self):
        """Esegue il plot con le impostazioni correnti."""
        # Variabili selezionate
        selected = self._get_selected_vars()
        if not selected:
            messagebox.showwarning("Nessuna variabile", "Seleziona almeno una variabile.")
            return

        # Parsing finestra temporale
        try:
            t_start, t_end = self._parse_datetime_input()
        except ValueError as e:
            messagebox.showerror("Errore data/ora", str(e))
            return

        # Filtro dati
        mask = (self.df["datetime"] >= t_start) & (self.df["datetime"] <= t_end)
        subset = self.df.loc[mask].copy()

        if subset.empty:
            messagebox.showinfo("Nessun dato", "Nessun dato nel periodo selezionato.")
            return

        # Resampling (opzionale)
        resample_map = {
            "1 min": "1min", "5 min": "5min",
            "15 min": "15min", "1 h": "1h"
        }
        resample_rule = resample_map.get(self.resample_var.get())
        if resample_rule:
            subset = (
                subset.set_index("datetime")
                      .resample(resample_rule)
                      .mean(numeric_only=True)
                      .reset_index()
            )

        n_points = len(subset)
        self.status_var.set(f"{n_points:,} punti | {t_start:%d/%m/%Y %H:%M} → {t_end:%d/%m/%Y %H:%M}")

        # ── Costruzione figure con subplots ──────────────────
        # Raggruppa variabili con scale simili per ridurre il numero di assi
        groups = self._group_variables(selected)
        n_axes = len(groups)

        self.fig.clear()
        axes = self.fig.subplots(n_axes, 1, sharex=True)
        if n_axes == 1:
            axes = [axes]

        self.fig.suptitle(
            f"Monitoraggio IREN 2025 | {t_start:%d/%m/%Y %H:%M} – {t_end:%d/%m/%Y %H:%M}",
            fontsize=11, fontweight="bold", y=0.98
        )

        for ax, group in zip(axes, groups):
            for label, col in group:
                color = VAR_COLORS.get(col, None)
                ax.plot(
                    subset["datetime"], subset[col],
                    label=label, color=color,
                    linewidth=0.8, alpha=0.85
                )
            ax.legend(loc="upper right", fontsize=8, framealpha=0.7)
            ax.grid(True, linestyle="--", alpha=0.4)
            ax.set_ylabel(self._ylabel_for_group(group), fontsize=9)
            ax.tick_params(axis="both", labelsize=8)

        # Formattazione asse X
        self._format_xaxis(axes[-1], t_start, t_end)

        self.fig.tight_layout()
        self.canvas.draw()

    # ──────────────────────────────────────────────────────────
    # HELPER PLOT
    # ──────────────────────────────────────────────────────────

    @staticmethod
    def _group_variables(selected: list[tuple[str, str]]) -> list[list[tuple[str, str]]]:
        """
        Raggruppa le variabili per scale simili in modo da creare
        assi separati sensati:
          - MOX (cmos1-4): valori molto grandi → un asse
          - ECS (nh3, h2s): valori piccoli [0-1] → un asse
          - T + RH → un asse condiviso (scale simili ~0-100)
        Le variabili non raggruppabili vanno ognuna nel proprio asse.
        """
        group_defs = [
            {"cmos1", "cmos2", "cmos3", "cmos4"},
            {"nh3", "h2s"},
            {"temperature", "humidity"},
        ]
        groups: list[list] = []
        remaining = list(selected)

        for gdef in group_defs:
            members = [(l, c) for l, c in remaining if c in gdef]
            if members:
                groups.append(members)
                for m in members:
                    remaining.remove(m)

        # Variabili rimanenti: un asse ciascuna
        for item in remaining:
            groups.append([item])

        return groups

    @staticmethod
    def _ylabel_for_group(group: list[tuple[str, str]]) -> str:
        cols = {c for _, c in group}
        if cols <= {"cmos1", "cmos2", "cmos3", "cmos4"}:
            return "MOX (a.u.)"
        if cols <= {"nh3", "h2s"}:
            return "ECS (ppm)"
        if cols <= {"temperature", "humidity"}:
            return "T (°C) / RH (%)"
        return ", ".join(c for _, c in group)

    @staticmethod
    def _format_xaxis(ax, t_start: pd.Timestamp, t_end: pd.Timestamp):
        """Sceglie la granularità dell'asse X in base al range temporale."""
        delta = t_end - t_start
        if delta <= pd.Timedelta(hours=6):
            ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M"))
            ax.xaxis.set_major_locator(mdates.MinuteLocator(interval=30))
        elif delta <= pd.Timedelta(days=1):
            ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M"))
            ax.xaxis.set_major_locator(mdates.HourLocator(interval=2))
        elif delta <= pd.Timedelta(days=14):
            ax.xaxis.set_major_formatter(mdates.DateFormatter("%d/%m %H:%M"))
            ax.xaxis.set_major_locator(mdates.HourLocator(interval=12))
        elif delta <= pd.Timedelta(days=60):
            ax.xaxis.set_major_formatter(mdates.DateFormatter("%d/%m"))
            ax.xaxis.set_major_locator(mdates.DayLocator(interval=3))
        else:
            ax.xaxis.set_major_formatter(mdates.DateFormatter("%d/%m/%y"))
            ax.xaxis.set_major_locator(mdates.MonthLocator())
        plt.setp(ax.xaxis.get_majorticklabels(), rotation=30, ha="right")


# ─────────────────────────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("=" * 60)
    print(" IREN Monitoraggio 2025 — Explorer")
    print("=" * 60)

    # Risolvi percorso dati rispetto alla posizione dello script
    script_dir = os.path.dirname(os.path.abspath(__file__))
    data_path = os.path.normpath(os.path.join(script_dir, "../../data/raw/monitoraggio2025"))

    print(f"Cartella dati: {data_path}\n")

    try:
        df = load_all_files(data_path)
    except (FileNotFoundError, ValueError) as e:
        print(f"\n[ERRORE] {e}")
        raise SystemExit(1)

    app = MonitoraggioExplorer(df)
    app.mainloop()
