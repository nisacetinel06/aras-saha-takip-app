"""
Modül 9 (Arıza Risk Tahmini) + Modül 10 (Arıza Açıklaması Otomatik
Sınıflandırma) + Modül 11 (Kayıp-Kaçak / Anormal Tüketim Tespiti) — ortak
FastAPI servisi.

Bu servis ÜÇ AYRI eğitilmiş model ailesi barındırır:
- risk_model.pkl (Modül 9): RandomForestClassifier, SAYISAL/tablosal
  ekipman verisinden (yaş, bakım, arıza sayısı vb.) 0-100 risk skoru üretir.
- tfidf_vectorizer.pkl + text_type_model.pkl + text_priority_model.pkl
  (Modül 10): TF-IDF + LogisticRegression, serbest METİN arıza
  açıklamasından arıza tipi ve öncelik önerisi üretir.
- anomaly_model.pkl (Modül 11): IsolationForest, sayaçların 12 aylık tüketim
  geçmişinden türetilmiş özelliklerden (ortalama, düşüş oranı, düzensizlik
  vb.) kaçak/arızalı ölçüm şüphesi taşıyan sayaçları tespit eder.

Üç farklı ML tekniği (sayısal/RandomForest, metin/TF-IDF+LogisticRegression,
anomali/IsolationForest) BİLİNÇLİ olarak aynı serviste, tek bir uvicorn
process'inde birlikte sunulur — ayrı bir servis kurulmadı (bkz. README.md).
Node.js backend'i bu servise (varsayılan olarak http://localhost:8000) HTTP
ile bağlanır; iki taraf birbirinden tamamen bağımsız çalıştırılabilir.

DÜRÜSTLÜK NOTU: Üç model ailesi de SENTETİK/kural-tabanlı üretilmiş veri
setleriyle eğitildi (bkz. train_model.py + generate_training_data.py,
train_text_model.py + generate_text_training_data.py, train_anomaly_model.py
+ generate_consumption_data.py, README.md). Modellerin kendisi ve tahmin
ardışık düzeni gerçektir; eğitim verisi değildir.
"""
import json
from pathlib import Path

import joblib
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from consumption_feature_utils import FEATURE_COLUMNS as ANOMALY_FEATURE_COLUMNS
from consumption_feature_utils import encode_record as encode_anomaly_record
from feature_utils import EQUIPMENT_TYPES, encode_record

MODEL_PATH = Path(__file__).parent / "models" / "risk_model.pkl"

# Modül 10 — bkz. generate_text_training_data.py / train_text_model.py.
TEXT_VECTORIZER_PATH = Path(__file__).parent / "models" / "tfidf_vectorizer.pkl"
TEXT_TYPE_MODEL_PATH = Path(__file__).parent / "models" / "text_type_model.pkl"
TEXT_PRIORITY_MODEL_PATH = Path(__file__).parent / "models" / "text_priority_model.pkl"

# Modül 11 — bkz. generate_consumption_data.py / train_anomaly_model.py.
ANOMALY_MODEL_PATH = Path(__file__).parent / "models" / "anomaly_model.pkl"
ANOMALY_METADATA_PATH = Path(__file__).parent / "models" / "anomaly_model_metadata.json"

# Ay-ay tüketim değişiminin bu değeri AŞMASI "düzensiz/tutarsız tüketim
# örüntüsü" kural açıklamasını tetikler. Sentetik veri ölçeğine göre (normal
# sayaçların aylık ortalaması ~120-400 kWh) seçildi; gerçek üretimde bu, sabit
# bir kWh eşiği yerine sayacın kendi ortalamasına göre ORANSAL bir eşiğe
# (örn. ortalamanın %50'si) dönüştürülmelidir.
MAX_MONTH_CHANGE_THRESHOLD = 100.0
DROP_RATIO_THRESHOLD = 0.5
ZERO_MONTHS_THRESHOLD = 3

# Çok kısa metinler (örn. "sayaç garip") anlamlı bir sınıflandırma için
# yetersiz bağlam taşır; MIN_CONFIDENCE altındaki tahminler de güvenilir
# sayılmaz. İkisinde de öneri GÖSTERİLMEZ (null dönülür) — yanlış bir öneriyle
# kullanıcıyı yanıltmak, hiç öneri sunmamaktan daha kötüdür.
MIN_WORD_COUNT = 3
MIN_CONFIDENCE = 0.4

app = FastAPI(title="ArasSaha Arıza Risk Tahmini + Metin Sınıflandırma + Anormal Tüketim Tespiti Servisi")

_model = None
_text_vectorizer = None
_text_type_model = None
_text_priority_model = None
_anomaly_model = None
_anomaly_score_bounds = None


def get_model():
    global _model
    if _model is None:
        if not MODEL_PATH.exists():
            raise HTTPException(
                status_code=503,
                detail=(
                    "Model dosyası bulunamadı. Önce 'python generate_training_data.py' "
                    "ve 'python train_model.py' komutlarını çalıştırın."
                ),
            )
        _model = joblib.load(MODEL_PATH)
    return _model


def get_text_models():
    global _text_vectorizer, _text_type_model, _text_priority_model
    if _text_vectorizer is None:
        for path in (TEXT_VECTORIZER_PATH, TEXT_TYPE_MODEL_PATH, TEXT_PRIORITY_MODEL_PATH):
            if not path.exists():
                raise HTTPException(
                    status_code=503,
                    detail=(
                        "Metin sınıflandırma modeli bulunamadı. Önce "
                        "'python generate_text_training_data.py' ve "
                        "'python train_text_model.py' komutlarını çalıştırın."
                    ),
                )
        _text_vectorizer = joblib.load(TEXT_VECTORIZER_PATH)
        _text_type_model = joblib.load(TEXT_TYPE_MODEL_PATH)
        _text_priority_model = joblib.load(TEXT_PRIORITY_MODEL_PATH)
    return _text_vectorizer, _text_type_model, _text_priority_model


def get_anomaly_model():
    """anomaly_model.pkl'i ve normalize için gereken min/max decision_function
    sınırlarını (train_anomaly_model.py'nin metadata'ya yazdığı) birlikte döner."""
    global _anomaly_model, _anomaly_score_bounds
    if _anomaly_model is None:
        if not ANOMALY_MODEL_PATH.exists() or not ANOMALY_METADATA_PATH.exists():
            raise HTTPException(
                status_code=503,
                detail=(
                    "Anomali tespit modeli bulunamadı. Önce "
                    "'python generate_consumption_data.py' ve "
                    "'python train_anomaly_model.py' komutlarını çalıştırın."
                ),
            )
        _anomaly_model = joblib.load(ANOMALY_MODEL_PATH)
        with open(ANOMALY_METADATA_PATH, "r", encoding="utf-8") as f:
            metadata = json.load(f)
        _anomaly_score_bounds = (metadata["decision_score_min"], metadata["decision_score_max"])
    return _anomaly_model, _anomaly_score_bounds


class EquipmentFeatures(BaseModel):
    equipment_age_years: float = Field(..., ge=0, description="Ekipman yaşı (yıl)")
    months_since_maintenance: float = Field(..., ge=0, description="Son bakımdan bu yana geçen ay")
    past_fault_count: int = Field(..., ge=0, description="Geçmiş arıza sayısı")
    equipment_type: str = Field(..., description=f"Biri: {EQUIPMENT_TYPES}")
    avg_load_factor: float = Field(..., ge=0, description="Ortalama yük faktörü")


class RiskResponse(BaseModel):
    risk_score: int
    risk_level: str


def risk_level_for(score: int) -> str:
    if score <= 33:
        return "dusuk"
    if score <= 66:
        return "orta"
    return "yuksek"


@app.get("/health")
def health():
    """Node.js backend'in servis ayakta mı diye kontrol etmesi için basit bir health check."""
    return {
        "status": "ok",
        "model_loaded": MODEL_PATH.exists(),
        "anomaly_model_loaded": ANOMALY_MODEL_PATH.exists(),
    }


@app.post("/predict", response_model=RiskResponse)
def predict(features: EquipmentFeatures):
    if features.equipment_type not in EQUIPMENT_TYPES:
        raise HTTPException(
            status_code=422,
            detail=f"equipment_type şu değerlerden biri olmalı: {EQUIPMENT_TYPES}",
        )

    model = get_model()
    row = [encode_record(features.model_dump())]
    # predict_proba sütun sırası model.classes_'e göredir (burada [0, 1]);
    # [0][1] = will_fail=1 olma olasılığı.
    probability = model.predict_proba(row)[0][1]
    risk_score = max(0, min(100, round(probability * 100)))

    return RiskResponse(risk_score=risk_score, risk_level=risk_level_for(risk_score))


# --- Modül 10: Arıza Açıklaması Otomatik Sınıflandırma ---


class DescriptionInput(BaseModel):
    description: str = Field(..., min_length=1)


class ClassificationResponse(BaseModel):
    suggested_type: str | None
    type_confidence: float | None
    suggested_priority: str | None
    priority_confidence: float | None


@app.post("/classify-text", response_model=ClassificationResponse)
def classify_text(payload: DescriptionInput):
    text = payload.description.strip()
    word_count = len(text.split())

    if word_count < MIN_WORD_COUNT:
        return ClassificationResponse(
            suggested_type=None, type_confidence=None,
            suggested_priority=None, priority_confidence=None,
        )

    vectorizer, type_model, priority_model = get_text_models()
    vector = vectorizer.transform([text])

    type_proba = type_model.predict_proba(vector)[0]
    type_confidence = float(type_proba.max())
    suggested_type = str(type_model.classes_[type_proba.argmax()])

    priority_proba = priority_model.predict_proba(vector)[0]
    priority_confidence = float(priority_proba.max())
    suggested_priority = str(priority_model.classes_[priority_proba.argmax()])

    # Arıza tipi tahmini düşük güvenle geldiyse TÜM öneri gizlenir (Flutter
    # tarafı yalnızca suggested_type'a bakarak öneri kutusunu gösterip
    # göstermeyeceğine karar verir — bkz. create_work_order_screen.dart).
    # Öncelik tahmini ayrıca kendi güven eşiğine göre bağımsız değerlendirilir;
    # arıza tipi güvenilirken öncelik güvenilir değilse yalnızca öncelik
    # önerisi gizlenir, arıza tipi önerisi yine de gösterilir.
    if type_confidence < MIN_CONFIDENCE:
        return ClassificationResponse(
            suggested_type=None,
            type_confidence=round(type_confidence, 3),
            suggested_priority=None,
            priority_confidence=None,
        )

    return ClassificationResponse(
        suggested_type=suggested_type,
        type_confidence=round(type_confidence, 3),
        suggested_priority=suggested_priority if priority_confidence >= MIN_CONFIDENCE else None,
        priority_confidence=round(priority_confidence, 3) if priority_confidence >= MIN_CONFIDENCE else None,
    )


# --- Modül 11: Kayıp-Kaçak / Anormal Tüketim Tespiti ---


class ConsumptionFeatures(BaseModel):
    mean_consumption: float = Field(..., ge=0)
    std_consumption: float = Field(..., ge=0)
    last_3_month_avg: float = Field(..., ge=0)
    first_9_month_avg: float = Field(..., ge=0)
    drop_ratio: float
    max_month_to_month_change: float = Field(..., ge=0)
    zero_months_count: int = Field(..., ge=0, le=12)


class AnomalyResponse(BaseModel):
    anomaly_score: int
    is_suspicious: bool
    detected_reason: str | None


def detected_reason_for(features: ConsumptionFeatures, is_suspicious: bool) -> str | None:
    """Isolation Forest kara kutudur — "neden şüpheli" sorusuna somut bir yanıt
    vermek için, modelin skorundan BAĞIMSIZ, insan tarafından okunabilir basit
    kurallar burada (tahmin zamanında) değerlendirilir. Birden fazla kural
    tetiklenirse en açıklayıcı/öncelikli olan (sıfıra yakın -> düşüş ->
    düzensizlik sırasıyla) döner. Hiçbir kural tetiklenmezse ama model yine de
    şüpheli işaretlediyse (çok değişkenli bir örüntü nedeniyle), genel bir
    açıklama kullanılır — tamamen sessiz bir "şüpheli" etiketi bırakmamak için.

    ÖNEMLİ: zero_months_count kontrolü BİLİNÇLİ olarak drop_ratio'dan ÖNCE
    gelir. Bir sayaç 12 ayın TAMAMINDA sıfıra yakınsa, iki düşük/gürültülü
    dönem (first_9_month_avg, last_3_month_avg) arasındaki ORANSAL fark
    (drop_ratio) yine de %50'yi rahatça aşabilir — bu durumda "tüketim %X
    azaldı" mesajı yanıltıcı olur (sayaç zaten baştan beri neredeyse hiç
    tüketmiyordu, yeni bir düşüş yok). "Sıfıra yakın tüketim" burada çok daha
    doğru ve somut bir teşhistir.
    """
    if features.zero_months_count >= ZERO_MONTHS_THRESHOLD:
        return f"Son 12 ayda {features.zero_months_count} ay sıfıra yakın tüketim"
    if features.drop_ratio > DROP_RATIO_THRESHOLD:
        return f"Son 3 ayda tüketim %{features.drop_ratio * 100:.0f} azaldı"
    if features.max_month_to_month_change > MAX_MONTH_CHANGE_THRESHOLD:
        return "Düzensiz/tutarsız tüketim örüntüsü tespit edildi"
    if is_suspicious:
        return "Model, tüketim örüntüsünü istatistiksel olarak anormal buldu"
    return None


@app.post("/detect-anomaly", response_model=AnomalyResponse)
def detect_anomaly(features: ConsumptionFeatures):
    model, (score_min, score_max) = get_anomaly_model()
    row = [encode_anomaly_record(features.model_dump())]

    # decision_function: pozitif = normal (inlier), negatif = anormal (outlier).
    # predict: -1 = anomali, 1 = normal — modelin contamination'a göre kalibre
    # ettiği KENDİ karar sınırı; is_suspicious bilinçli olarak bir skor eşiği
    # yerine BU sınıra dayanır (bkz. train_anomaly_model.py).
    decision = float(model.decision_function(row)[0])
    is_suspicious = bool(model.predict(row)[0] == -1)

    # score_max (eğitimdeki en "normal" nokta) -> 0, score_min (eğitimdeki en
    # "anormal" nokta) -> 100 olacak şekilde ters çevrilip ölçeklenir. Eğitim
    # sırasında görülmeyen bir uç değer sınırların dışına taşarsa clip edilir.
    if score_max == score_min:
        anomaly_score = 50
    else:
        raw = (score_max - decision) / (score_max - score_min) * 100
        anomaly_score = max(0, min(100, round(raw)))

    return AnomalyResponse(
        anomaly_score=anomaly_score,
        is_suspicious=is_suspicious,
        detected_reason=detected_reason_for(features, is_suspicious),
    )
