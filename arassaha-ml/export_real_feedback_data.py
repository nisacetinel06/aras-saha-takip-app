"""
Modül 15 (Görüntü Tabanlı Hasar Tespiti) — TEST-20: Gerçek Saha
Fotoğraflarından Geri Bildirim Döngüsü, dışa aktarma adımı.

arassaha-backend'deki isg_reports tablosunda, bir yönetici/dispeçerin
İSG bildirimini incelerken "Fotoğrafta gerçekten hasar var mıydı?" sorusunu
Evet/Hayır olarak yanıtladığı kayıtlar birikir (bkz.
arassaha-backend/routes/isg.js PATCH /:id/verify-damage,
human_verified_damage sütunu). Bu script o kayıtların fotoğraflarını
(uploads/isg/ klasöründen) GERÇEK etiketleriyle (human_verified_damage —
modelin KENDİ tahmini cv_is_damaged DEĞİL) birlikte
dataset/train/hasarli|hasarsiz klasörlerine EKLER.

KRİTİK İLKE: Kaggle veri seti SİLİNMEZ/DEĞİŞTİRİLMEZ, yalnızca ÜZERİNE
eklenir — bu script hiçbir zaman dataset/train/ içindeki mevcut bir dosyaya
dokunmaz, yalnızca YENİ dosyalar ekler (isim çakışması olmasın diye
`real_feedback_<isg_report_id>.<ext>` adlandırması kullanılır, Kaggle
kaynaklı dosyalar `pic_*`/`img_*` adlandırması kullanır — bkz.
organize_dataset.py — bu yüzden çakışma yapısal olarak imkansızdır).

İDEMPOTENT: hangi isg_reports.id'lerin daha önce dışa aktarıldığı
`dataset/real_feedback_manifest.json`da tutulur — script tekrar
çalıştırıldığında aynı fotoğraf İKİNCİ KEZ kopyalanmaz/sayılmaz.

Kullanım:
    python export_real_feedback_data.py

Ardından, yeterli miktar (bkz. MIN_REAL_FEEDBACK_FOR_RETRAIN) birikince:
    python train_damage_model.py   # artık dataset/train/ Kaggle + gerçek veri karışımı
"""
import json
import shutil
import sqlite3
from pathlib import Path

BASE_DIR = Path(__file__).parent
DATASET_DIR = BASE_DIR / "dataset"
MANIFEST_PATH = DATASET_DIR / "real_feedback_manifest.json"

BACKEND_DIR = BASE_DIR.parent / "arassaha-backend"
DB_PATH = BACKEND_DIR / "aras_saha.db"
UPLOADS_ISG_DIR = BACKEND_DIR / "uploads" / "isg"

# Prompt'ta belirtilen eşik: yeterli miktar (50+) gerçek fotoğraf birikince
# fine-tune anlamlı hale gelir — bu script eşiği KONTROL EDER ve raporlar,
# ama eşiğin altında bile dışa aktarmayı YAPAR (biriktirme süreci baştan
# başlamalı, "eşiğe ulaşana kadar hiçbir şey yapma" YANLIŞ olurdu — aksi
# halde 49. fotoğrafta bile hâlâ sıfır dışa aktarılmış veri olurdu).
MIN_REAL_FEEDBACK_FOR_RETRAIN = 50


def load_manifest() -> dict:
    if MANIFEST_PATH.exists():
        return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    return {"exported_report_ids": []}


def save_manifest(manifest: dict) -> None:
    MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")


def resolve_photo_path(photo_path: str) -> Path | None:
    """isg_reports.photo_path DB'de '/uploads/isg/<dosya>' biçiminde saklanır
    (bkz. arassaha-backend/routes/isg.js) — burada gerçek disk yoluna çevrilir.
    routes/kvkk.js/jobs/retentionPurge.js'teki AYNI path traversal savunması:
    yalnızca dosya adı (basename) kullanılır, ../ ile klasör dışına çıkılamaz."""
    filename = Path(photo_path).name
    if not filename:
        return None
    resolved = (UPLOADS_ISG_DIR / filename).resolve()
    if not str(resolved).startswith(str(UPLOADS_ISG_DIR.resolve())):
        return None
    return resolved


def main():
    if not DB_PATH.exists():
        print(f"[HATA] Backend veritabanı bulunamadı: {DB_PATH}")
        print("Bu script arassaha-backend ile AYNI makinede/klasör yapısında çalıştırılmalıdır.")
        return

    for label in ("hasarli", "hasarsiz"):
        (DATASET_DIR / "train" / label).mkdir(parents=True, exist_ok=True)

    manifest = load_manifest()
    already_exported = set(manifest["exported_report_ids"])

    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    try:
        rows = conn.execute(
            """
            SELECT id, photo_path, human_verified_damage
            FROM isg_reports
            WHERE human_verified_damage IS NOT NULL
              AND photo_path IS NOT NULL
            ORDER BY id
            """
        ).fetchall()
    finally:
        conn.close()

    newly_exported = 0
    skipped_already = 0
    skipped_missing_file = 0
    counts = {"hasarli": 0, "hasarsiz": 0}

    for row in rows:
        report_id = row["id"]
        if report_id in already_exported:
            skipped_already += 1
            counts["hasarli" if row["human_verified_damage"] == 1 else "hasarsiz"] += 1
            continue

        disk_path = resolve_photo_path(row["photo_path"])
        if disk_path is None or not disk_path.exists():
            print(f"[UYARI] isg_reports.id={report_id}: fotoğraf diskte bulunamadı ({row['photo_path']}), atlandı.")
            skipped_missing_file += 1
            continue

        label = "hasarli" if row["human_verified_damage"] == 1 else "hasarsiz"
        ext = disk_path.suffix or ".jpg"
        dest = DATASET_DIR / "train" / label / f"real_feedback_{report_id}{ext}"

        shutil.copy2(disk_path, dest)
        already_exported.add(report_id)
        newly_exported += 1
        counts[label] += 1
        print(f"[{label}] dışa aktarıldı: isg_reports.id={report_id} -> {dest.relative_to(BASE_DIR)}")

    manifest["exported_report_ids"] = sorted(already_exported)
    save_manifest(manifest)

    total_exported = len(already_exported)
    print(f"\nBu çalıştırmada YENİ dışa aktarılan: {newly_exported} (hasarli={counts['hasarli']}, hasarsiz={counts['hasarsiz']})")
    print(f"Zaten dışa aktarılmıştı (atlandı): {skipped_already}")
    if skipped_missing_file:
        print(f"Fotoğrafı diskte bulunamadığı için atlanan: {skipped_missing_file}")
    print(f"Toplam birikmiş gerçek geri bildirim fotoğrafı: {total_exported}")

    if total_exported >= MIN_REAL_FEEDBACK_FOR_RETRAIN:
        print(
            f"\n{total_exported} >= {MIN_REAL_FEEDBACK_FOR_RETRAIN} eşiği AŞILDI — "
            "'python train_damage_model.py' şimdi Kaggle + gerçek saha verisinin "
            "KARIŞIMIYLA yeniden eğitim yapabilir."
        )
    else:
        print(
            f"\nHenüz eşiğin altında ({total_exported}/{MIN_REAL_FEEDBACK_FOR_RETRAIN}) — "
            "dosyalar dataset/train/'e eklendi (gelecekteki bir eğitimde zaten kullanılacak), "
            "ama fine-tune için 'yeterli miktar' beklemek hâlâ mantıklı bir tedbir."
        )


if __name__ == "__main__":
    main()
