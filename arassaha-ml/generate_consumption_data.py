"""
Modül 11 (Kayıp-Kaçak / Anormal Tüketim Tespiti) — sentetik aylık tüketim
verisi üretici.

DÜRÜSTLÜK NOTU (bkz. README.md): ArasSaha'nın elinde gerçek bir AMI/akıllı
sayaç okuma sistemi (sayaçların otomatik, uzaktan, aylık tüketim verisi
gönderdiği bir altyapı) YOK. Bu script, gerçek sayaç okumaları yerine kural
tabanlı, elektrik mühendisliği açısından makul (mevsimsel dalgalanma,
kaçak/arıza örüntüleri) SENTETİK bir 12 aylık tüketim geçmişi üretir. Amaç,
gerçek veri toplanana kadar makine öğrenmesi ardışık düzeninin (veri ->
özellik çıkarımı -> IsolationForest eğitimi -> servis -> Node/Flutter
entegrasyonu) uçtan uca ÇALIŞTIĞINI göstermektir. Gerçek üretim ortamında bu
script tamamen devre dışı bırakılır; yerine ArasSaha'nın gerçek AMI/sayaç
okuma sisteminden gelen tüketim geçmişi kullanılır — model mimarisi, özellik
seti ve servis kodu değişmeden kalır.

Bu script AYRICA arassaha-backend/aras_saha.db dosyasına (Node.js'in
kullandığı SQLite dosyasının AYNISI — node:sqlite de standart SQLite dosya
formatını kullandığı için Python'un yerleşik sqlite3 modülüyle doğrudan
okunup/yazılabilir) equipment_type='sayac' olan ekipmanları okur ve ürettiği
ham veriyi meter_consumption tablosuna yazar. Bu, Modül 9/10'daki
generate_*.py scriptlerinden FARKLI bir adımdır (onlar yalnızca CSV üretir) —
çünkü Modül 11'de backend'in GERÇEKTEN okuyacağı ham zaman serisi verisi
(meter_consumption) ile model eğitimi için türetilmiş özellik verisi
(consumption_training_data.csv) ayrı ayrı gerekiyor (bkz. PROMPT).
"""
import sqlite3
from datetime import datetime, timedelta
from pathlib import Path

import numpy as np
import pandas as pd

from consumption_feature_utils import compute_features

BACKEND_DB_PATH = Path(__file__).parent.parent / "arassaha-backend" / "aras_saha.db"
OUTPUT_CSV_PATH = Path(__file__).parent / "consumption_training_data.csv"

RANDOM_SEED = 42
N_MONTHS = 12

# Sentetik veride BİLEREK işaretlenen anomali oranı — train_anomaly_model.py'deki
# IsolationForest'ın contamination parametresiyle TUTARLI olmalı (bkz. o script).
ANOMALY_RATE = 0.15

# Kış aylarında (ısıtma) ve yaz aylarında (klima) tüketimin bir miktar artması,
# EDAŞ bölgesindeki (Erzurum/Ağrı/Kars/Iğdır/Ardahan/Erzincan/Bayburt) sert
# kış iklimi göz önüne alındığında makul bir varsayımdır — gerçek istatistiğe
# değil, alan uzmanlığına dayanır (bkz. arassaha-ml/generate_training_data.py
# TYPE_BASE_RISK ile aynı dürüstlük ilkesi).
SEASONAL_FACTOR = {
    1: 1.22, 2: 1.18, 3: 1.05, 4: 0.95, 5: 0.88, 6: 0.95,
    7: 1.05, 8: 1.05, 9: 0.92, 10: 0.95, 11: 1.10, 12: 1.20,
}


def last_n_months(n=N_MONTHS):
    """Bugünden geriye, kronolojik sırada (en eskiden en yeniye) 'YYYY-MM' etiketleri."""
    today = datetime.now()
    months = []
    year, month = today.year, today.month
    for _ in range(n):
        months.append((year, month))
        month -= 1
        if month == 0:
            month = 12
            year -= 1
    months.reverse()
    return [f"{y:04d}-{m:02d}" for y, m in months]


def generate_normal_series(rng, baseline):
    """Normal sayaç: mevsimsel dalgalanma + düşük varyanslı rastgele gürültü."""
    values = []
    for year_month in last_n_months():
        month = int(year_month.split("-")[1])
        seasonal = baseline * SEASONAL_FACTOR[month]
        noise = rng.normal(loc=0, scale=baseline * 0.06)
        values.append(max(0.0, seasonal + noise))
    return values


def generate_sudden_drop_series(rng, baseline):
    """Ani düşüş: ilk 9 ay normal, son 3 ayda tüketim %60-80 düşer (kaçak şüphesi)."""
    values = generate_normal_series(rng, baseline)
    drop_factor = rng.uniform(0.2, 0.4)  # kalan oran — yani %60-80 düşüş
    for i in range(N_MONTHS - 3, N_MONTHS):
        values[i] = values[i] * drop_factor
    return values


def generate_near_zero_series(rng):
    """Sıfıra yakın tüketim: sayaç aktif kayıtlıyken 12 ay boyunca ~0 (arızalı/bypass şüphesi)."""
    return [max(0.0, rng.uniform(0, 3)) for _ in range(N_MONTHS)]


def generate_irregular_series(rng, baseline):
    """Düzensiz dalgalanma: ay-ay mantıksız sıçramalar (ölçüm hatası/kurcalama şüphesi)."""
    # Baseline'dan bağımsız, geniş bir aralıkta kaotik değerler — normal bir
    # sayacın ay-ay bu kadar oynaması fiziksel olarak beklenmez.
    low = max(10.0, baseline * 0.15)
    high = baseline * 2.5
    return [rng.uniform(low, high) for _ in range(N_MONTHS)]


def main():
    if not BACKEND_DB_PATH.exists():
        raise SystemExit(
            f"Backend veritabanı bulunamadı: {BACKEND_DB_PATH}\n"
            "Önce 'node seed.js' (arassaha-backend içinde) çalıştırılmalı."
        )

    rng = np.random.default_rng(RANDOM_SEED)

    conn = sqlite3.connect(BACKEND_DB_PATH)
    conn.row_factory = sqlite3.Row

    # meter_consumption tablosu normalde Node (database.js) tarafından
    # oluşturulur; bu script'in backend hiç çalıştırılmadan da (yalnızca
    # seed.js sonrası) bağımsız çalışabilmesi için savunmacı bir CREATE TABLE
    # IF NOT EXISTS eklendi — şema database.js ile birebir aynı olmalı.
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS meter_consumption (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            equipment_id INTEGER NOT NULL,
            year_month TEXT NOT NULL,
            consumption_kwh REAL NOT NULL,
            FOREIGN KEY (equipment_id) REFERENCES equipment (id)
        )
        """
    )

    meters = conn.execute(
        "SELECT id, status FROM equipment WHERE equipment_type = 'sayac' ORDER BY id"
    ).fetchall()

    if len(meters) < 15:
        print(
            f"UYARI: yalnızca {len(meters)} sayaç ekipmanı bulundu (önerilen: 15-20). "
            "Anlamlı bir eğitim seti için arassaha-backend/seed.js içindeki sayaç "
            "kayıtlarının artırılması önerilir."
        )

    month_labels = last_n_months()

    # Bu script tekrar çalıştırılabilir olsun diye önce mevcut sayaç verisini temizler.
    meter_ids = [m["id"] for m in meters]
    if meter_ids:
        placeholders = ",".join("?" * len(meter_ids))
        conn.execute(f"DELETE FROM meter_consumption WHERE equipment_id IN ({placeholders})", meter_ids)

    active_meter_ids = [m["id"] for m in meters if m["status"] == "aktif"]
    n_anomalies = round(len(meters) * ANOMALY_RATE)
    # Sıfıra yakın tüketim tipi yalnızca AKTİF kayıtlı sayaçlar için anlamlıdır
    # (bkz. PROMPT) — anomali tipi ataması bu kısıtı göz önünde bulundurur.
    anomaly_ids = set(rng.choice([m["id"] for m in meters], size=min(n_anomalies, len(meters)), replace=False))

    rows_for_insert = []
    training_rows = []

    for meter in meters:
        equipment_id = meter["id"]
        baseline = float(rng.uniform(120, 400))  # sayacın kendi tipik aylık tüketim düzeyi (kWh)

        if equipment_id in anomaly_ids:
            candidates = ["ani_dusus", "duzensiz"]
            if equipment_id in active_meter_ids:
                candidates.append("sifira_yakin")
            anomaly_type = rng.choice(candidates)

            if anomaly_type == "ani_dusus":
                values = generate_sudden_drop_series(rng, baseline)
            elif anomaly_type == "sifira_yakin":
                values = generate_near_zero_series(rng)
            else:
                values = generate_irregular_series(rng, baseline)
            is_anomaly_true = True
        else:
            values = generate_normal_series(rng, baseline)
            anomaly_type = "normal"
            is_anomaly_true = False

        for year_month, value in zip(month_labels, values):
            rows_for_insert.append((equipment_id, year_month, round(float(value), 2)))

        features = compute_features(values)
        training_rows.append(
            {
                "equipment_id": equipment_id,
                **features,
                "is_anomaly_true": is_anomaly_true,
                "anomaly_type": anomaly_type,
            }
        )

    conn.executemany(
        "INSERT INTO meter_consumption (equipment_id, year_month, consumption_kwh) VALUES (?, ?, ?)",
        rows_for_insert,
    )
    conn.commit()
    conn.close()

    df = pd.DataFrame(training_rows)
    df.to_csv(OUTPUT_CSV_PATH, index=False)

    print(f"{len(meters)} sayaç için {len(rows_for_insert)} aylık tüketim kaydı 'meter_consumption' tablosuna yazıldı.")
    print(f"Özellik verisi '{OUTPUT_CSV_PATH.name}' olarak kaydedildi.")
    print(f"\nBilerek işaretlenen anomali sayısı: {df['is_anomaly_true'].sum()} / {len(df)}")
    print("Anomali tipine göre dağılım:")
    print(df["anomaly_type"].value_counts())


if __name__ == "__main__":
    main()
