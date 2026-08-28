"""
Modül 9 (Arıza Risk Tahmini) — model eğitimi.

DÜRÜSTLÜK NOTU: 'training_data.csv' SENTETİK/kural-tabanlı üretilmiş bir veri
setidir (bkz. generate_training_data.py, README.md). Burada eğitilen
RandomForestClassifier gerçek bir eğitim sürecinden geçer — gerçek
train/test ayrımı, gerçek metrikler, gerçek feature importance. Sahte olan
yalnızca VERİ; model eğitim süreci, servis ve entegrasyon gerçektir. Gerçek
üretim ortamında bu script, ArasSaha'nın SQLite/veri ambarında biriken gerçek
work_orders + equipment geçmişiyle yeniden çalıştırılır.

TEST-19 GÜNCELLEMESİ — metodoloji sıkılaştırması:
  1) Tek bir train/test bölmesi yerine k-fold (k=5) cross-validation: hem
     TUNING ÖNCESİ varsayılan parametrelerle (kıyas/baseline) hem de
     TUNING SONRASI en iyi parametrelerle raporlanıyor — tek bölmedeki "iyi"
     sonucun şans eseri olmadığının kanıtı.
  2) RandomizedSearchCV ile hiperparametre araması (n_estimators, max_depth,
     min_samples_leaf, min_samples_split) — GridSearchCV yerine Randomized
     tercih edildi çünkü parametre uzayı büyük, arama BÜTÇESİ (n_iter) ile
     süre kontrol edilebiliyor; sonuçlar GridSearchCV'ninkine çok yakın olur.
  3) Özellik önemi analizi + hangi özelliklerin zayıf katkı sağladığına dair
     açık bir değerlendirme notu (metadata'ya da yazılır).
  4) Kalibrasyon kontrolü (calibration_curve) + gerekirse (Brier score /
     ortalama kalibrasyon hatası kötüyse) CalibratedClassifierCV ile düzeltme.

NOT — 6. madde (periyodik yeniden eğitim altyapısı): bkz. dosyanın SONUNDAKİ
`retrain_with_real_outcomes()` fonksiyonu. Bu fonksiyon YAZILDI ama
`__main__` bloğunda ÇAĞRILMIYOR — backend'deki risk_prediction_outcomes
tablosunda yeterli (>=50) gerçek sonuç birikene kadar bilinçli olarak devre
dışı bırakılan, ileriye dönük bir altyapı (bkz. README.md "Gerçek Geri
Bildirim Döngüsü" bölümü).
"""
import json
import os
from datetime import datetime, timezone
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.calibration import CalibratedClassifierCV, calibration_curve
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (
    accuracy_score,
    brier_score_loss,
    f1_score,
    precision_score,
    recall_score,
)
from sklearn.model_selection import (
    RandomizedSearchCV,
    StratifiedKFold,
    cross_val_score,
    train_test_split,
)

from feature_utils import FEATURE_COLUMNS, encode_record

DATA_PATH = "training_data.csv"
MODEL_PATH = "models/risk_model.pkl"
METADATA_PATH = "models/model_metadata.json"

# Kalibrasyon kontrolünde "ortalama mutlak kalibrasyon hatası" bu değeri
# aşarsa (yani model tahmin ettiği olasılıkla gerçek gözlenen oran arasında
# ortalama %8 puandan fazla sapıyorsa) CalibratedClassifierCV devreye girer.
CALIBRATION_ERROR_THRESHOLD = 0.08

# Gerçek geri bildirim döngüsü (bkz. dosya sonu retrain_with_real_outcomes) —
# bu sayının altında yeniden eğitim ANLAMSIZ/gürültülü olur, altyapı hazır
# ama tetiklenmiyor.
MIN_REAL_OUTCOMES_FOR_RETRAIN = 50


def load_dataset(path=DATA_PATH):
    df = pd.read_csv(path)
    records = df.drop(columns=["will_fail"]).to_dict(orient="records")
    X = pd.DataFrame([encode_record(r) for r in records], columns=FEATURE_COLUMNS)
    y = df["will_fail"]
    return X, y


def mean_calibration_error(y_true, y_proba, n_bins=10):
    """calibration_curve'ün döndürdüğü (gerçek oran, tahmin edilen ortalama
    olasılık) çiftleri arasındaki ORTALAMA MUTLAK farktır — 0'a ne kadar
    yakınsa model o kadar 'dürüst': %80 dediği durumların GERÇEKTEN ~%80'i
    pozitif çıkıyor demektir."""
    prob_true, prob_pred = calibration_curve(y_true, y_proba, n_bins=n_bins, strategy="quantile")
    return float(np.mean(np.abs(prob_true - prob_pred))), prob_true, prob_pred


def main():
    X, y = load_dataset()

    # Nihai test seti — hiperparametre aramasına/CV'ye HİÇ karışmaz, yalnızca
    # en sonda "gerçek dünyada nasıl davranır" sorusuna dürüst bir cevap
    # vermek için ayrılır (data leakage'a karşı bkz. check_data_leakage.py
    # ile aynı disiplin).
    X_temp, X_test, y_temp, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)

    # --- 1) BASELINE: varsayılan/eski parametrelerle 5-fold CV (kıyas için) ---
    baseline_model = RandomForestClassifier(
        n_estimators=200, max_depth=8, class_weight="balanced", random_state=42
    )
    baseline_cv_scores = cross_val_score(baseline_model, X_temp, y_temp, cv=cv, scoring="f1")

    print("=== [1/5] Baseline (eski sabit parametreler) — 5-fold CV ===")
    print(f"F1 skorları (5 fold): {np.round(baseline_cv_scores, 3)}")
    print(f"F1 ortalama: {baseline_cv_scores.mean():.3f}  (std: {baseline_cv_scores.std():.3f})")

    # --- 2) Hiperparametre araması (RandomizedSearchCV, 5-fold CV) ---
    param_distributions = {
        "n_estimators": [100, 200, 300, 400, 500],
        "max_depth": [4, 6, 8, 10, 12, None],
        "min_samples_leaf": [1, 2, 4, 8, 16],
        "min_samples_split": [2, 4, 8, 16],
        "max_features": ["sqrt", "log2", None],
    }
    search = RandomizedSearchCV(
        RandomForestClassifier(class_weight="balanced", random_state=42),
        param_distributions=param_distributions,
        n_iter=40,
        cv=cv,
        scoring="f1",
        random_state=42,
        n_jobs=-1,
    )
    search.fit(X_temp, y_temp)
    best_model = search.best_estimator_
    tuned_cv_scores = cross_val_score(best_model, X_temp, y_temp, cv=cv, scoring="f1")

    print("\n=== [2/5] Hiperparametre araması (RandomizedSearchCV, n_iter=40) ===")
    print(f"En iyi parametreler: {search.best_params_}")
    print(f"Tuned F1 skorları (5 fold): {np.round(tuned_cv_scores, 3)}")
    print(f"Tuned F1 ortalama: {tuned_cv_scores.mean():.3f}  (std: {tuned_cv_scores.std():.3f})")
    print(
        f"Baseline'a göre değişim: {tuned_cv_scores.mean() - baseline_cv_scores.mean():+.3f} "
        "(NOT: bu, tek bir 'iyi' bölmeye göre DEĞİL, 5 farklı bölmenin ortalamasına göre "
        "karşılaştırma — dolayısıyla şansa daha az bağlı bir kıyas)"
    )

    # --- 3) Nihai (hiç görülmemiş) test setinde değerlendirme ---
    best_model.fit(X_temp, y_temp)
    y_pred = best_model.predict(X_test)
    y_proba = best_model.predict_proba(X_test)[:, 1]

    accuracy = accuracy_score(y_test, y_pred)
    precision = precision_score(y_test, y_pred, zero_division=0)
    recall = recall_score(y_test, y_pred, zero_division=0)
    f1 = f1_score(y_test, y_pred, zero_division=0)
    brier = brier_score_loss(y_test, y_proba)

    print("\n=== [3/5] Nihai (hiç görülmemiş) test seti metrikleri ===")
    print(f"Eğitim (temp) satırı: {len(X_temp)}  |  Test satırı: {len(X_test)}")
    print(f"Accuracy:  {accuracy:.3f}")
    print(f"Precision: {precision:.3f}")
    print(f"Recall:    {recall:.3f}")
    print(f"F1:        {f1:.3f}")
    print(f"Brier score (düşük=iyi): {brier:.3f}")

    # --- 4) Özellik önemi analizi ---
    importances = dict(zip(FEATURE_COLUMNS, best_model.feature_importances_))
    sorted_importances = sorted(importances.items(), key=lambda x: -x[1])
    print("\n=== [4/5] Özellik Önem Sıralaması (feature_importances_) ===")
    for name, importance in sorted_importances:
        print(f"{name}: {importance:.3f}")

    # WEAK_IMPORTANCE_THRESHOLD: bu eşiğin altındaki özellikler "zayıf katkı"
    # olarak işaretlenir — bilgi amaçlı, OTOMATİK olarak ÇIKARILMAZ (bkz.
    # aşağıdaki not). one-hot encoded equipment_type_* sütunlarından biri tek
    # başına çıkarılamaz (kalan kategoriler yanlış yorumlanır, bkz.
    # feature_utils.py dosya başı notu) — bu yüzden "çıkarma" kararı burada
    # otomatik uygulanmıyor, yalnızca gözlem olarak raporlanıyor.
    WEAK_IMPORTANCE_THRESHOLD = 0.03
    weak_features = [name for name, imp in sorted_importances if imp < WEAK_IMPORTANCE_THRESHOLD]
    if weak_features:
        print(
            f"\nZAYIF KATKI notu: {weak_features} — %{WEAK_IMPORTANCE_THRESHOLD*100:.0f}'in altında "
            "önem taşıyor. Çıkarılmadı (one-hot kategori sütunları tek başına çıkarılamaz, "
            "sayısal özellikler ise generate_training_data.py'deki risk formülünün DOĞRUDAN "
            "bir girdisi olduğu için düşük önem çoğunlukla 'bu tip için nadir' anlamına geliyor, "
            "gürültü değil) — gelecekte gerçek veriyle yeniden değerlendirilmeli."
        )
    else:
        print("\nZAYIF KATKI notu: tüm özellikler eşiğin üzerinde katkı sağlıyor, çıkarılacak aday yok.")

    # --- 5) Kalibrasyon kontrolü ---
    calib_error, prob_true, prob_pred = mean_calibration_error(y_test, y_proba)
    print("\n=== [5/5] Kalibrasyon kontrolü (calibration_curve) ===")
    print(f"Tahmin edilen olasılık (bin ortalaması): {np.round(prob_pred, 3)}")
    print(f"Gerçekleşen oran (bin ortalaması):       {np.round(prob_true, 3)}")
    print(f"Ortalama mutlak kalibrasyon hatası: {calib_error:.3f} (eşik: {CALIBRATION_ERROR_THRESHOLD})")

    final_model = best_model
    calibrated = False
    if calib_error > CALIBRATION_ERROR_THRESHOLD:
        print(
            f"Kalibrasyon hatası eşiği aştı ({calib_error:.3f} > {CALIBRATION_ERROR_THRESHOLD}) — "
            "CalibratedClassifierCV (sigmoid/Platt scaling, cv=5) uygulanıyor..."
        )
        calibrated_model = CalibratedClassifierCV(
            RandomForestClassifier(**search.best_params_, class_weight="balanced", random_state=42),
            method="sigmoid",
            cv=5,
        )
        calibrated_model.fit(X_temp, y_temp)
        calibrated_proba = calibrated_model.predict_proba(X_test)[:, 1]
        calibrated_error, _, _ = mean_calibration_error(y_test, calibrated_proba)
        calibrated_brier = brier_score_loss(y_test, calibrated_proba)

        print(f"Kalibrasyon sonrası hata: {calibrated_error:.3f}  (öncesi: {calib_error:.3f})")
        print(f"Kalibrasyon sonrası Brier: {calibrated_brier:.3f}  (öncesi: {brier:.3f})")

        if calibrated_error < calib_error:
            final_model = calibrated_model
            calibrated = True
            y_pred = final_model.predict(X_test)
            y_proba = calibrated_proba
            accuracy = accuracy_score(y_test, y_pred)
            precision = precision_score(y_test, y_pred, zero_division=0)
            recall = recall_score(y_test, y_pred, zero_division=0)
            f1 = f1_score(y_test, y_pred, zero_division=0)
            brier = calibrated_brier
            calib_error = calibrated_error
            print("CalibratedClassifierCV KULLANILDI (kalibrasyonu iyileştirdi) — nihai model bu.")
        else:
            print(
                "CalibratedClassifierCV kalibrasyonu İYİLEŞTİRMEDİ — ham RandomForestClassifier "
                "nihai model olarak KORUNDU."
            )
    else:
        print("Kalibrasyon hatası eşiğin altında — CalibratedClassifierCV'ye gerek yok.")

    os.makedirs("models", exist_ok=True)
    joblib.dump(final_model, MODEL_PATH)

    metadata = {
        "trained_at": datetime.now(timezone.utc).isoformat(),
        "model_type": "CalibratedClassifierCV(RandomForestClassifier)" if calibrated else "RandomForestClassifier",
        "feature_columns": FEATURE_COLUMNS,
        "training_samples": len(X) ,
        "train_samples": len(X_temp),
        "test_samples": len(X_test),
        "best_hyperparameters": search.best_params_,
        "cross_validation": {
            "folds": 5,
            "baseline_f1_mean": round(float(baseline_cv_scores.mean()), 4),
            "baseline_f1_std": round(float(baseline_cv_scores.std()), 4),
            "tuned_f1_mean": round(float(tuned_cv_scores.mean()), 4),
            "tuned_f1_std": round(float(tuned_cv_scores.std()), 4),
        },
        "test_accuracy": round(float(accuracy), 4),
        "test_precision": round(float(precision), 4),
        "test_recall": round(float(recall), 4),
        "test_f1": round(float(f1), 4),
        "test_brier_score": round(float(brier), 4),
        "calibration": {
            "mean_absolute_calibration_error": round(float(calib_error), 4),
            "threshold": CALIBRATION_ERROR_THRESHOLD,
            "calibrated_classifier_used": calibrated,
        },
        "feature_importances": {k: round(float(v), 4) for k, v in importances.items()},
        "weak_features_below_threshold": weak_features,
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


# --- 6) Periyodik yeniden eğitim altyapısı (YAZILDI, ÇAĞRILMIYOR) ---
#
# GERÇEK GERİ BİLDİRİM DÖNGÜSÜ (bkz. README.md): arassaha-backend'deki
# `risk_prediction_outcomes` tablosu, her risk tahmininin GERÇEKTE arızayla
# sonuçlanıp sonuçlanmadığını (actual_fault_occurred) biriktirir. Bu
# fonksiyon o tabloyu (backend'in aras_saha.db'sinden, salt-okunur) okuyup
# sentetik veriyle karıştırarak yeniden eğitim yapabilir — ama şu an (henüz
# yeterli gerçek sonuç birikmediği için) `__main__` bloğunda ÇAĞRILMIYOR.
# İleride (aylar sonra, MIN_REAL_OUTCOMES_FOR_RETRAIN eşiği aşıldığında) bir
# operatör bunu elle (`python train_model.py --retrain-with-real-outcomes`
# gibi bir CLI bayrağı eklenerek) tetikleyecek.
def load_real_outcomes(db_path="../arassaha-backend/aras_saha.db"):
    """risk_prediction_outcomes + equipment tablolarından, SONUÇLANMIŞ
    (actual_fault_occurred IS NOT NULL) gerçek kayıtları eğitim formatına
    (training_data.csv ile AYNI sütunlar) dönüştürür. equipment tablosundaki
    GÜNCEL özellikler kullanılır — bu bir yaklaşıklamadır (tahmin anındaki
    yaş/bakım durumu değil, OKUMA anındaki durum), gerçek bir prod sistemde
    tahmin anındaki özellik anlık görüntüsü (snapshot) risk_prediction_outcomes
    tablosuna EK sütunlar olarak saklanmalıdır — bu, ileride eklenmesi
    gereken bir iyileştirme notu olarak burada bırakılıyor.
    """
    # NOT: equipment tablosunda yaş/bakım DOĞRUDAN bir sütun olarak
    # tutulmuyor (install_date/last_maintenance_date'ten hesaplanıyor, bkz.
    # arassaha-backend/routes/risk.js calculateAgeYears/
    # calculateMonthsSinceMaintenance) — bu fonksiyon o hesaplamayı Python
    # tarafında TEKRARLAMAK yerine, gerçek kullanımda Node tarafının zaten
    # hesapladığı özellikleri risk_prediction_outcomes tablosuna EK sütun
    # olarak yazmasını (predicted_at anındaki equipment_age_years/
    # months_since_maintenance/past_fault_count/avg_load_factor/
    # equipment_type) önerir — bu fonksiyon o şema genişlemesini VARSAYAR,
    # şu anki tabloda henüz YOK (bkz. arassaha-backend/database.js
    # risk_prediction_outcomes CREATE TABLE). Bu yüzden burada gerçek bir
    # SQL sorgusu bile YAZILMADI — hangi sütunların gerekeceği yukarıda
    # BELİRTİLDİ, ama tablo o sütunları henüz taşımadığı için sorgu şu an
    # anlamsız olurdu.
    if not Path(db_path).exists():
        raise NotImplementedError(
            f"load_real_outcomes: '{db_path}' bulunamadı (backend'in aras_saha.db'si)."
        )
    raise NotImplementedError(
        "load_real_outcomes: risk_prediction_outcomes tablosu henüz tahmin anındaki "
        "özellik anlık görüntüsünü saklamıyor (yalnızca predicted_risk_score var, ham "
        "özellikler yok). Bu, MIN_REAL_OUTCOMES_FOR_RETRAIN eşiği yaklaşıldığında "
        "database.js'e eklenmesi gereken bir şema genişlemesi notu."
    )


def retrain_with_real_outcomes(real_outcome_weight=3.0, min_real_outcomes=MIN_REAL_OUTCOMES_FOR_RETRAIN):
    """Sentetik veriyi GERÇEK sonuçlarla karıştırıp yeniden eğitir.

    real_outcome_weight: gerçek kayıtların sentetik kayıtlara göre örnek
    ağırlığı (sample_weight) — gerçek veri az ama DEĞERLİ olduğu için
    (sentetik olmayan tek sinyal kaynağı) RandomForestClassifier.fit'e
    sample_weight ile daha yüksek ağırlık verilir, aksi halde 1800 sentetik
    kayıt arasında birkaç düzine gerçek kayıt istatistiksel olarak
    kaybolur.
    """
    try:
        real_df = load_real_outcomes()
    except NotImplementedError as exc:
        print(f"[retrain_with_real_outcomes] Atlandı: {exc}")
        return None

    if len(real_df) < min_real_outcomes:
        print(
            f"[retrain_with_real_outcomes] Yalnızca {len(real_df)} gerçek sonuç var "
            f"(eşik: {min_real_outcomes}) — yeniden eğitim ATLANDI, sentetik model korunuyor."
        )
        return None

    synthetic_df = pd.read_csv(DATA_PATH)
    combined_df = pd.concat([synthetic_df, real_df], ignore_index=True)
    sample_weight = np.concatenate(
        [np.ones(len(synthetic_df)), np.full(len(real_df), real_outcome_weight)]
    )

    records = combined_df.drop(columns=["will_fail"]).to_dict(orient="records")
    X = pd.DataFrame([encode_record(r) for r in records], columns=FEATURE_COLUMNS)
    y = combined_df["will_fail"]

    model = RandomForestClassifier(n_estimators=300, max_depth=8, class_weight="balanced", random_state=42)
    model.fit(X, y, sample_weight=sample_weight)

    print(
        f"[retrain_with_real_outcomes] {len(real_df)} gerçek + {len(synthetic_df)} sentetik "
        f"kayıtla yeniden eğitildi (gerçek kayıt ağırlığı: {real_outcome_weight}x)."
    )
    return model


if __name__ == "__main__":
    main()
