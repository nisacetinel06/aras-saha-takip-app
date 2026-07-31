# ArasSaha ML Servisi — Arıza Risk Tahmini (Modül 9) + Arıza Açıklaması Otomatik Sınıflandırma (Modül 10)

Bu klasör, Node.js/Express backend'inden HTTP ile çağrılan bağımsız bir
Python (FastAPI) servisidir. `arassaha-backend`'e hiçbir şekilde import
edilmez; iki taraf da yalnızca HTTP üzerinden konuşur ve birbirinden
bağımsız başlatılıp durdurulabilir.

## Dürüstlük Notu (önemli)

**Bu modeldeki eğitim verisi (`training_data.csv`) sentetiktir.** Gerçek bir
üretim sisteminde bu tür bir modeli anlamlı şekilde eğitmek için yıllarca
birikmiş gerçek arıza/bakım geçmişi gerekir; ArasSaha prototipinde henüz
böyle bir veri seti yok. Bunun yerine, `generate_training_data.py` içinde
tanımlı, elektrik mühendisliği açısından makul kural tabanlı bir olasılık
fonksiyonuyla (ekipman yaşı, son bakımdan geçen süre, geçmiş arıza sayısı,
yük faktörü ve ekipman tipine göre ağırlıklandırılmış) sentetik bir veri
seti üretilip model bunun üzerinde eğitiliyor.

Bu, gerçek veri toplanana kadar saha projelerinde yaygın ve kabul gören bir
başlangıç yaklaşımıdır: **model eğitimi, servis mimarisi ve Node.js/Flutter
entegrasyonu gerçektir; sahte olan yalnızca eğitim verisidir.** Gerçek
üretim ortamına geçildiğinde tek yapılması gereken, `generate_training_data.py`
yerine ArasSaha'nın gerçek `work_orders`/`equipment` geçmişinden türetilmiş
bir CSV vermek ve `train_model.py`'yi bununla yeniden çalıştırmaktır — model
mimarisi, feature seti ve servis kodu değişmeden kalır.

## Kurulum

```bash
cd arassaha-ml
python -m venv venv
venv\Scripts\activate        # Windows
# source venv/bin/activate   # macOS/Linux
pip install -r requirements.txt
```

## Modeli eğitme

```bash
python generate_training_data.py   # training_data.csv oluşturur
python train_model.py              # models/risk_model.pkl ve model_metadata.json oluşturur
```

`train_model.py` çalıştıktan sonra konsola test doğruluğu, precision,
recall, F1 ve özellik önem sıralaması yazdırılır; aynı bilgiler
`models/model_metadata.json` içine de kalıcı olarak kaydedilir (modelin
"kimlik kartı").

## Servisi başlatma

```bash
uvicorn app:app --reload --port 8000
```

- `GET /health` — servis ve model yüklü mü kontrolü
- `POST /predict` — tek bir ekipman için risk skoru (Modül 9)
- `POST /classify-text` — bir arıza açıklama metni için arıza tipi/öncelik önerisi (Modül 10)

Node.js backend'i bu servise `ML_SERVICE_URL` ortam değişkeniyle
(varsayılan `http://localhost:8000`) bağlanır (bkz. `arassaha-backend/routes/risk.js`
ve `arassaha-backend/routes/nlp.js`).

## Modül 10 — Arıza Açıklaması Otomatik Sınıflandırma

```bash
python generate_text_training_data.py   # text_training_data.csv oluşturur
python train_text_model.py              # models/tfidf_vectorizer.pkl, text_type_model.pkl, text_priority_model.pkl, text_model_metadata.json oluşturur
```

**İki farklı ML yaklaşımı, tek serviste:** Modül 9, SAYISAL/tablosal ekipman
verisinden (yaş, bakım süresi, geçmiş arıza sayısı vb.) `RandomForestClassifier`
ile risk skoru üretir. Modül 10 ise BİLİNÇLİ olarak farklı bir teknikle
çalışır: serbest METİN arıza açıklamasını `TfidfVectorizer` ile sayısal bir
vektöre çevirip iki ayrı `LogisticRegression` modeliyle (biri arıza tipi,
biri öncelik için) sınıflandırır. İki teknik de aynı `arassaha-ml` FastAPI
servisinde, tek bir `uvicorn` process'inde birlikte çalışır — ayrı bir servis
kurulmadı. Aynı dürüstlük ilkesi burada da geçerlidir: eğitim verisi
(`text_training_data.csv`) gerçek şirket arıza kayıtları değil, şablon tabanlı
üretilmiş sentetik Türkçe metinlerdir (bkz. `generate_text_training_data.py`);
gerçek üretim ortamında model, ArasSaha'nın gerçek arıza açıklama
metinleriyle yeniden eğitilir.
