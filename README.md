# Redmine Docker 패키지

이 프로젝트는 Redmine 6.1.1 기반의 커스텀 Docker 이미지와 Docker Compose 설정을 제공합니다.

## 주요 특징

* **Redmine 6.1.1**: 최신 안정 버전 사용.
* **한국어 최적화**: '일감' 용어를 '이슈'로 변경하여 친숙한 UI 제공.
* **인기 테마 포함**: Opale, PurpleMine2, Circle, Abis 테마 기본 탑재.
* **필수 플러그인 포함**:
    * View Customize: UI/UX 커스터마이징 가능.
    * Issue Templates: 이슈 생성 시 템플릿 지원.
    * WBS: 프로젝트 구조 시각화 도구.

## 실행 방법

1. 환경 변수 설정: `DB_PASSWORD`와 `REDMINE_SECRET_KEY`를 설정해야 합니다.
2. 실행 명령:
   ```bash
   docker-compose up -d
   ```

## 라이선스
MIT



2) (멀티플랫폼 필요하면) amd64+arm64 빌드+푸시
먼저 Buildx를 docker-container 드라이버로 만들어야 하는 경우가 많아 (네가 방금 본 에러가 그 케이스).

bash
docker buildx rm mybuilder 2>/dev/null || true
docker buildx create --name mybuilder --driver docker-container --bootstrap --use
그 다음:

bash
export DB_IMG=wknight1/redmine-pjs-postgres
export DB_TAG=18.1-ko-20260208

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --target database \
  -t ${DB_IMG}:${DB_TAG} \
  -t ${DB_IMG}:latest \
  --push \
  .
3) 푸시 확인
bash
docker buildx imagetools inspect ${DB_IMG}:${DB_TAG}
멀티플랫폼이면 manifest에 amd64/arm64가 같이 보일 거야.



-----
2) 여러 줄로 쓰고 싶으면 (zsh/macOS)
마지막 줄에 . 을 꼭 넣으면 됩니다.

bash
export IMG=wknight1/redmine-pjs
export TAG=6.1.1-ko-20260208

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --target application \
  -t ${IMG}:${TAG} \
  -t ${IMG}:latest \
  --push \
  .
-----
export IMG=wknight1/redmine-pjs-postgres
export TAG=18.1-ko

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f Dockerfile.postgres \
  -t ${IMG}:${TAG} \
  -t ${IMG}:latest \
  --push \
  .
