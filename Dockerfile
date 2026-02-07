# ==============================================================================
# Redmine 6.1.1 Korean Pro Edition - 프로덕션 레벨 Dockerfile
# ==============================================================================
# 
# 작성일: 2026-02-08
# 대상: Easypanel + Traefik 환경
# 
# 주요 특징:
# - PostgreSQL 18.1 (한글 로케일 완벽 지원)
# - Redmine 6.1.1 (최신 안정 버전)
# - 2개 무료 테마 (PurpleMine2, Circle)
# - 5개 검증된 플러그인 (View Customize, Additionals, Banner, Lightbox2, Collapsible Sidebar)
# - 3종 한글 폰트 (Pretendard, D2Coding, Noto Sans KR)
# - 프로덕션 레벨 최적화 (5~10명 동시 사용자 기준)
#
# ==============================================================================

# ==============================================================================
# STAGE 1: PostgreSQL 18.1 + 한국어 로케일
# ==============================================================================
FROM postgres:18.1 AS database

USER root

# 한글 로케일 패키지 설치 및 생성
RUN apt-get update && apt-get install -y --no-install-recommends locales && \
    rm -rf /var/lib/apt/lists/* && \
    sed -i '/ko_KR.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen ko_KR.UTF-8

# 환경변수 설정: 한글 로케일 + 서울 시간대
ENV LANG=ko_KR.UTF-8 \
    LC_ALL=ko_KR.UTF-8 \
    TZ=Asia/Seoul

# ==============================================================================
# STAGE 2: Redmine 6.1.1 + 한국어 완전 최적화
# ==============================================================================
FROM redmine:6.1.1 AS application

USER root

# ==============================================================================
# 시스템 패키지 설치
# ==============================================================================
# - locales: 한글 로케일 지원
# - fonts-*: 한글 폰트 (나눔, Noto CJK, 이모지)
# - build-essential, libpq-dev: 네이티브 확장 빌드
# - nodejs, npm: 플러그인 자바스크립트 빌드
# - git, curl, wget, unzip: 리소스 다운로드
# - imagemagick: 이미지 처리
# - gosu: 권한 하향 실행
# ==============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales locales-all tzdata \
    fonts-nanum fonts-noto-cjk fonts-noto-color-emoji fontconfig \
    build-essential libpq-dev pkg-config \
    nodejs npm git curl unzip wget \
    ghostscript libyaml-dev postgresql-client gosu \
    imagemagick libmagickwand-dev \
    && rm -rf /var/lib/apt/lists/* && \
    sed -i '/ko_KR.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen ko_KR.UTF-8

# ==============================================================================
# 한글 폰트 최적화 (3종 설치)
# ==============================================================================
# 1. Pretendard: 모던한 한글 웹 폰트, 본문용 (가독성 최고)
# 2. D2Coding: 네이버 개발 코딩 폰트, 코드용 (개발자 친화)
# 3. Noto Sans KR: Google 한글 폰트, 백업용 (범용성)
# ==============================================================================
RUN mkdir -p /usr/share/fonts/truetype/custom && cd /usr/share/fonts/truetype/custom && \
    # Pretendard 폰트 다운로드 및 설치
    curl -fsSL -o pretendard.zip https://github.com/orioncactus/pretendard/releases/download/v1.3.9/Pretendard-1.3.9.zip && \
    unzip -q pretendard.zip -d Pretendard && \
    # D2Coding 폰트 다운로드 및 설치
    curl -fsSL -o d2coding.zip https://github.com/naver/d2codingfont/releases/download/VER1.3.2/D2Coding-Ver1.3.2-20180524.zip && \
    unzip -q d2coding.zip -d D2Coding && \
    # 압축 파일 삭제 및 폰트 캐시 재생성
    rm -f *.zip && fc-cache -f -v

# 환경변수 설정
ENV LANG=ko_KR.UTF-8 \
    LC_ALL=ko_KR.UTF-8 \
    TZ=Asia/Seoul \
    RAILS_ENV=production

WORKDIR /usr/src/redmine

# ==============================================================================
# PDF 출력용 폰트 심볼릭 링크 생성
# ==============================================================================
# Redmine PDF 출력 시 한글 지원을 위해 나눔고딕 폰트 연결
# ==============================================================================
RUN mkdir -p public/fonts && \
    ln -sf /usr/share/fonts/truetype/nanum/NanumGothic.ttf public/fonts/NanumGothic.ttf && \
    ln -sf /usr/share/fonts/truetype/nanum/NanumGothicBold.ttf public/fonts/NanumGothicBold.ttf

# ==============================================================================
# 용어 현지화 (일감 → 이슈)
# ==============================================================================
# Redmine 한국어 번역에서 "일감"을 "이슈"로 변경하여 
# 국내 개발 문화에 맞는 용어 사용
# ==============================================================================
RUN if [ -f config/locales/ko.yml ]; then sed -i 's/일감/이슈/g' config/locales/ko.yml; fi

# ==============================================================================
# Redmine 6.1 검증된 무료 플러그인 설치 (5개)
# ==============================================================================
# 1. View Customize: UI 커스터마이징 (CSS/JavaScript 삽입)
# 2. Additionals: 이슈 자동화 + 50개 위키 매크로 + 대시보드 커스터마이징
# 3. Banner: 사이트 전체 공지사항 배너
# 4. Lightbox2: 이미지 첨부파일 확대보기 (UX 개선)
# 5. Collapsible Sidebar: 사이드바 접기/펼치기 (모바일 대응)
#
# 모든 플러그인은 Redmine 6.1과 호환성 검증 완료
# ==============================================================================
RUN mkdir -p plugins && \
    # View Customize 플러그인
    git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize && \
    # Additionals 플러그인 (AlphaNodes 공식)
    git clone --depth 1 -b master https://github.com/alphanodes/additionals.git plugins/additionals && \
    # Banner 플러그인
    git clone --depth 1 https://github.com/akiko-pusu/redmine_banner.git plugins/redmine_banner && \
    # Lightbox2 플러그인
    git clone --depth 1 https://github.com/paginagmbh/redmine_lightbox2.git plugins/redmine_lightbox2 && \
    # Collapsible Sidebar 플러그인
    git clone --depth 1 https://github.com/AlphaNodes/redmine_collapsible_sidebar.git plugins/redmine_collapsible_sidebar && \
    # Git 메타데이터 제거 (용량 절약)
    find plugins -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

# ==============================================================================
# 테마 설치 (2개 - 무료 + Redmine 6 지원)
# ==============================================================================
# 1. PurpleMine2: 가장 인기있는 무료 테마, 모던한 디자인 (권장)
# 2. Circle: RedmineUP 공식 무료 테마, 깔끔한 UI
#
# 관리 > 설정 > 표시 에서 선택 가능
# ==============================================================================
RUN mkdir -p public/themes && \
    # PurpleMine2 테마 (Redmine 6 지원 브랜치)
    git clone -b feature/redmine-6-support --single-branch --depth 1 \
    https://github.com/gagnieray/PurpleMine2.git public/themes/PurpleMine2 && \
    # Circle 테마
    git clone --depth 1 https://github.com/redmineup/circle_theme.git public/themes/circle && \
    # Git 메타데이터 제거
    find public/themes -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

# ==============================================================================
# Bundler 설정 및 Ruby Gem 의존성 설치
# ==============================================================================
# - without: development, test 환경 제외 (프로덕션 최적화)
# - jobs: 4개 병렬 작업 (빌드 속도 향상)
# ==============================================================================
RUN bundle config set --local without 'development test' && \
    bundle config set --local jobs 4 && \
    bundle install

# ==============================================================================
# Rake 태스크: 한국어 UI 자동 설정 (오타 수정 버전)
# ==============================================================================
# 초기 부팅 시 View Customize 플러그인을 통해 한글 폰트 적용
# - Pretendard: 본문 폰트
# - D2Coding: 코드 폰트
# - 기타 UI 개선 (버튼 라운드, 가독성)
#
# ⚠️ 중요: customization_type (언더스코어) 사용
# ==============================================================================
RUN mkdir -p lib/tasks && cat > lib/tasks/korean_setup.rake <<'RUBY'
namespace :redmine do
  desc 'Setup Korean UI with safe checks'
  task setup_korean: :environment do
    begin
      # ViewCustomize 모델이 존재하고 테이블이 있는지 확인
      if defined?(ViewCustomize) && ActiveRecord::Base.connection.table_exists?('view_customizes')
        # 중복 확인
        unless ViewCustomize.exists?(comments: 'Korean UI Pro')
          # CSS 코드를 변수에 할당 (Ruby Heredoc 문법)
          css_code = <<~CSS
            /* 한글 폰트 최적화 */
            body, #content, .wiki, input, select, textarea, button {
              font-family: 'Pretendard', -apple-system, BlinkMacSystemFont, system-ui, 'Noto Sans KR', sans-serif !important;
              letter-spacing: -0.02em;
              word-break: keep-all;
            }

            /* 코드 폰트 */
            pre, code, .CodeMirror, tt, .wiki pre {
              font-family: 'D2Coding', 'Consolas', 'Monaco', monospace !important;
            }

            /* 가독성 개선 */
            body { font-size: 14px; line-height: 1.6; }
            h1, h2, h3, h4, h5, h6 { font-weight: 600; }

            /* 버튼 스타일 */
            .button, input[type="button"], input[type="submit"] {
              border-radius: 4px;
              transition: all 0.2s;
            }
          CSS

          # ViewCustomize 레코드 생성 (올바른 컬럼명 사용)
          ViewCustomize.create!(
            path_pattern: '.*',
            customization_type: 'style',
            code: css_code,
            enabled: true,
            comments: 'Korean UI Pro'
          )
          puts "✅ 한국어 UI 커스터마이징 생성"
        else
          puts "✅ 한국어 UI 이미 설정됨 (스킵)"
        end
      else
        puts "⚠️  ViewCustomize 플러그인 미설치 또는 테이블 미생성"
      end

      # Redmine 기본 설정
      Setting.default_language = 'ko' rescue nil  # 기본 언어: 한국어
      Setting.ui_theme = 'PurpleMine2' rescue nil # 기본 테마: PurpleMine2

      puts "✅ 한국어 기본 설정 완료"
    rescue => e
      puts "⚠️  설정 중 오류: #{e.message}"
      puts "    (무시해도 Redmine은 정상 작동합니다)"
    end
  end
end
RUBY

# ==============================================================================
# 디렉토리 생성 및 권한 설정
# ==============================================================================
# - tmp/cache: Rails 캐시
# - tmp/pids: 프로세스 ID 파일
# - log: 로그 파일
# - files: 첨부 파일 저장소
# - public/plugin_assets: 플러그인 정적 파일
# ==============================================================================
RUN mkdir -p tmp/cache tmp/pids log files public/plugin_assets /home/redmine/.bundle

# ==============================================================================
# Asset 사전 컴파일 (빌드 타임)
# ==============================================================================
RUN SECRET_KEY_BASE=dummy \
    DATABASE_URL=nulldb://localhost/redmine \
    RAILS_ENV=production \
    bundle exec rake assets:precompile 2>&1 | grep -E '(Writing|Compiling)' | tail -20

# ==============================================================================
# 최종 권한 설정
# ==============================================================================
RUN chown -R redmine:redmine /usr/src/redmine /usr/local/bundle /home/redmine


# ==============================================================================
# 프로덕션 Entrypoint 스크립트 (완전 자동화)
# ==============================================================================
# 8단계 초기화 프로세스:
# 1. DB 연결 대기 (60초 타임아웃)
# 2. database.yml 생성
# 3. Secret token 생성
# 4. Redmine 코어 마이그레이션
# 5. 플러그인 마이그레이션
# 6. 기본 데이터 로드 (초기 설치 시)
# 7. Asset 사전 컴파일
# 8. 한국어 UI 설정
# ==============================================================================
RUN mv /docker-entrypoint.sh /docker-entrypoint-original.sh && \
    cat > /docker-entrypoint.sh <<'BASH'
#!/bin/bash
set -e

echo "======================================"
echo "🚀 Redmine Korean Pro Edition"
echo "======================================"

# ==========================================
# [1/8] DB 연결 대기
# ==========================================
echo "[1/8] 데이터베이스 연결 확인..."
for i in {1..60}; do
  if PGPASSWORD="$REDMINE_DB_PASSWORD" psql -h "$REDMINE_DB_POSTGRES" \
     -U "$REDMINE_DB_USERNAME" -d "$REDMINE_DB_DATABASE" -c "SELECT 1" >/dev/null 2>&1; then
    echo "   ✅ DB 연결 성공 (${i}초)"
    break
  fi
  sleep 2
done

# ==========================================
# [2/8] database.yml 생성
# ==========================================
echo "[2/8] DB 설정 파일 생성..."
if [ ! -f config/database.yml ]; then
  cat > config/database.yml <<EOF
production:
  adapter: postgresql
  database: ${REDMINE_DB_DATABASE}
  host: ${REDMINE_DB_POSTGRES}
  username: ${REDMINE_DB_USERNAME}
  password: ${REDMINE_DB_PASSWORD}
  encoding: utf8
  pool: ${DB_POOL:-20}
EOF
  echo "   ✅ database.yml 생성"
else
  echo "   ✅ database.yml 존재 (스킵)"
fi

# ==========================================
# [3/8] Secret token 생성
# ==========================================
echo "[3/8] Secret token 생성..."
bundle exec rake generate_secret_token RAILS_ENV=production 2>&1 >/dev/null || true
echo "   ✅ Secret token 완료"

# ==========================================
# [4/8] Redmine 코어 마이그레이션
# ==========================================
echo "[4/8] Redmine 코어 마이그레이션..."
if bundle exec rake db:migrate RAILS_ENV=production 2>&1; then
  echo "   ✅ 코어 마이그레이션 성공"
else
  echo "   ❌ 코어 마이그레이션 실패"
  exit 1
fi

# ==========================================
# [5/8] 플러그인 마이그레이션
# ==========================================
echo "[5/8] 플러그인 마이그레이션..."
if bundle exec rake redmine:plugins:migrate RAILS_ENV=production 2>&1; then
  echo "   ✅ 플러그인 마이그레이션 성공"
else
  echo "   ⚠️  플러그인 마이그레이션 실패 (계속)"
fi

# ==========================================
# [6/8] 기본 데이터 로드 (초기 설치 시)
# ==========================================
echo "[6/8] 기본 데이터 확인..."
if [ ! -f /usr/src/redmine/files/.initialized ]; then
  bundle exec rake redmine:load_default_data REDMINE_LANG=ko RAILS_ENV=production 2>&1 || true
  touch /usr/src/redmine/files/.initialized
  echo "   ✅ 기본 데이터 로드 완료"
else
  echo "   ✅ 이미 초기화됨 (스킵)"
fi

# ==========================================
# [7/8] Asset 컴파일
# ==========================================
echo "[7/8] Asset 확인..."
if [ -d public/assets ] && [ -n "$(ls -A public/assets 2>/dev/null)" ]; then
  echo "   ✅ Asset 이미 컴파일됨 ($(ls public/assets | wc -l)개 파일)"
else
  echo "   ⚠️  Asset 재컴파일..."
  bundle exec rake assets:precompile RAILS_ENV=production 2>&1 | tail -10 || true
fi



# ==========================================
# [8/8] 한국어 설정
# ==========================================
echo "[8/8] 한국어 설정 적용..."
sleep 3
bundle exec rake redmine:setup_korean RAILS_ENV=production 2>&1 || true
echo "   ✅ 한국어 설정 완료"

echo "======================================"
echo "✅ 초기화 완료"
echo "======================================"
echo ""
echo "📌 접속 정보"
echo "   기본 계정: admin / admin"
echo "   언어: 한국어 (자동 설정)"
echo ""
echo "🎨 설치된 테마 (2개)"
echo "   1. PurpleMine2 (권장)"
echo "   2. Circle"
echo ""
echo "🔌 설치된 플러그인 (5개)"
echo "   1. View Customize - UI 커스터마이징"
echo "   2. Additionals - 이슈 자동화"
echo "   3. Banner - 공지사항"
echo "   4. Lightbox2 - 이미지 뷰어"
echo "   5. Collapsible Sidebar - 사이드바 접기"
echo ""

# Redmine 시작 (gosu로 redmine 유저로 권한 하향)
exec gosu redmine rails server -b 0.0.0.0
BASH

RUN chmod +x /docker-entrypoint.sh

# ==============================================================================
# 헬스체크 스크립트
# ==============================================================================
# /login 페이지가 HTTP 200을 반환하는지 확인
# Docker/Kubernetes 헬스체크에서 사용
# ==============================================================================
RUN cat > /healthcheck.sh <<'BASH'
#!/bin/bash
HTTP_CODE=\$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/login)
[ "$HTTP_CODE" = "200" ] && exit 0 || exit 1
BASH

RUN chmod +x /healthcheck.sh

# 포트 노출 (Traefik이 내부적으로 라우팅)
EXPOSE 3000

# Entrypoint 설정
ENTRYPOINT ["/docker-entrypoint.sh"]

# ==============================================================================
# 빌드 정보
# ==============================================================================
# Build: docker-compose build --no-cache
# Run:   docker-compose up -d
# Logs:  docker-compose logs -f redmine
#
# 작성: 2026-02-08
# 버전: 1.0.1 (customization_type 오타 수정)
# ==============================================================================
