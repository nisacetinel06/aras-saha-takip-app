"""
Modül 10 (Arıza Açıklaması Otomatik Sınıflandırma) — metin sınıflandırma
modellerinin eğitimi.

DÜRÜSTLÜK NOTU: 'text_training_data.csv' SENTETİK/şablon tabanlı üretilmiş
bir veri setidir (bkz. generate_text_training_data.py, README.md). Burada
eğitilen TF-IDF + LogisticRegression modelleri gerçek bir eğitim
sürecinden geçer — gerçek train/test ayrımı, gerçek doğruluk skorları,
gerçek katsayı (coefficient) analizi. Sahte olan yalnızca VERİ; model
eğitim süreci, servis ve entegrasyon gerçektir. Gerçek üretim ortamında bu
script, ArasSaha'nın gerçek arıza açıklama metinleriyle (ve gerçek
etiketleriyle) yeniden çalıştırılır — model mimarisi değişmeden kalır.

Modül 9'dan (RandomForestClassifier, sayısal/tablosal veri — equipment_age_years,
past_fault_count vb.) BİLİNÇLİ olarak FARKLI bir ML tekniği kullanılır: TF-IDF
(serbest metni sayısal bir vektöre çevirme) + LogisticRegression (metin
sınıflandırma için klasik, hızlı ve yorumlanabilir bir yöntem — coef_
üzerinden hangi kelimenin hangi sınıfı işaret ettiği doğrudan okunabilir).
"""
import json
import os
from datetime import datetime, timezone

import joblib
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score
from sklearn.model_selection import train_test_split

DATA_PATH = "text_training_data.csv"
VECTORIZER_PATH = "models/tfidf_vectorizer.pkl"
TYPE_MODEL_PATH = "models/text_type_model.pkl"
PRIORITY_MODEL_PATH = "models/text_priority_model.pkl"
METADATA_PATH = "models/text_model_metadata.json"

# Basit bir Türkçe stop-word listesi (opsiyonel iyileştirme) — TF-IDF'in çok
# sık geçen ama ayırt edici olmayan bağlaç/zamir/sıfatları gürültü olarak
# saymaması için. Kapsamlı bir NLP kütüphanesi (örn. Zemberek) kasıtlı olarak
# kullanılmadı — bu basit liste, staj projesinin kapsamı için yeterli.
TURKISH_STOP_WORDS = [
    "ve", "bir", "bu", "çok", "da", "de", "ile", "için", "gibi", "var",
    "yok", "her", "ama", "ya", "ki", "mi", "mı", "mu", "mü", "en",
]


def main():
    df = pd.read_csv(DATA_PATH, encoding="utf-8")

    (
        X_train_text, X_test_text,
        y_type_train, y_type_test,
        y_priority_train, y_priority_test,
    ) = train_test_split(
        df["text"], df["ariza_tipi"], df["oncelik"],
        test_size=0.2, random_state=42, stratify=df["ariza_tipi"],
    )

    # Aynı TF-IDF vektörleştirici her iki model tarafından da paylaşılır —
    # yalnızca EĞİTİM metinleriyle fit edilir (test verisi sızıntısı olmasın diye).
    vectorizer = TfidfVectorizer(stop_words=TURKISH_STOP_WORDS, lowercase=True)
    X_train = vectorizer.fit_transform(X_train_text)
    X_test = vectorizer.transform(X_test_text)

    type_model = LogisticRegression(max_iter=1000)
    type_model.fit(X_train, y_type_train)
    type_accuracy = accuracy_score(y_type_test, type_model.predict(X_test))

    priority_model = LogisticRegression(max_iter=1000)
    priority_model.fit(X_train, y_priority_train)
    priority_accuracy = accuracy_score(y_priority_test, priority_model.predict(X_test))

    print("=== Test Seti Doğruluğu ===")
    print(f"Eğitim satırı: {X_train.shape[0]}  |  Test satırı: {X_test.shape[0]}")
    print(f"Kelime dağarcığı (vocabulary) boyutu: {len(vectorizer.get_feature_names_out())}")
    print(f"Arıza Tipi Modeli Accuracy:  {type_accuracy:.3f}")
    print(f"Öncelik Modeli Accuracy:     {priority_accuracy:.3f}")

    # Her sınıf için en belirleyici (en yüksek pozitif katsayılı) kelimeler.
    # LogisticRegression.coef_ her sınıf için bir satırdır (one-vs-rest);
    # büyük pozitif katsayı, o kelimenin varlığının o sınıfın olasılığını
    # güçlü şekilde artırdığı anlamına gelir.
    feature_names = vectorizer.get_feature_names_out()
    top_words_per_class = {}
    print("\n=== Arıza Tipi Modeli — Sınıf Başına En Belirleyici Kelimeler ===")
    for idx, class_label in enumerate(type_model.classes_):
        coefs = type_model.coef_[idx]
        top_indices = coefs.argsort()[::-1][:8]
        top_words = [(feature_names[i], round(float(coefs[i]), 3)) for i in top_indices]
        top_words_per_class[class_label] = top_words
        print(f"{class_label}: {', '.join(word for word, _ in top_words)}")

    os.makedirs("models", exist_ok=True)
    joblib.dump(vectorizer, VECTORIZER_PATH)
    joblib.dump(type_model, TYPE_MODEL_PATH)
    joblib.dump(priority_model, PRIORITY_MODEL_PATH)

    metadata = {
        "trained_at": datetime.now(timezone.utc).isoformat(),
        "approach": (
            "TF-IDF (TfidfVectorizer) + LogisticRegression (iki ayrı model: arıza tipi ve "
            "öncelik) — Modül 9'daki RandomForestClassifier'dan (sayısal/tablosal veri) "
            "BİLİNÇLİ olarak farklı bir teknik; metin sınıflandırma için kullanılır."
        ),
        "training_samples": len(df),
        "train_samples": int(X_train.shape[0]),
        "test_samples": int(X_test.shape[0]),
        "vocabulary_size": int(len(feature_names)),
        "type_model_test_accuracy": round(float(type_accuracy), 4),
        "priority_model_test_accuracy": round(float(priority_accuracy), 4),
        "top_words_per_fault_type": {
            str(k): [{"word": w, "weight": c} for w, c in v] for k, v in top_words_per_class.items()
        },
        "data_source": (
            "SENTETİK — generate_text_training_data.py ile şablon tabanlı üretilmiştir. "
            "Gerçek üretim ortamında ArasSaha'nın work_orders.description sütununda "
            "biriken gerçek arıza açıklama metinleriyle (ve gerçek etiketleriyle) "
            "yeniden eğitilmelidir (bkz. README.md)."
        ),
    }
    with open(METADATA_PATH, "w", encoding="utf-8") as f:
        json.dump(metadata, f, ensure_ascii=False, indent=2)

    print(f"\nVektörleştirici kaydedildi: {VECTORIZER_PATH}")
    print(f"Arıza tipi modeli kaydedildi: {TYPE_MODEL_PATH}")
    print(f"Öncelik modeli kaydedildi: {PRIORITY_MODEL_PATH}")
    print(f"Metadata kaydedildi: {METADATA_PATH}")


if __name__ == "__main__":
    main()
