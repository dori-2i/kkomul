"""
엑셀 상품 양식(kkomul_products_template.xlsx)을 읽어 Supabase(PostgreSQL)에 올리는 스크립트

필요한 것
  pip install "psycopg[binary]" openpyxl

환경변수
  DATABASE_URL   Supabase 연결 문자열 (Connect > Direct > Session pooler, 비밀번호 포함)

실행
  python upload_products.py 상품목록.xlsx --dry-run   # 검사만 하고 DB에는 넣지 않음
  python upload_products.py 상품목록.xlsx             # 검사 통과 시 DB에 저장

동작
  - 한 군데라도 잘못된 칸이 있으면 몇 번째 줄인지 알려 주고 아무것도 저장하지 않아요.
  - 같은 파일을 여러 번 올려도 상품은 중복되지 않아요(상품코드 기준으로 갱신).
  - 가격은 '상품 + 판매처 + 가격확인일'이 같으면 다시 넣지 않고, 날짜가 다르면 기록으로 쌓여요.
  - 상품코드가 EX로 시작하거나 브랜드가 '예시브랜드'인 줄은 예시라서 건너뛰어요.
"""

import argparse
import datetime as dt
import os
import re
import sys

from openpyxl import load_workbook

KST = dt.timezone(dt.timedelta(hours=9))

CATEGORY = {
    "바디슈트": "bodysuit",
    "우주복": "romper",
    "상하복": "set",
    "아우터": "outer",
    "하의·양말": "legwear",
    "모자·소품": "acc",
    "장난감": "toy",
}

PRODUCT_COLS = ["상품코드", "브랜드", "상품명", "카테고리", "정가", "판매처", "판매가",
                "상품링크", "이미지링크", "판매사이즈", "추천시작개월", "추천종료개월", "가격확인일"]
SIZE_COLS = ["브랜드", "상품코드", "사이즈", "개월최소", "개월최대", "키최소(cm)", "키최대(cm)",
             "몸무게최소(kg)", "몸무게최대(kg)", "가슴둘레(cm)", "화장(cm)", "총장(cm)",
             "허리둘레(cm)", "엉덩이둘레(cm)", "옆기장(cm)", "머리둘레(cm)", "메모"]

# 엑셀 머리글 → DB 칸, 허용 범위
MEASURES = [
    ("가슴둘레(cm)",   "chest_cm",   20, 120),
    ("화장(cm)",       "sleeve_cm",   5,  80),
    ("총장(cm)",       "length_cm",  10, 130),
    ("허리둘레(cm)",   "waist_cm",   20, 100),
    ("엉덩이둘레(cm)", "hip_cm",     20, 120),
    ("옆기장(cm)",     "outseam_cm", 10, 100),
    ("머리둘레(cm)",   "head_cm",    25,  60),
]
CHART_COLS = ["height_min_cm", "height_max_cm", "weight_min_kg", "weight_max_kg", "note",
              "month_min", "month_max"] + [m[1] for m in MEASURES]

SKU_RE = re.compile(r"^[A-Za-z0-9_-]{1,30}$")


# ---------------------------------------------------------------- 읽기 도우미

def text(v):
    if v is None:
        return ""
    if isinstance(v, float) and v.is_integer():
        v = int(v)
    return str(v).strip()


def is_example(sku, brand):
    return sku.upper().startswith("EX") or brand == "예시브랜드"


def read_sheet(wb, name, expected):
    if name not in wb.sheetnames:
        sys.exit(f"'{name}' 시트가 없어요. 양식의 시트 이름을 바꾸지 말아 주세요.")
    ws = wb[name]
    header = [text(c.value) for c in ws[1]]
    missing = [c for c in expected if c not in header]
    if missing:
        sys.exit(f"'{name}' 시트에 머리글이 없어요: {', '.join(missing)}")
    idx = {c: header.index(c) for c in expected}
    for r, row in enumerate(ws.iter_rows(min_row=2, values_only=True), start=2):
        rec = {c: row[i] if i < len(row) else None for c, i in idx.items()}
        if all(text(v) == "" for v in rec.values()):
            continue
        yield r, rec


class Checker:
    def __init__(self):
        self.errors = []

    def err(self, sheet, row, msg):
        self.errors.append(f"[{sheet} {row}행] {msg}")

    def integer(self, sheet, row, col, v, required, lo=None, hi=None):
        s = text(v).replace(",", "").replace("원", "")
        if s == "":
            if required:
                self.err(sheet, row, f"{col}을(를) 입력해 주세요.")
            return None
        try:
            n = int(float(s))
        except ValueError:
            self.err(sheet, row, f"{col}은(는) 숫자여야 해요: '{text(v)}'")
            return None
        if (lo is not None and n < lo) or (hi is not None and n > hi):
            self.err(sheet, row, f"{col}은(는) {lo}~{hi} 사이여야 해요: {n}")
            return None
        return n

    def decimal(self, sheet, row, col, v, required, lo, hi):
        s = text(v)
        if s == "":
            if required:
                self.err(sheet, row, f"{col}을(를) 입력해 주세요.")
            return None
        try:
            n = round(float(s), 2)
        except ValueError:
            self.err(sheet, row, f"{col}은(는) 숫자여야 해요: '{s}'")
            return None
        if not lo <= n <= hi:
            self.err(sheet, row, f"{col}은(는) {lo}~{hi} 사이여야 해요: {n}")
            return None
        return n

    def date(self, sheet, row, col, v):
        if isinstance(v, dt.datetime):
            return v.date()
        if isinstance(v, dt.date):
            return v
        s = text(v).replace(".", "-").replace("/", "-")
        if s == "":
            self.err(sheet, row, f"{col}을(를) 입력해 주세요.")
            return None
        try:
            return dt.date.fromisoformat(s)
        except ValueError:
            self.err(sheet, row, f"{col}은(는) YYYY-MM-DD 형식이어야 해요: '{text(v)}'")
            return None


# ---------------------------------------------------------------- 검사

def parse(path):
    wb = load_workbook(path, data_only=True)
    ck = Checker()
    products = {}   # sku -> 상품 정보
    prices = []     # 판매처별 가격
    skipped = 0

    for r, x in read_sheet(wb, "상품", PRODUCT_COLS):
        sku, brand = text(x["상품코드"]), text(x["브랜드"])
        if sku and is_example(sku, brand):
            skipped += 1
            continue
        if not SKU_RE.match(sku):
            ck.err("상품", r, f"상품코드는 영문·숫자·-·_ 30자 이내여야 해요: '{sku}'")
            continue
        name = text(x["상품명"])
        if not name:
            ck.err("상품", r, "상품명을 입력해 주세요.")
        cat = CATEGORY.get(text(x["카테고리"]))
        if not cat:
            ck.err("상품", r, f"카테고리는 목록에서 골라 주세요: '{text(x['카테고리'])}'")
        list_price = ck.integer("상품", r, "정가", x["정가"], False, 1)
        mall = text(x["판매처"])
        if not mall:
            ck.err("상품", r, "판매처를 입력해 주세요.")
        price = ck.integer("상품", r, "판매가", x["판매가"], True, 1)
        link = text(x["상품링크"])
        if not link.startswith(("http://", "https://")):
            ck.err("상품", r, "상품링크는 http로 시작해야 해요.")
        image = text(x["이미지링크"]) or None
        if image and not image.startswith(("http://", "https://")):
            ck.err("상품", r, "이미지링크는 http로 시작해야 해요.")
        sizes = [s for s in re.split(r"[,\s/]+", text(x["판매사이즈"])) if s]
        for s in sizes:
            if len(s) > 10:
                ck.err("상품", r, f"사이즈 표기가 너무 길어요: '{s}'")
        m_min = ck.integer("상품", r, "추천시작개월", x["추천시작개월"], False, 0, 36)
        m_max = ck.integer("상품", r, "추천종료개월", x["추천종료개월"], False, 0, 36)
        if m_min is not None and m_max is not None and m_min > m_max:
            ck.err("상품", r, "추천시작개월이 추천종료개월보다 커요.")
        checked = ck.date("상품", r, "가격확인일", x["가격확인일"])
        if checked and checked > dt.date.today() + dt.timedelta(days=1):
            ck.err("상품", r, f"가격확인일이 미래 날짜예요: {checked}")

        p = products.setdefault(sku, {
            "sku": sku, "brand": brand or None, "name": name, "category": cat,
            "list_price": list_price, "image": image, "sizes": [],
            "month_min": m_min, "month_max": m_max, "first_row": r,
        })
        if p["name"] != name or p["category"] != cat or p["brand"] != (brand or None):
            ck.err("상품", r, f"같은 상품코드({sku})인데 {p['first_row']}행과 상품명·브랜드·카테고리가 달라요.")
        p["image"] = p["image"] or image
        p["list_price"] = p["list_price"] or list_price
        for s in sizes:
            if s not in p["sizes"]:
                p["sizes"].append(s)
        prices.append({"sku": sku, "mall": mall, "price": price, "link": link, "date": checked, "row": r})

    seen = {}
    for pr in prices:
        key = (pr["sku"], pr["mall"], pr["date"])
        if key in seen:
            ck.err("상품", pr["row"], f"{seen[key]}행과 상품코드·판매처·가격확인일이 같아요. 한 줄만 남겨 주세요.")
        seen[key] = pr["row"]

    charts = []
    for r, x in read_sheet(wb, "사이즈표", SIZE_COLS):
        brand, sku = text(x["브랜드"]), text(x["상품코드"])
        if is_example(sku, brand) and (sku or brand):
            skipped += 1
            continue
        if not brand and not sku:
            ck.err("사이즈표", r, "브랜드나 상품코드 중 하나는 입력해 주세요.")
        size = text(x["사이즈"])
        if not size or len(size) > 10:
            ck.err("사이즈표", r, "사이즈를 10자 이내로 입력해 주세요.")
        elif "(" in size:
            ck.err("사이즈표", r, f"사이즈 칸에는 '{size.split('(')[0].strip()}'만 적고, 괄호 속 개월은 개월최소·개월최대 칸에 적어 주세요.")
        m_min = ck.integer("사이즈표", r, "개월최소", x["개월최소"], False, 0, 72)
        m_max = ck.integer("사이즈표", r, "개월최대", x["개월최대"], False, 0, 72)
        if m_min is not None and m_max is not None and m_min > m_max:
            ck.err("사이즈표", r, "개월최소가 개월최대보다 커요.")
        h_min = ck.decimal("사이즈표", r, "키최소(cm)", x["키최소(cm)"], False, 30, 140)
        h_max = ck.decimal("사이즈표", r, "키최대(cm)", x["키최대(cm)"], False, 30, 140)
        if h_min is not None and h_max is not None and h_min >= h_max:
            ck.err("사이즈표", r, "키최소가 키최대보다 작아야 해요.")
        w_min = ck.decimal("사이즈표", r, "몸무게최소(kg)", x["몸무게최소(kg)"], False, 1, 30)
        w_max = ck.decimal("사이즈표", r, "몸무게최대(kg)", x["몸무게최대(kg)"], False, 1, 30)
        rec = {"brand": brand or None, "sku": sku or None, "size": size, "row": r,
               "height_min_cm": h_min, "height_max_cm": h_max,
               "weight_min_kg": w_min, "weight_max_kg": w_max,
               "note": text(x["메모"])[:200] or None,
               "month_min": m_min, "month_max": m_max}
        for col, field, lo, hi in MEASURES:
            rec[field] = ck.decimal("사이즈표", r, col, x[col], False, lo, hi)
        if all(rec[f] is None for f in ["height_max_cm", "month_max"] + [m[1] for m in MEASURES]):
            ck.err("사이즈표", r, "키최대, 개월최대, 부위별 치수 중 하나는 적어 주세요.")
        charts.append(rec)

    return products, prices, charts, skipped, ck.errors


# ---------------------------------------------------------------- 저장

def brand_id(cur, name, cache):
    if not name:
        return None
    if name not in cache:
        cur.execute("""insert into brands(name) values (%s)
                       on conflict (name) do update set name = excluded.name
                       returning id""", (name,))
        cache[name] = cur.fetchone()[0]
    return cache[name]


def save(conn, products, prices, charts):
    stats = {"상품": 0, "가격(신규)": 0, "가격(이미 있음)": 0, "사이즈표": 0}
    brands, ids = {}, {}
    with conn.cursor() as cur:
        for p in products.values():
            cur.execute(
                """insert into products(sku, brand_id, name, category, list_price, image_url, month_min, month_max)
                   values (%s, %s, %s, %s, %s, %s, %s, %s)
                   on conflict (sku) do update set
                     brand_id = excluded.brand_id, name = excluded.name, category = excluded.category,
                     list_price = excluded.list_price, image_url = excluded.image_url,
                     month_min = excluded.month_min, month_max = excluded.month_max
                   returning id""",
                (p["sku"], brand_id(cur, p["brand"], brands), p["name"], p["category"],
                 p["list_price"], p["image"], p["month_min"], p["month_max"]))
            ids[p["sku"]] = cur.fetchone()[0]
            stats["상품"] += 1
            if p["sizes"]:
                cur.execute("delete from product_sizes where product_id = %s", (ids[p["sku"]],))
                for s in p["sizes"]:
                    cur.execute("insert into product_sizes(product_id, size_label) values (%s, %s)",
                                (ids[p["sku"]], s))

        for pr in prices:
            at = dt.datetime.combine(pr["date"], dt.time(0), tzinfo=KST)
            cur.execute("""select 1 from product_prices
                           where product_id = %s and mall_name = %s and collected_at = %s""",
                        (ids[pr["sku"]], pr["mall"], at))
            if cur.fetchone():
                cur.execute("""update product_prices set price = %s, link = %s
                               where product_id = %s and mall_name = %s and collected_at = %s""",
                            (pr["price"], pr["link"], ids[pr["sku"]], pr["mall"], at))
                stats["가격(이미 있음)"] += 1
            else:
                cur.execute("""insert into product_prices(product_id, mall_name, price, link, collected_at)
                               values (%s, %s, %s, %s, %s)""",
                            (ids[pr["sku"]], pr["mall"], pr["price"], pr["link"], at))
                stats["가격(신규)"] += 1

        cols_sql = ", ".join(CHART_COLS)
        marks = ", ".join(["%s"] * (len(CHART_COLS) + 1))
        updates = ", ".join(f"{c} = excluded.{c}" for c in CHART_COLS)
        for c in charts:
            vals = (c["size"], *[c[k] for k in CHART_COLS])
            if c["sku"]:
                pid = ids.get(c["sku"])
                if pid is None:
                    cur.execute("select id from products where sku = %s", (c["sku"],))
                    found = cur.fetchone()
                    if not found:
                        raise ValueError(f"[사이즈표 {c['row']}행] 상품코드 {c['sku']}인 상품이 없어요.")
                    pid = found[0]
                cur.execute(
                    f"""insert into size_charts(product_id, size_label, {cols_sql})
                        values (%s, {marks})
                        on conflict (product_id, size_label) where product_id is not null
                        do update set {updates}""", (pid, *vals))
            else:
                cur.execute(
                    f"""insert into size_charts(brand_id, size_label, {cols_sql})
                        values (%s, {marks})
                        on conflict (brand_id, size_label) where brand_id is not null
                        do update set {updates}""", (brand_id(cur, c["brand"], brands), *vals))
            stats["사이즈표"] += 1
    return stats


def main():
    ap = argparse.ArgumentParser(description="엑셀 상품 양식을 Supabase에 올려요.")
    ap.add_argument("xlsx", help="작성한 엑셀 파일 경로")
    ap.add_argument("--dry-run", action="store_true", help="검사만 하고 저장하지 않음")
    args = ap.parse_args()

    products, prices, charts, skipped, errors = parse(args.xlsx)
    print(f"읽은 내용: 상품 {len(products)}개, 판매처별 가격 {len(prices)}줄, 사이즈표 {len(charts)}줄"
          f" (예시 {skipped}줄 건너뜀)")
    if errors:
        print(f"\n고칠 곳이 {len(errors)}군데 있어요. 아무것도 저장하지 않았어요.")
        for e in errors:
            print("  -", e)
        sys.exit(1)
    if args.dry_run:
        print("\n검사 통과. --dry-run이라 DB에는 저장하지 않았어요.")
        return

    if "DATABASE_URL" not in os.environ:
        sys.exit("환경변수 DATABASE_URL이 설정되지 않았어요.")
    import psycopg
    try:
        with psycopg.connect(os.environ["DATABASE_URL"]) as conn:
            stats = save(conn, products, prices, charts)
    except ValueError as e:
        sys.exit(f"{e}\n아무것도 저장하지 않았어요.")
    print("\n저장 완료: " + ", ".join(f"{k} {v}" for k, v in stats.items()))


if __name__ == "__main__":
    main()
