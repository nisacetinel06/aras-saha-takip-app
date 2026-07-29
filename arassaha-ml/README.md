# ArasSaha ML Servisi — Arıza Risk Tahmini (Modül 9)

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
- `POST /predict` — tek bir ekipman için risk skoru

Node.js backend'i bu servise `ML_SERVICE_URL` ortam değişkeniyle
(varsayılan `http://localhost:8000`) bağlanır (bkz. `arassaha-backend/routes/risk.js`).
