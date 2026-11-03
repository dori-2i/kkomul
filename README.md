# 꼬물샵 (가칭)

아기 키와 개월 수에 맞는 옷 사이즈를 알려 주고, 개월별 장난감과 참고 가격을 모아 보여 주는 육아 쇼핑 정보 서비스입니다.
쇼핑몰 연계(구매 링크) + 고객 참여(상품별 댓글, 최저가 제보, 포인트)를 결합한 구조를 목표로 합니다.

## 핵심 기능 (계획)

- **사이즈 핏 체크**: 아기 개월 수·키를 입력하면 상품 사이즈별로 `작아요 / 딱 맞아요 / 넉넉해요 / 아직 너무 커요` 판정
- **상품 큐레이션**: 판매처별 참고 가격, 가격 확인일, 구매 링크
- **개월별 장난감 순위**와 상태별 추정 중고가
- **참여 기능**: 상품별 댓글, 최저가 제보(승인 시 포인트), 출석체크, 포인트로 아기 프로필 꾸미기
- **운영**: 신고 누적 기반 제재, 운영자 댓글 숨김, 구매 링크 클릭 통계(브랜드 협업 자료)

## 기술 스택

- DB: PostgreSQL (Supabase, 서울 리전), 전 테이블 RLS 적용
- 데이터 도구: Python (`psycopg`, `openpyxl`)
- 웹 앱: Next.js 16 + Tailwind CSS, Vercel 배포 예정

## 폴더 구조

```
DB/        DB 스키마와 마이그레이션
scripts/   엑셀 상품 양식을 DB에 올리는 스크립트
web/       Next.js 웹 앱
data/      상품·사이즈표 입력용 엑셀 양식
feature_backlog.md   기능 목록과 결정 기록
```

## DB 설치 순서

새 DB를 만들 때: `schema.sql` → `migration_002_points.sql` → `migration_003_engagement.sql` → `migration_012_public_read.sql`

(`schema.sql`에는 migration_001, 004~011의 변경이 이미 반영되어 있습니다.)

## 상품 업로드

```powershell
pip install "psycopg[binary]" openpyxl
python scripts/upload_products.py data/상품목록.xlsx --dry-run   # 검사만
python scripts/upload_products.py data/상품목록.xlsx             # 저장
```

DB 연결 주소는 저장소 맨 위 `.env` 파일(`DATABASE_URL=...`)에 두며, `.gitignore`로 저장소에서 제외합니다.

## 웹 앱 실행

```powershell
cd web
npm install
copy env.local.example .env.local   # 값 채우기
npm run dev                          # http://localhost:3000
```

## 진행 기록

- 2026-11-03: 서비스 기획, 화면 시안, DB 설계, 상품 업로드 도구, 사이즈 판정 로직, 웹 앱 상품 목록
- 네이버 쇼핑 검색 API 종료(2026-07-31)에 따라 상품·가격은 직접 큐레이션 + 사용자 제보 방식으로 전환
