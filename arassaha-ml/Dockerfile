FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Sentetik eğitim verisi + model, build zamanında üretilir (arassaha-backend'in
# Dockerfile'ının build zamanında seed.js çalıştırmasıyla aynı desen). Sabit
# random_seed sayesinde deterministiktir; git'e commit edilmez (bkz. .gitignore).
#
# İSTİSNA (Modül 15 — models/damage_model.keras): bu model burada YENİDEN
# EĞİTİLMEZ. Gerçek bir Kaggle veri setiyle lokalde ~30-70 dakikada bir kez
# eğitildi ve git'e commit edildi (bkz. .gitignore istisnası, README.md Modül
# 15) — yukarıdaki `COPY . .` onu olduğu gibi imaja taşır. Diğer üç modelin
# aksine "ucuza yeniden üretilebilir" değil, bu yüzden build-time training
# deseninin DIŞINDA tutuldu.
#
# UI/servis denetimi bulgusu: Modül 10 ve Modül 11 önceden BURADA
# eğitilmiyordu — yalnızca Modül 9 (risk) build-time training deseninin
# içindeydi, diğer ikisi unutulmuştu. Canlıda /health hep
# anomaly_model_loaded=false dönüyordu, Tüketim Analizi ve (muhtemelen)
# arıza açıklaması önerisi bu yüzden hiç çalışmıyordu. generate_consumption_data.py
# artık arassaha-backend'in veritabanı bu container'da YOKKEN de (STANDALONE
# mod) çalışabiliyor — yalnızca model eğitimi için sentetik sayaç ID'leriyle
# consumption_training_data.csv üretir, gerçek bir veritabanına dokunmaz
# (bkz. o script'teki STANDALONE mod notu). generate_text_training_data.py
# zaten baştan beri veritabanından bağımsızdı.
RUN python generate_training_data.py && python train_model.py
RUN python generate_text_training_data.py && python train_text_model.py
RUN python generate_consumption_data.py && python train_anomaly_model.py

EXPOSE 8000

# Railway, servise dinamik bir PORT ortam değişkeni enjekte eder ve genel
# domain'i o porta yönlendirir (arassaha-backend/server.js'teki
# `process.env.PORT || 3000` ile aynı desen); bu yüzden shell-form CMD ile
# $PORT'u okuyoruz, yerelde (venv ile) çalıştırırken olduğu gibi sabit 8000
# değil.
CMD uvicorn app:app --host 0.0.0.0 --port ${PORT:-8000}
