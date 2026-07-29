"""Model eğitimi (train_model.py) ile tahmin servisi (app.py) arasında
ortak/paylaşılan özellik (feature) sözleşmesi.

Bu modülün varlık nedeni: one-hot encoding sırası eğitim ve tahmin anında
BİREBİR aynı olmak zorunda. RandomForestClassifier, girdi vektörünü sütun
ADINA göre değil sütun SIRASINA göre yorumlar; eğitimde "trafo" 5. sütundaysa
tahmin anında da 5. sütun olmalı, aksi halde model yanlış özelliğe bakıp
anlamsız bir olasılık üretir. Bu yüzden hem train_model.py hem app.py bu tek
modüldeki `encode_record` fonksiyonunu çağırır; ikisi ayrı ayrı kendi
encoding mantığını yazmaz.
"""

EQUIPMENT_TYPES = ["direk", "kesici", "sayac", "trafo"]

NUMERIC_FEATURES = [
    "equipment_age_years",
    "months_since_maintenance",
    "past_fault_count",
    "avg_load_factor",
]

FEATURE_COLUMNS = NUMERIC_FEATURES + [f"equipment_type_{t}" for t in EQUIPMENT_TYPES]


def encode_record(record: dict) -> list:
    """Tek bir kayıt (dict) için FEATURE_COLUMNS sırasına uygun sayısal vektör üretir."""
    equipment_type = record["equipment_type"]
    if equipment_type not in EQUIPMENT_TYPES:
        raise ValueError(
            f"Bilinmeyen equipment_type: {equipment_type!r}. Geçerli değerler: {EQUIPMENT_TYPES}"
        )

    row = [
        float(record["equipment_age_years"]),
        float(record["months_since_maintenance"]),
        float(record["past_fault_count"]),
        float(record["avg_load_factor"]),
    ]
    row += [1.0 if equipment_type == t else 0.0 for t in EQUIPMENT_TYPES]
    return row
