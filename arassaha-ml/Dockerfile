FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Sentetik eğitim verisi + model, build zamanında üretilir (arassaha-backend'in
# Dockerfile'ının build zamanında seed.js çalıştırmasıyla aynı desen). Sabit
# random_seed sayesinde deterministiktir; git'e commit edilmez (bkz. .gitignore).
RUN python generate_training_data.py && python train_model.py

EXPOSE 8000

# Railway, servise dinamik bir PORT ortam değişkeni enjekte eder ve genel
# domain'i o porta yönlendirir (arassaha-backend/server.js'teki
# `process.env.PORT || 3000` ile aynı desen); bu yüzden shell-form CMD ile
# $PORT'u okuyoruz, yerelde (venv ile) çalıştırırken olduğu gibi sabit 8000
# değil.
CMD uvicorn app:app --host 0.0.0.0 --port ${PORT:-8000}
