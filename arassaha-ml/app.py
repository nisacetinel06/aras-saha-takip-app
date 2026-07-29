"""
Modül 9 (Arıza Risk Tahmini) — tahmin servisi (FastAPI).

Bu servis eğitilmiş modeli (models/risk_model.pkl) yükler ve tek bir ekipman
için 0-100 arası bir risk skoru döner. Node.js backend'i bu servise
(varsayılan olarak http://localhost:8000) HTTP ile bağlanır; iki katman
birbirinden tamamen bağımsız çalıştırılabilir.

DÜRÜSTLÜK NOTU: Model, generate_training_data.py ile üretilmiş SENTETİK/
kural-tabanlı bir veri setiyle eğitildi (bkz. train_model.py, README.md).
Modelin kendisi ve tahmin ardışık düzeni gerçektir; eğitim verisi değildir.
"""
from pathlib import Path

import joblib
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from feature_utils import EQUIPMENT_TYPES, encode_record

MODEL_PATH = Path(__file__).parent / "models" / "risk_model.pkl"

app = FastAPI(title="ArasSaha Arıza Risk Tahmini Servisi")

_model = None


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
