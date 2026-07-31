"""
Modül 9 (Arıza Risk Tahmini) + Modül 10 (Arıza Açıklaması Otomatik
Sınıflandırma) — ortak FastAPI servisi.

Bu servis iki AYRI eğitilmiş model ailesi barındırır:
- risk_model.pkl (Modül 9): RandomForestClassifier, SAYISAL/tablosal
  ekipman verisinden (yaş, bakım, arıza sayısı vb.) 0-100 risk skoru üretir.
- tfidf_vectorizer.pkl + text_type_model.pkl + text_priority_model.pkl
  (Modül 10): TF-IDF + LogisticRegression, serbest METİN arıza
  açıklamasından arıza tipi ve öncelik önerisi üretir.

İki farklı ML tekniği (sayısal/RandomForest ve metin/TF-IDF+LogisticRegression)
BİLİNÇLİ olarak aynı serviste, tek bir uvicorn process'inde birlikte sunulur —
ayrı bir servis kurulmadı (bkz. README.md). Node.js backend'i bu servise
(varsayılan olarak http://localhost:8000) HTTP ile bağlanır; iki taraf
birbirinden tamamen bağımsız çalıştırılabilir.

DÜRÜSTLÜK NOTU: Her iki model ailesi de SENTETİK/kural-tabanlı üretilmiş veri
setleriyle eğitildi (bkz. train_model.py + generate_training_data.py, ve
train_text_model.py + generate_text_training_data.py, README.md). Modellerin
kendisi ve tahmin ardışık düzeni gerçektir; eğitim verisi değildir.
"""
from pathlib import Path

import joblib
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from feature_utils import EQUIPMENT_TYPES, encode_record

MODEL_PATH = Path(__file__).parent / "models" / "risk_model.pkl"

# Modül 10 — bkz. generate_text_training_data.py / train_text_model.py.
TEXT_VECTORIZER_PATH = Path(__file__).parent / "models" / "tfidf_vectorizer.pkl"
TEXT_TYPE_MODEL_PATH = Path(__file__).parent / "models" / "text_type_model.pkl"
TEXT_PRIORITY_MODEL_PATH = Path(__file__).parent / "models" / "text_priority_model.pkl"

# Çok kısa metinler (örn. "sayaç garip") anlamlı bir sınıflandırma için
# yetersiz bağlam taşır; MIN_CONFIDENCE altındaki tahminler de güvenilir
# sayılmaz. İkisinde de öneri GÖSTERİLMEZ (null dönülür) — yanlış bir öneriyle
# kullanıcıyı yanıltmak, hiç öneri sunmamaktan daha kötüdür.
MIN_WORD_COUNT = 3
MIN_CONFIDENCE = 0.4

app = FastAPI(title="ArasSaha Arıza Risk Tahmini + Metin Sınıflandırma Servisi")

_model = None
_text_vectorizer = None
_text_type_model = None
_text_priority_model = None


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
    return {"status": "ok", "model_loaded": MODEL_PATH.exists()}


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
