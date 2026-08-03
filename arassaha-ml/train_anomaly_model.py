"""
Modül 11 (Kayıp-Kaçak / Anormal Tüketim Tespiti) — model eğitimi.

DÜRÜSTLÜK NOTU: 'consumption_training_data.csv' SENTETİK bir veri setidir
(bkz. generate_consumption_data.py, README.md). Burada eğitilen
IsolationForest gerçek bir eğitim sürecinden geçer — gerçek fit, gerçek
decision_function dağılımı. Sahte olan yalnızca VERİ; model eğitim süreci,
servis ve entegrasyon gerçektir. Gerçek üretim ortamında bu script,
ArasSaha'nın gerçek AMI/sayaç okuma sisteminden türetilmiş bir tüketim
geçmişiyle yeniden çalıştırılır.

IsolationForest DENETİMSİZ (unsupervised) bir algoritmadır — normalde "doğru
cevap" (hangi sayaç gerçekten şüpheli) olmadan çalışır. Burada SADECE
doğrulama amacıyla, sentetik veriyi ÜRETİRKEN bilerek işaretlediğimiz
anomalileri (`is_anomaly_true`) modelin bulduklarıyla karşılaştırıyoruz —
bu karşılaştırma modelin eğitimine değil, yalnızca "üretim ardışık düzeni
gerçekten çalışıyor mu" sorusuna kabaca bir yanıt vermeye yarar.
"""
import json
import os
from datetime import datetime, timezone

import joblib
import pandas as pd
from sklearn.ensemble import IsolationForest

from consumption_feature_utils import FEATURE_COLUMNS

DATA_PATH = "consumption_training_data.csv"
MODEL_PATH = "models/anomaly_model.pkl"
METADATA_PATH = "models/anomaly_model_metadata.json"

# generate_consumption_data.py'deki ANOMALY_RATE ile TUTARLI olmalı — model,
# eğitim verisinin yaklaşık bu oranının anomali olduğunu varsayarak kendi
# karar sınırını (decision boundary) buna göre kalibre eder.
CONTAMINATION = 0.15


def main():
    df = pd.read_csv(DATA_PATH)
    X = df[FEATURE_COLUMNS]

    model = IsolationForest(
        n_estimators=200, contamination=CONTAMINATION, random_state=42
    )
    model.fit(X)

    # decision_function: pozitif = normal (inlier), negatif = anormal (outlier).
    # predict: -1 = anomali, 1 = normal — modelin KENDİ contamination'a göre
    # kalibre ettiği karar sınırı (bkz. app.py'deki is_suspicious).
    decision_scores = model.decision_function(X)
    predictions = model.predict(X)

    score_min = float(decision_scores.min())
    score_max = float(decision_scores.max())

    predicted_suspicious = predictions == -1
    true_suspicious = df["is_anomaly_true"].astype(bool)

    true_positive = int((predicted_suspicious & true_suspicious).sum())
    false_positive = int((predicted_suspicious & ~true_suspicious).sum())
    false_negative = int((~predicted_suspicious & true_suspicious).sum())

    precision = true_positive / (true_positive + false_positive) if (true_positive + false_positive) > 0 else 0.0
    recall = true_positive / (true_positive + false_negative) if (true_positive + false_negative) > 0 else 0.0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0.0

    print("=== Doğrulama Özeti (yalnızca sentetik veri işaretlemesine karşı) ===")
    print(f"Toplam sayaç: {len(df)}  |  Bilerek işaretlenmiş anomali: {int(true_suspicious.sum())}")
    print(f"Model tarafından şüpheli işaretlenen: {int(predicted_suspicious.sum())}")
    print(f"Doğru yakalanan (TP): {true_positive}")
    print(f"Yanlış alarm (FP):    {false_positive}")
    print(f"Kaçırılan (FN):       {false_negative}")
    print(f"Precision: {precision:.3f}  |  Recall: {recall:.3f}  |  F1: {f1:.3f}")

    os.makedirs("models", exist_ok=True)
    joblib.dump(model, MODEL_PATH)

    metadata = {
        "trained_at": datetime.now(timezone.utc).isoformat(),
        "model_type": "IsolationForest",
        "feature_columns": FEATURE_COLUMNS,
        "contamination": CONTAMINATION,
        "training_samples": len(df),
        "decision_score_min": score_min,
        "decision_score_max": score_max,
        "validation_true_positive": true_positive,
        "validation_false_positive": false_positive,
        "validation_false_negative": false_negative,
        "validation_precision": round(precision, 4),
        "validation_recall": round(recall, 4),
        "validation_f1": round(f1, 4),
        "data_source": (
            "SENTETİK — generate_consumption_data.py ile kural tabanlı üretilmiştir. "
            "Gerçek üretim ortamında ArasSaha'nın gerçek AMI/sayaç okuma "
            "geçmişiyle yeniden eğitilmelidir (bkz. README.md)."
        ),
    }
    with open(METADATA_PATH, "w", encoding="utf-8") as f:
        json.dump(metadata, f, ensure_ascii=False, indent=2)

    print(f"\nModel kaydedildi: {MODEL_PATH}")
    print(f"Metadata kaydedildi: {METADATA_PATH}")


if __name__ == "__main__":
    main()
