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
