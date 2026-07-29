"""
Modül 9 (Arıza Risk Tahmini) — model eğitimi.

DÜRÜSTLÜK NOTU: 'training_data.csv' SENTETİK/kural-tabanlı üretilmiş bir veri
setidir (bkz. generate_training_data.py, README.md). Burada eğitilen
RandomForestClassifier gerçek bir eğitim sürecinden geçer — gerçek
train/test ayrımı, gerçek metrikler, gerçek feature importance. Sahte olan
yalnızca VERİ; model eğitim süreci, servis ve entegrasyon gerçektir. Gerçek
üretim ortamında bu script, ArasSaha'nın SQLite/veri ambarında biriken gerçek
work_orders + equipment geçmişiyle yeniden çalıştırılır.
"""
import json
import os
from datetime import datetime, timezone

import joblib
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, f1_score, precision_score, recall_score
from sklearn.model_selection import train_test_split

from feature_utils import FEATURE_COLUMNS, encode_record

DATA_PATH = "training_data.csv"
MODEL_PATH = "models/risk_model.pkl"
METADATA_PATH = "models/model_metadata.json"


def main():
    df = pd.read_csv(DATA_PATH)

    records = df.drop(columns=["will_fail"]).to_dict(orient="records")
    X = pd.DataFrame([encode_record(r) for r in records], columns=FEATURE_COLUMNS)
    y = df["will_fail"]

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    # class_weight='balanced': will_fail=1 veri setinde azınlıkta (~%25) olduğu
    # için dengesiz ağırlık kullanılmazsa model çoğunluk sınıfına (0) aşırı
    # yaslanıp neredeyse hiç pozitif tahmin üretmiyordu (recall ~%1). Bu
    # ağırlıklandırma, azınlık sınıfındaki hataları daha 'pahalı' sayarak
    # modelin gerçek arıza sinyaline duyarlılığını artırır.
    model = RandomForestClassifier(
        n_estimators=200, max_depth=8, class_weight="balanced", random_state=42
    )
    model.fit(X_train, y_train)

    y_pred = model.predict(X_test)
    accuracy = accuracy_score(y_test, y_pred)
    precision = precision_score(y_test, y_pred, zero_division=0)
    recall = recall_score(y_test, y_pred, zero_division=0)
    f1 = f1_score(y_test, y_pred, zero_division=0)

    print("=== Test Seti Metrikleri ===")
    print(f"Eğitim satırı: {len(X_train)}  |  Test satırı: {len(X_test)}")
    print(f"Accuracy:  {accuracy:.3f}")
    print(f"Precision: {precision:.3f}")
    print(f"Recall:    {recall:.3f}")
    print(f"F1:        {f1:.3f}")

    importances = dict(zip(FEATURE_COLUMNS, model.feature_importances_))
    print("\n=== Özellik Önem Sıralaması (feature_importances_) ===")
    for name, importance in sorted(importances.items(), key=lambda x: -x[1]):
        print(f"{name}: {importance:.3f}")

    os.makedirs("models", exist_ok=True)
    joblib.dump(model, MODEL_PATH)

    metadata = {
        "trained_at": datetime.now(timezone.utc).isoformat(),
        "model_type": "RandomForestClassifier",
        "feature_columns": FEATURE_COLUMNS,
        "training_samples": len(df),
        "train_samples": len(X_train),
        "test_samples": len(X_test),
        "test_accuracy": round(float(accuracy), 4),
        "test_precision": round(float(precision), 4),
        "test_recall": round(float(recall), 4),
        "test_f1": round(float(f1), 4),
        "feature_importances": {k: round(float(v), 4) for k, v in importances.items()},
        "data_source": (
            "SENTETİK — generate_training_data.py ile kural tabanlı üretilmiştir. "
            "Gerçek üretim ortamında ArasSaha'nın gerçek arıza/bakım geçmişiyle "
            "yeniden eğitilmelidir (bkz. README.md)."
        ),
    }
    with open(METADATA_PATH, "w", encoding="utf-8") as f:
        json.dump(metadata, f, ensure_ascii=False, indent=2)

    print(f"\nModel kaydedildi: {MODEL_PATH}")
    print(f"Metadata kaydedildi: {METADATA_PATH}")


if __name__ == "__main__":
    main()
