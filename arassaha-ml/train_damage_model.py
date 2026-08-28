# Görüntü Tabanlı Hasar Tespiti (Modül 15) — model eğitimi.
#
# Kaynak veri seti: Kaggle "Power Line Components Images Dataset"
# https://www.kaggle.com/datasets/abdulbasit89/power-line-components-images-dataset
# (kullanıcı: abdulbasit89, lisans: CC0-1.0). bkz. organize_dataset.py ve README.
#
# Mimari: MobileNetV2 (ImageNet ağırlıkları) + transfer learning, 2 aşamalı:
#   Aşama 1 — yalnızca eklenen katmanlar (MobileNetV2 dondurulmuş)
#   Aşama 2 — fine-tuning (MobileNetV2'nin son 30 katmanı çözülür, çok düşük LR)
#
# DÜRÜSTLÜK NOTU: risk.js/anomaly.js'teki modellerin aksine bu model SENTETİK
# değil GERÇEK, halka açık bir veri setiyle eğitildi — ama "hasarlı" görseller
# de kaynak veri setinde yapay olarak üretilmiş (defective) versiyonlar,
# ArasSaha'nın kendi sahasından toplanmış gerçek arıza fotoğrafları değil.
# Üretimde gerçek İSG/iş emri fotoğraflarıyla yeniden eğitilmesi gerekir.
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # sunucu/CI ortamında ekran olmadan PNG üretmek için
import matplotlib.pyplot as plt
import numpy as np
import tensorflow as tf
from sklearn.metrics import accuracy_score, confusion_matrix, f1_score, precision_score, recall_score

IMG_SIZE = (224, 224)  # MobileNetV2'nin beklediği giriş boyutu
BATCH_SIZE = 32
SEED = 42

BASE_DIR = Path(__file__).parent
DATASET_DIR = BASE_DIR / "dataset"
MODELS_DIR = BASE_DIR / "models"
MODELS_DIR.mkdir(exist_ok=True)

KAGGLE_URL = "https://www.kaggle.com/datasets/abdulbasit89/power-line-components-images-dataset"


def load_split(split: str, shuffle: bool):
    ds = tf.keras.utils.image_dataset_from_directory(
        DATASET_DIR / split,
        image_size=IMG_SIZE,
        batch_size=BATCH_SIZE,
        label_mode="binary",
        shuffle=shuffle,
        seed=SEED,
    )
    class_names = ds.class_names
    assert class_names == ["hasarli", "hasarsiz"], (
        f"Beklenmeyen klasör/sınıf sırası: {class_names} — image_dataset_from_directory "
        "klasörleri alfabetik sıralar, 'hasarli' < 'hasarsiz' olmalı (organize_dataset.py "
        "çıktısını kontrol edin)."
    )
    # Keras label=0 -> hasarli (alfabetik ilk), label=1 -> hasarsiz. Modelin
    # sigmoid çıktısının sezgisel kalması için ("1.0 = hasarlı olasılığı
    # yüksek") etiketler burada TERS ÇEVRİLİYOR — bu satırdan sonra akıştaki
    # HER YER (eğitim, değerlendirme, kaydedilen model, FastAPI serving) 1=hasarli,
    # 0=hasarsiz kabul eder.
    return ds.map(lambda x, y: (x, 1.0 - y))


def count_images(directory: Path) -> dict:
    return {
        label: len(list((directory / label).glob("*.jpg")) + list((directory / label).glob("*.png")))
        for label in ("hasarli", "hasarsiz")
    }


# TEST-20: GERÇEK DÜNYA doğrulama seti — bkz. build_real_world_validation_set.py
# dosya başı notu. Kaggle veri setinden TAMAMEN AYRI, Wikimedia Commons'tan
# indirilmiş CC lisanslı görseller. EĞİTİME/fine-tuning'e HİÇ KATILMAZ —
# yalnızca aşağıdaki değerlendirme adımında, modelin ağırlıkları tamamen
# sabitlenmiş hâldeyken kullanılır.
REAL_WORLD_DIR = DATASET_DIR / "real_world_validation"


def load_real_world_validation():
    """Klasör hiç oluşturulmadıysa (build_real_world_validation_set.py hiç
    çalıştırılmadıysa) veya içi boşsa None döner — bu durumda ana eğitim
    akışı ETKİLENMEZ, yalnızca bu ek değerlendirme adımı atlanır."""
    if not REAL_WORLD_DIR.exists():
        return None, None
    counts = count_images(REAL_WORLD_DIR)
    if counts["hasarli"] + counts["hasarsiz"] == 0:
        return None, None

    ds = tf.keras.utils.image_dataset_from_directory(
        REAL_WORLD_DIR,
        image_size=IMG_SIZE,
        batch_size=BATCH_SIZE,
        label_mode="binary",
        shuffle=False,
        seed=SEED,
    )
    class_names = ds.class_names
    assert class_names == ["hasarli", "hasarsiz"], (
        f"Beklenmeyen klasör/sınıf sırası: {class_names} — bkz. load_split() AYNI notu."
    )
    return ds.map(lambda x, y: (x, 1.0 - y)), counts


print("Veri setleri yükleniyor...")
train_ds = load_split("train", shuffle=True)
val_ds = load_split("val", shuffle=False)
test_ds = load_split("test", shuffle=False)

split_counts = {split: count_images(DATASET_DIR / split) for split in ("train", "val", "test")}
print("Görsel sayıları:", json.dumps(split_counts, ensure_ascii=False))

AUTOTUNE = tf.data.AUTOTUNE
# .cache(): tüm veri seti RAM'e rahatça sığar (~10K görsel x 224x224x3, ~1.5GB)
# — ilk epoch'tan sonra diskten tekrar okuma/decode olmaz, CPU'da eğitim
# hızını belirgin şekilde artırır.
train_ds = train_ds.cache().shuffle(1000, seed=SEED).prefetch(AUTOTUNE)
val_ds = val_ds.cache().prefetch(AUTOTUNE)
test_ds = test_ds.cache().prefetch(AUTOTUNE)

# --- Veri artırma — yalnızca eğitim sırasında (model.fit) aktif; Keras bunu
# model.predict/evaluate çağrılarında otomatik pasifleştirir. Sınıf dengesi
# %40/%60 ile ciddi dengesiz olmasa da (bkz. organize_dataset.py çıktısı),
# ~10K görsellik bir veri setinde ezberlemeyi (overfitting) azaltmak için
# genel bir iyi pratik.
#
# TEST-20 GÜNCELLEMESİ — DOMAIN SHIFT'i azaltmak için sıkılaştırıldı: Kaggle
# veri seti nispeten "temiz" koşullarda çekilmiş (iyi ışık, net odak, düz
# açı); ArasSaha'nın sahadaki gerçek kullanıcıları telefonla, değişken ışıkta
# (gölge/parlama), eğik açıdan, bazen bulanık fotoğraf çekecek. Önceki
# parametreler bu farkı simüle etmek için YETERSİZDİ:
#   RandomRotation  0.15 -> AYNI (zaten agresif, arttırılmadı)
#   RandomZoom      0.15 -> 0.2  (kameraya yakın/uzak çekim farkı)
#   RandomBrightness 0.15 -> 0.3 (gölge/parlak güneş ışığı farkı çok daha geniş)
#   RandomContrast  YOK  -> 0.3 (EKLENDİ — bulutlu/güneşli gün kontrast farkı)
#   GaussianNoise   YOK  -> 0.05 (EKLENDİ — telefon kamerası sensör gürültüsü/
#                                  hafif bulanıklığın kabaca bir yaklaşıklaması)
data_augmentation = tf.keras.Sequential(
    [
        tf.keras.layers.RandomFlip("horizontal"),
        tf.keras.layers.RandomRotation(0.15),
        tf.keras.layers.RandomZoom(0.2),
        tf.keras.layers.RandomBrightness(0.3),
        tf.keras.layers.RandomContrast(0.3),
        tf.keras.layers.GaussianNoise(0.05),
    ],
    name="augmentation",
)

# --- Transfer Learning mimarisi ---
base_model = tf.keras.applications.MobileNetV2(
    input_shape=IMG_SIZE + (3,), include_top=False, weights="imagenet"
)
base_model.trainable = False

inputs = tf.keras.Input(shape=IMG_SIZE + (3,))
x = data_augmentation(inputs)
x = tf.keras.applications.mobilenet_v2.preprocess_input(x)
x = base_model(x, training=False)
x = tf.keras.layers.GlobalAveragePooling2D()(x)
x = tf.keras.layers.Dropout(0.3)(x)
outputs = tf.keras.layers.Dense(1, activation="sigmoid")(x)
model = tf.keras.Model(inputs, outputs, name="damage_classifier")
model.summary()

checkpoint_path = MODELS_DIR / "damage_model.keras"

# --- Aşama 1: yalnızca eklenen katmanlar ---
model.compile(
    optimizer=tf.keras.optimizers.Adam(learning_rate=1e-3),
    loss="binary_crossentropy",
    metrics=["accuracy"],
)
print("\n=== AŞAMA 1: Yalnızca eklenen katmanlar eğitiliyor (MobileNetV2 dondurulmuş) ===")
history1 = model.fit(
    train_ds,
    validation_data=val_ds,
    epochs=12,
    callbacks=[
        tf.keras.callbacks.EarlyStopping(monitor="val_loss", patience=5, restore_best_weights=True),
        tf.keras.callbacks.ModelCheckpoint(str(checkpoint_path), monitor="val_accuracy", save_best_only=True),
    ],
)

# --- Aşama 2: fine-tuning (son 30 katman çözülür) ---
base_model.trainable = True
FINE_TUNE_AT = len(base_model.layers) - 30
for layer in base_model.layers[:FINE_TUNE_AT]:
    layer.trainable = False

model.compile(
    optimizer=tf.keras.optimizers.Adam(learning_rate=1e-5),  # aşama 1'den ÇOK düşük — önceden öğrenileni bozmamak için
    loss="binary_crossentropy",
    metrics=["accuracy"],
)
print(f"\n=== AŞAMA 2: Fine-tuning ({len(base_model.layers) - FINE_TUNE_AT} katman çözüldü) ===")
initial_epoch = len(history1.history["loss"])
history2 = model.fit(
    train_ds,
    validation_data=val_ds,
    epochs=initial_epoch + 8,
    initial_epoch=initial_epoch,
    callbacks=[
        tf.keras.callbacks.EarlyStopping(monitor="val_loss", patience=5, restore_best_weights=True),
        tf.keras.callbacks.ModelCheckpoint(str(checkpoint_path), monitor="val_accuracy", save_best_only=True),
    ],
)

# --- Eğitim eğrileri ---
def combined(key):
    return history1.history[key] + history2.history[key]

phase1_epochs = len(history1.history["loss"])
fig, axes = plt.subplots(1, 2, figsize=(12, 5))
axes[0].plot(combined("accuracy"), label="Eğitim")
axes[0].plot(combined("val_accuracy"), label="Doğrulama")
axes[0].axvline(phase1_epochs - 0.5, color="gray", linestyle="--", label="Fine-tuning başlangıcı")
axes[0].set_title("Doğruluk (Accuracy)")
axes[0].set_xlabel("Epoch")
axes[0].legend()
axes[1].plot(combined("loss"), label="Eğitim")
axes[1].plot(combined("val_loss"), label="Doğrulama")
axes[1].axvline(phase1_epochs - 0.5, color="gray", linestyle="--", label="Fine-tuning başlangıcı")
axes[1].set_title("Kayıp (Loss)")
axes[1].set_xlabel("Epoch")
axes[1].legend()
fig.tight_layout()
fig.savefig(MODELS_DIR / "training_history.png", dpi=150)
plt.close(fig)
print(f"\nKaydedildi: {MODELS_DIR / 'training_history.png'}")

# --- Test seti değerlendirme (tek geçişte y_true/y_prob + yanlış sınıflandırılanlar toplanır) ---
print("\n=== Test seti değerlendirmesi ===")
y_true_list, y_prob_list, batches = [], [], []
for images, labels in test_ds:
    preds = model.predict(images, verbose=0).flatten()
    y_true_list.extend(labels.numpy().flatten().tolist())
    y_prob_list.extend(preds.tolist())
    batches.append((images.numpy(), labels.numpy().flatten(), preds))

y_true = np.array(y_true_list)
y_prob = np.array(y_prob_list)
y_pred = (y_prob >= 0.5).astype(int)

accuracy = accuracy_score(y_true, y_pred)
precision = precision_score(y_true, y_pred, zero_division=0)
recall = recall_score(y_true, y_pred, zero_division=0)
f1 = f1_score(y_true, y_pred, zero_division=0)

print(f"Accuracy:  {accuracy:.4f}")
print(f"Precision: {precision:.4f}")
print(f"Recall:    {recall:.4f}")
print(f"F1-score:  {f1:.4f}")

# --- TEST-20: GERÇEK DÜNYA doğrulama seti değerlendirmesi ---
# Kaggle test setinden TAMAMEN AYRI — model bu görselleri EĞİTİM sırasında
# hiç görmedi (bkz. REAL_WORLD_DIR notu). Amaç: domain shift'in (Kaggle'ın
# "temiz" koşulları vs. gerçek sahadaki değişken ışık/açı/kalite) ne kadar
# ciddi olduğunu DÜRÜSTÇE ölçmek — bu sayı Kaggle test setinden DAHA DÜŞÜK
# çıkarsa bu bir hata DEĞİL, beklenen ve raporlanması gereken bir bulgudur.
real_world_ds, real_world_counts = load_real_world_validation()
real_world_metrics = None
if real_world_ds is None:
    print(
        "\n=== Gerçek dünya doğrulama seti ===\n"
        "Atlandı — dataset/real_world_validation/ hiç oluşturulmamış ya da boş. "
        "Önce 'python build_real_world_validation_set.py' çalıştırılmalı."
    )
else:
    print(f"\n=== Gerçek dünya doğrulama seti değerlendirmesi ({real_world_counts}) ===")
    rw_true_list, rw_prob_list = [], []
    for images, labels in real_world_ds:
        preds = model.predict(images, verbose=0).flatten()
        rw_true_list.extend(labels.numpy().flatten().tolist())
        rw_prob_list.extend(preds.tolist())

    rw_true = np.array(rw_true_list)
    rw_prob = np.array(rw_prob_list)
    rw_pred = (rw_prob >= 0.5).astype(int)

    rw_accuracy = accuracy_score(rw_true, rw_pred)
    rw_precision = precision_score(rw_true, rw_pred, zero_division=0)
    rw_recall = recall_score(rw_true, rw_pred, zero_division=0)
    rw_f1 = f1_score(rw_true, rw_pred, zero_division=0)

    print(f"Accuracy:  {rw_accuracy:.4f}  (Kaggle test seti: {accuracy:.4f}, fark: {rw_accuracy - accuracy:+.4f})")
    print(f"Precision: {rw_precision:.4f}  (Kaggle test seti: {precision:.4f})")
    print(f"Recall:    {rw_recall:.4f}  (Kaggle test seti: {recall:.4f})")
    print(f"F1-score:  {rw_f1:.4f}  (Kaggle test seti: {f1:.4f})")

    real_world_metrics = {
        "n_images": int(len(rw_true)),
        "split_counts": real_world_counts,
        "accuracy": round(float(rw_accuracy), 4),
        "precision": round(float(rw_precision), 4),
        "recall": round(float(rw_recall), 4),
        "f1_score": round(float(rw_f1), 4),
        "accuracy_diff_vs_kaggle_test": round(float(rw_accuracy - accuracy), 4),
        "source": "Wikimedia Commons (CC0/CC-BY/CC-BY-SA) — bkz. build_real_world_validation_set.py, "
        "dataset/real_world_validation/attribution.json",
        "note": (
            "Bu görseller EĞİTİME KATILMADI, yalnızca değerlendirme için kullanıldı. "
            "Negatif bir fark (Kaggle'a göre düşük performans), domain shift'in gerçek "
            "boyutunun dürüst bir göstergesidir — gizlenmedi, burada raporlanıyor."
        ),
    }

# --- Confusion matrix (matplotlib ile — seaborn bağımlılığı eklemeye gerek yok) ---
cm = confusion_matrix(y_true, y_pred)
fig, ax = plt.subplots(figsize=(5, 4))
im = ax.imshow(cm, cmap="Blues")
ax.set_xticks([0, 1])
ax.set_xticklabels(["hasarsiz", "hasarli"])
ax.set_yticks([0, 1])
ax.set_yticklabels(["hasarsiz", "hasarli"])
ax.set_xlabel("Tahmin")
ax.set_ylabel("Gerçek")
ax.set_title("Confusion Matrix (Test Seti)")
for i in range(2):
    for j in range(2):
        ax.text(j, i, str(cm[i, j]), ha="center", va="center", color="white" if cm[i, j] > cm.max() / 2 else "black")
fig.colorbar(im)
fig.tight_layout()
fig.savefig(MODELS_DIR / "confusion_matrix.png", dpi=150)
plt.close(fig)
print(f"Kaydedildi: {MODELS_DIR / 'confusion_matrix.png'}")

# --- Yanlış sınıflandırılan örnekler ---
misclassified = [
    (img, int(true_label), float(prob))
    for images, labels, preds in batches
    for img, true_label, prob in zip(images, labels, preds)
    if int(prob >= 0.5) != int(true_label)
]

if misclassified:
    n_show = min(6, len(misclassified))
    fig, axes = plt.subplots(1, n_show, figsize=(3 * n_show, 3))
    axes = [axes] if n_show == 1 else axes
    for ax, (img, true_label, prob) in zip(axes, misclassified[:n_show]):
        ax.imshow(img.astype("uint8"))
        true_str = "hasarli" if true_label == 1 else "hasarsiz"
        pred_str = "hasarli" if prob >= 0.5 else "hasarsiz"
        ax.set_title(f"Gerçek: {true_str}\nTahmin: {pred_str} (%{prob * 100:.0f})", fontsize=9)
        ax.axis("off")
    fig.tight_layout()
    fig.savefig(MODELS_DIR / "misclassified_examples.png", dpi=150)
    plt.close(fig)
    print(
        f"Kaydedildi: {MODELS_DIR / 'misclassified_examples.png'} "
        f"({len(misclassified)} yanlış sınıflandırma / {len(y_true)} test görseli)"
    )
else:
    print("Test setinde yanlış sınıflandırılan örnek yok — misclassified_examples.png üretilmedi.")

# --- Model + metadata kaydet ---
model.save(MODELS_DIR / "damage_model.keras")
print(f"\nModel kaydedildi: {MODELS_DIR / 'damage_model.keras'}")

metadata = {
    "dataset_source": {
        "name": "Power Line Components Images Dataset",
        "kaggle_user": "abdulbasit89",
        "url": KAGGLE_URL,
        "license": "CC0-1.0",
    },
    "split_counts": split_counts,
    "architecture": {
        "base_model": "MobileNetV2 (ImageNet ağırlıkları)",
        "input_size": list(IMG_SIZE) + [3],
        "head": "GlobalAveragePooling2D -> Dropout(0.3) -> Dense(1, sigmoid)",
        "training": "2 aşamalı transfer learning: (1) yalnızca head, (2) son 30 katman fine-tuning",
        "phase1_epochs_run": phase1_epochs,
        "phase2_epochs_run": len(history2.history["loss"]),
    },
    "test_metrics": {
        "accuracy": round(float(accuracy), 4),
        "precision": round(float(precision), 4),
        "recall": round(float(recall), 4),
        "f1_score": round(float(f1), 4),
        "n_test_images": int(len(y_true)),
        "n_misclassified": len(misclassified),
    },
    "real_world_validation_metrics": real_world_metrics,
    "label_convention": "sigmoid çıktısı: 1.0 = hasarlı olasılığı, 0.0 = hasarsız olasılığı",
}
with open(MODELS_DIR / "damage_model_metadata.json", "w", encoding="utf-8") as f:
    json.dump(metadata, f, ensure_ascii=False, indent=2)
print(f"Metadata kaydedildi: {MODELS_DIR / 'damage_model_metadata.json'}")
