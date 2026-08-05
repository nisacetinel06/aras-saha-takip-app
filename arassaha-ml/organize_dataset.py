# Görüntü Tabanlı Hasar Tespiti (Modül 15) — veri seti düzenleme.
#
# Kaynak: Kaggle "Power Line Components Images Dataset"
# https://www.kaggle.com/datasets/abdulbasit89/power-line-components-images-dataset
# (kullanıcı: abdulbasit89, lisans: CC0-1.0 — kaynak burada ve README'de belirtilir).
#
# Ham veri seti raw_dataset/processed_raw_data/train/ altında 10 alt klasörde
# geliyor (bkz. README Modül 15 notu): 6 tanesi sağlam bileşen (disk/pin
# izolatör, dropout, trafo bushing, direk, çapraz kol), 4 tanesi bunların
# yapay olarak üretilmiş HASARLI ("defective"/"defeftive" — kaynak veri
# setinde bu son kelimede bir yazım hatası var, aynen bırakıldı çünkü klasör
# adı) versiyonu. Direk ve çapraz kol için hasarlı versiyon YOK — bu veri
# setinin kendi tasarımı, eksik değil.
#
# DÜZELTME (bkz. check_data_leakage.py): Kaggle açıklamasına göre "defective
# images created artificially" — disk/pin izolatör hasarlı klasörlerinde
# (6, 7) her taban görselin (pic_N.jpg) birkaç augmented VARYANTI da var
# (pic_N_0.jpg, pic_N_1.jpg, ...). check_data_leakage.py, bu varyantların
# TEKİL GÖRSEL bazında rastgele bölündüğünde 47 grubun (243 dosya) farklı
# split'lere dağıldığını, ayrıca 68 dosyanın birebir (MD5) aynı içerikle
# birden fazla split'te göründüğünü kanıtladı — klasik train/test sızıntısı.
#
# İKİ AYRI sızıntı kaynağı var, bu yüzden İKİSİ DE gruplamaya dahil edilir:
#   1) İsimlendirme örüntüsü: pic_N.jpg <-> pic_N_M.jpg (aynı taban id).
#   2) BİREBİR AYNI İÇERİK, FARKLI taban id: örn. pic_1027.jpg ile
#      pic_1031.jpg baytı baytına aynı ama isim örüntüsü bunları
#      İLİŞKİLENDİRMEZ (farklı taban id) — yalnızca MD5 karşılaştırmasıyla
#      yakalanabilir (bkz. check_data_leakage.py'nin ikinci turda hâlâ 65
#      hash çakışması bulması). Bu yüzden dosyalar bir UNION-FIND ile
#      gruplanır: iki dosya AYNI taban id'yi PAYLAŞIYORSA ya da AYNI MD5
#      hash'e sahipse aynı gruba (bileşene) birleştirilir — TEK bir mekanizma
#      her iki sızıntı kaynağını da kapsar, "taban görsel grubu" artık bir
#      bağlantılı bileşendir, yalnızca isimlendirmeye dayalı statik bir anahtar değil.
import hashlib
import random
import re
import shutil
from collections import defaultdict
from pathlib import Path

RAW_DIR = Path(__file__).parent / "raw_dataset" / "processed_raw_data" / "train"
OUT_DIR = Path(__file__).parent / "dataset"

# check_data_leakage.py'deki BASE_NAME_PATTERN ile BİREBİR AYNI olmalı — biri
# değişirse diğeri de güncellenmeli, aksi halde sızıntı kontrolü artık bu
# script'in gerçekte ne yaptığını doğrulamaz. pic_0.jpg -> taban '0',
# pic_0_1.jpg -> taban '0' (varyant '1'); img_1023.jpg -> taban '1023'
# (varyant yok, bu klasörlerde hiç görülmedi ama zararsız).
BASE_NAME_PATTERN = re.compile(r"^(?P<prefix>pic|img)_(?P<base>\d+)(?:_\d+)?\.jpg$", re.IGNORECASE)


def label_for(dirname: str) -> str:
    return "hasarli" if "defe" in dirname.lower() else "hasarsiz"


TRAIN_RATIO = 0.70
VAL_RATIO = 0.15
# TEST_RATIO kalan ~0.15
RANDOM_SEED = 42  # deterministik bölünme — script tekrar çalıştırılınca AYNI sonucu verir


def base_key(class_dir_name: str, filename: str) -> tuple:
    """Bir dosyanın isimlendirme örüntüsüne göre taban anahtarı — bkz. dosya
    başındaki DÜZELTME notu #1. Eşleşmeyen dosyalar KENDİ tekil anahtarını
    oluşturur (bir ilişki UYDURULMAZ)."""
    m = BASE_NAME_PATTERN.match(filename)
    if m:
        return (class_dir_name, m.group("prefix"), m.group("base"))
    return (class_dir_name, "__singleton__", filename)


def md5_of(path: Path) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


class UnionFind:
    """Basit union-find (path compression'lı) — dosyaları hem isimlendirme
    hem de birebir içerik eşleşmesine göre TEK bir bağlantılı bileşende
    toplamak için (bkz. dosya başındaki DÜZELTME notu #2)."""

    def __init__(self):
        self._parent: dict = {}

    def find(self, x):
        self._parent.setdefault(x, x)
        while self._parent[x] != x:
            self._parent[x] = self._parent[self._parent[x]]
            x = self._parent[x]
        return x

    def union(self, a, b):
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self._parent[ra] = rb


def collect_groups_by_label() -> dict[str, list[list[Path]]]:
    """label -> [[dosya1, dosya2, ...] (bir bağlantılı bileşenin tüm dosyaları), ...]

    Her dosya iki şekilde birbirine bağlanır: (1) isimlendirme taban id'si
    AYNIYSA, (2) MD5 içeriği AYNIYSA (farklı taban id'ler olsa bile). Sonuçta
    ortaya çıkan her bağlantılı bileşen train/val/test'e BİRLİKTE, hiç
    bölünmeden atanır."""
    files_by_label: dict[str, list[Path]] = {"hasarli": [], "hasarsiz": []}

    for class_dir in sorted(RAW_DIR.iterdir()):
        if not class_dir.is_dir():
            continue
        label = label_for(class_dir.name)
        files = sorted(class_dir.glob("*.jpg"))
        files_by_label[label].extend(files)
        print(f"  {class_dir.name:32s} -> {label:9s} ({len(files)} görsel)")

    groups_by_label: dict[str, list[list[Path]]] = {}
    for label, files in files_by_label.items():
        uf = UnionFind()

        by_base_key: dict[tuple, list[Path]] = defaultdict(list)
        by_hash: dict[str, list[Path]] = defaultdict(list)
        for f in files:
            by_base_key[base_key(f.parent.name, f.name)].append(f)
            by_hash[md5_of(f)].append(f)

        for bucket in (*by_base_key.values(), *by_hash.values()):
            for f in bucket[1:]:
                uf.union(str(bucket[0]), str(f))

        components: dict[str, list[Path]] = defaultdict(list)
        for f in files:
            components[uf.find(str(f))].append(f)

        groups = list(components.values())
        merged_files = sum(len(g) for g in groups if len(g) > 1)
        print(
            f"  [{label}] {len(files)} görsel -> {len(groups)} bağlantılı bileşen "
            f"({merged_files} görsel en az bir başkasıyla aynı grupta)"
        )
        groups_by_label[label] = groups

    return groups_by_label


def stratified_split_groups(groups: list[list[Path]], seed: int) -> tuple[list, list, list]:
    """Bir sınıfın TABAN GRUPLARI listesini train/val/test'e böler (grup =
    birim, tekil dosya DEĞİL) — aynı taban görselin tüm varyantları her zaman
    BİRLİKTE aynı split'e düşer. Grup büyüklükleri farklı olduğu için nihai
    DOSYA oranları tam olarak %70/15/15 olmayabilir (bkz. main() çıktısı),
    bu beklenen ve kabul edilebilir bir sapmadır — sızıntısız olmak, tam
    orana sadık kalmaktan daha önemlidir."""
    shuffled = groups.copy()
    random.Random(seed).shuffle(shuffled)
    n = len(shuffled)
    n_train = int(n * TRAIN_RATIO)
    n_val = int(n * VAL_RATIO)
    return shuffled[:n_train], shuffled[n_train:n_train + n_val], shuffled[n_train + n_val:]


def copy_split(groups: list[list[Path]], split: str, label: str) -> int:
    dest_dir = OUT_DIR / split / label
    dest_dir.mkdir(parents=True, exist_ok=True)
    count = 0
    for group in groups:
        for src in group:
            # Farklı ham klasörlerden gelen dosya adları çakışabilir — hedef
            # dosya adının başına kaynak klasör adı eklenerek çakışma/sessiz
            # üzerine yazma önlenir (check_data_leakage.py bu adlandırmayı
            # ORGANIZED_NAME_PATTERN ile geri çözümler).
            dest_name = f"{src.parent.name}__{src.name}"
            shutil.copy2(src, dest_dir / dest_name)
            count += 1
    return count


def main() -> None:
    if OUT_DIR.exists():
        print(f"Mevcut {OUT_DIR} siliniyor (temiz baştan üretilecek)...")
        shutil.rmtree(OUT_DIR)

    print(f"Ham veri seti taranıyor: {RAW_DIR}")
    groups_by_label = collect_groups_by_label()
    for label, groups in groups_by_label.items():
        total_files = sum(len(g) for g in groups)
        print(f"  {label}: {len(groups)} taban grup, {total_files} toplam görsel")

    print("\nBölünüyor (train %70 / val %15 / test %15, GRUP bazlı stratified)...")
    totals = {"train": {}, "val": {}, "test": {}}
    for label, groups in groups_by_label.items():
        train_groups, val_groups, test_groups = stratified_split_groups(groups, RANDOM_SEED)
        totals["train"][label] = copy_split(train_groups, "train", label)
        totals["val"][label] = copy_split(val_groups, "val", label)
        totals["test"][label] = copy_split(test_groups, "test", label)

    print("\n=== Nihai görsel sayıları ===")
    grand_total = 0
    for split in ("train", "val", "test"):
        split_total = sum(totals[split].values())
        grand_total += split_total
        print(f"{split:6s}: hasarli={totals[split]['hasarli']:5d}  hasarsiz={totals[split]['hasarsiz']:5d}  (toplam {split_total})")
    print(f"\nGenel toplam: {grand_total} görsel -> {OUT_DIR}")

    hasarli_total = sum(totals[s]["hasarli"] for s in totals)
    hasarsiz_total = sum(totals[s]["hasarsiz"] for s in totals)
    ratio = hasarli_total / (hasarli_total + hasarsiz_total)
    print(f"Sınıf dengesi: hasarli %{ratio*100:.1f} / hasarsiz %{(1-ratio)*100:.1f}")
    if ratio < 0.3 or ratio > 0.7:
        print("UYARI: Sınıflar arası belirgin bir dengesizlik var — train_damage_model.py'daki")
        print("veri artırma (augmentation) katmanı ve/veya class_weight bunu telafi edecek.")


if __name__ == "__main__":
    main()
