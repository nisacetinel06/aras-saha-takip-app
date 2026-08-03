"""Kayıp-Kaçak / Anormal Tüketim Tespiti (Modül 11) — özellik (feature)
sözleşmesi.

feature_utils.py'nin (Modül 9) oynadığı rolün AYNISI: veri üretimi
(generate_consumption_data.py), model eğitimi (train_anomaly_model.py) ve
tahmin servisi (app.py) arasında sütun SIRASI birebir aynı olmak zorunda —
IsolationForest de RandomForestClassifier gibi girdi vektörünü sütun adına
değil sırasına göre yorumlar. Bu yüzden ham 12 aylık tüketim dizisinden
7 özelliği hesaplayan `compute_features` fonksiyonu tek bir yerde tanımlanır.

Node.js tarafı (routes/anomaly.js) bu modülü İÇE AKTARAMAZ (ayrı bir dil/
process) — bu yüzden AYNI 7 formülü kendi JS koduyla bağımsız olarak yeniden
uygular (bkz. routes/anomaly.js buildFeatures). Bu, Modül 9'daki risk.js'nin
buildFeatures'ı feature_utils.py'den bağımsız olarak JS'te yeniden
uygulamasıyla AYNI, önceden kabul edilmiş desendir.
"""
import numpy as np

FEATURE_COLUMNS = [
    "mean_consumption",
    "std_consumption",
    "last_3_month_avg",
    "first_9_month_avg",
    "drop_ratio",
    "max_month_to_month_change",
    "zero_months_count",
]

# Bir ayın "sıfıra yakın" sayılması için üst sınır (kWh). Sentetik veri
# ölçeğine göre (normal sayaçların aylık ortalaması ~120-400 kWh) seçildi;
# gerçek üretimde sayaç tipine göre kalibre edilmiş bir eşik kullanılmalıdır.
ZERO_CONSUMPTION_THRESHOLD_KWH = 5.0


def compute_features(monthly_values: list) -> dict:
    """Kronolojik sıradaki (en eskiden en yeniye) 12 aylık ham tüketim
    listesinden FEATURE_COLUMNS sırasına uygun özellik sözlüğü üretir."""
    values = np.array(monthly_values, dtype=float)
    n = len(values)

    mean_consumption = float(values.mean())
    std_consumption = float(values.std())  # ddof=0 (popülasyon) — Node tarafıyla birebir aynı
    last_3_month_avg = float(values[-3:].mean())
    first_9_month_avg = float(values[: n - 3].mean())

    drop_ratio = (
        0.0
        if first_9_month_avg == 0
        else (first_9_month_avg - last_3_month_avg) / first_9_month_avg
    )

    max_month_to_month_change = float(np.abs(np.diff(values)).max()) if n > 1 else 0.0
    zero_months_count = int((values < ZERO_CONSUMPTION_THRESHOLD_KWH).sum())

    return {
        "mean_consumption": round(mean_consumption, 2),
        "std_consumption": round(std_consumption, 2),
        "last_3_month_avg": round(last_3_month_avg, 2),
        "first_9_month_avg": round(first_9_month_avg, 2),
        "drop_ratio": round(drop_ratio, 4),
        "max_month_to_month_change": round(max_month_to_month_change, 2),
        "zero_months_count": zero_months_count,
    }


def encode_record(record: dict) -> list:
    """Bir özellik sözlüğü için FEATURE_COLUMNS sırasına uygun sayısal vektör üretir."""
    return [float(record[col]) for col in FEATURE_COLUMNS]
