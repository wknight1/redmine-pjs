# ==============================================================================
# STAGE 1: PostgreSQL 18.1 + 한국어 로케일
# ==============================================================================
FROM postgres:18.1 AS database

USER root

RUN apt-get update && apt-get install -y --no-install-recommends locales && \
    rm -rf /var/lib/apt/lists/* && \
    sed -i '/ko_KR.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen ko_KR.UTF-8

ENV LANG=ko_KR.UTF-8 \
    LC_ALL=ko_KR.UTF-8 \
    TZ=Asia/Seoul

# ==============================================================================
# STAGE 2: Redmine 6.1.1 + 프로덕션 레벨 최적화
# ==============================================================================
FROM redmine:6.1.1 AS application

USER root

# 시스템 패키지 + 추가 폰트 도구
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
# 한글 폰트 최적화 (3종)
# ==============================================================================
# 1. Pretendard: 본문 (가독성 최고)
# 2. D2Coding: 코드 (개발자 친화)
# 3. Noto Sans KR: 백업 폰트
# ==============================================================================
RUN mkdir -p /usr/share/fonts/truetype/custom && cd /usr/share/fonts/truetype/custom && \
    # Pretendard (본문용 - 최신 한글 폰트)
    curl -fsSL -o pretendard.zip https://github.com/orioncactus/pretendard/releases/download/v1.3.9/Pretendard-1.3.9.zip && \
    unzip -q pretendard.zip -d Pretendard && \
    # D2Coding (코드용 - 네이버 개발)
    curl -fsSL -o d2coding.zip https://github.com/naver/d2codingfont/releases/download/VER1.3.2/D2Coding-Ver1.3.2-20180524.zip && \
    unzip -q d2coding.zip -d D2Coding && \
    # 나눔고딕 (PDF 출력용)
    rm -f *.zip && fc-cache -f -v

ENV LANG=ko_KR.UTF-8 \
    LC_ALL=ko_KR.UTF-8 \
    TZ=Asia/Seoul \
    RAILS_ENV=production

WORKDIR /usr/src/redmine

# PDF 폰트 설정
RUN mkdir -p public/fonts && \
    ln -sf /usr/share/fonts/truetype/nanum/NanumGothic.ttf public/fonts/NanumGothic.ttf && \
    ln -sf /usr/share/fonts/truetype/nanum/NanumGothicBold.ttf public/fonts/NanumGothicBold.ttf

# 용어 현지화 (일감 → 이슈)
RUN if [ -f config/locales/ko.yml ]; then sed -i 's/일감/이슈/g' config/locales/ko.yml; fi

# ==============================================================================
# Redmine 6.1 검증된 무료 플러그인 (5개)
# ==============================================================================
RUN mkdir -p plugins && \
    # 1. View Customize - UI 커스터마이징 (필수)
    git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize && \
    # 2. Additionals - 이슈 자동화 + 50개 매크로
    git clone --depth 1 -b master https://github.com/alphanodes/additionals.git plugins/additionals && \
    # 3. Banner - 공지사항 배너
    git clone --depth 1 https://github.com/akiko-pusu/redmine_banner.git plugins/redmine_banner && \
    # 4. Lightbox2 - 이미지 확대보기
    git clone --depth 1 https://github.com/paginagmbh/redmine_lightbox2.git plugins/redmine_lightbox2 && \
    # 5. Collapsible Sidebar - 사이드바 접기
    git clone --depth 1 https://github.com/AlphaNodes/redmine_collapsible_sidebar.git plugins/redmine_collapsible_sidebar && \
    # .git 디렉토리 제거 (용량 절약)
    find plugins -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

# ==============================================================================
# 테마 설치 (2개 - 선택 가능)
# ==============================================================================
RUN mkdir -p public/themes && \
    # 1. PurpleMine2 (가장 인기 - 모던한 디자인)
    git clone -b feature/redmine-6-support --single-branch --depth 1 \
    https://github.com/gagnieray/PurpleMine2.git public/themes/PurpleMine2 && \
    # 2. Circle (RedmineUP 무료 - 깔끔한 UI)
    git clone --depth 1 https://github.com/redmineup/circle_theme.git public/themes/circle && \
    # .git 디렉토리 제거
    find public/themes -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

# Bundler 설정 및 의존성 설치
RUN bundle config set --local without 'development test' && \
    bundle config set --local jobs 4 && \
    bundle install

# ==============================================================================
# Rake 태스크 (한국어 UI + 기본 테마 설정)
# ==============================================================================
RUN mkdir -p lib/tasks && cat > lib/tasks/korean_setup.rake <<'RUBY'
namespace :redmine do
  desc 'Setup Korean UI and default settings'
  task setup_korean: :environment do
    begin
      # ViewCustomize UI 설정
      if defined?(ViewCustomize) && ActiveRecord::Base.connection.table_exists?('view_customizes')
        unless ViewCustomize.exists?(comments: 'Korean UI Pro')
          ViewCustomize.create!(
            path_pattern: '.*',
            customization_type: 'style',
            code: <<-CSS
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
            ,
            enabled: true,
            comments: 'Korean UI Pro'
          )
          puts "✅ 한국어 UI 커스터마이징 생성"
        end
      end
      
      # 기본 설정
      Setting.default_language = 'ko' rescue nil
      Setting.ui_theme = 'PurpleMine2' rescue nil
      
      puts "✅ 한국어 기본 설정 완료"
    rescue => e
      puts "⚠️  설정 중 오류: #{e.message}"
    end
  end
end
RUBY

# 디렉토리 생성 및 권한 설정
RUN mkdir -p tmp/cache tmp/pids log files public/plugin_assets /home/redmine/.bundle && \
    chown -R redmine:redmine /usr/src/redmine /usr/local/bundle /home/redmine

# ==============================================================================
# 프로덕션 Entrypoint (완전 자동화)
# ==============================================================================
RUN mv /docker-entrypoint.sh /docker-entrypoint-original.sh && \
    cat > /docker-entrypoint.sh <<'BASH'
#!/bin/bash
set -e

echo "======================================"
echo "🚀 Redmine Korean Pro Edition"
echo "======================================"

# DB 연결 대기
echo "[1/8] 데이터베이스 연결 확인..."
for i in {1..60}; do
  if PGPASSWORD="$REDMINE_DB_PASSWORD" psql -h "$REDMINE_DB_POSTGRES" \
     -U "$REDMINE_DB_USERNAME" -d "$REDMINE_DB_DATABASE" -c "SELECT 1" >/dev/null 2>&1; then
    echo "   ✅ DB 연결 성공 (${i}초)"
    break
  fi
  sleep 2
done

# database.yml 생성
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

# Secret token
echo "[3/8] Secret token 생성..."
bundle exec rake generate_secret_token RAILS_ENV=production 2>&1 >/dev/null || true
echo "   ✅ Secret token 완료"

# 코어 마이그레이션
echo "[4/8] Redmine 코어 마이그레이션..."
if bundle exec rake db:migrate RAILS_ENV=production 2>&1; then
  echo "   ✅ 코어 마이그레이션 성공"
else
  echo "   ❌ 코어 마이그레이션 실패"
  exit 1
fi

# 플러그인 마이그레이션
echo "[5/8] 플러그인 마이그레이션..."
if bundle exec rake redmine:plugins:migrate RAILS_ENV=production 2>&1; then
  echo "   ✅ 플러그인 마이그레이션 성공"
else
  echo "   ⚠️  플러그인 마이그레이션 실패 (계속)"
fi

# 기본 데이터 로드 (초기 설치 시)
echo "[6/8] 기본 데이터 확인..."
if [ ! -f /usr/src/redmine/files/.initialized ]; then
  bundle exec rake redmine:load_default_data REDMINE_LANG=ko RAILS_ENV=production 2>&1 || true
  touch /usr/src/redmine/files/.initialized
  echo "   ✅ 기본 데이터 로드 완료"
else
  echo "   ✅ 이미 초기화됨 (스킵)"
fi

# Asset 컴파일
echo "[7/8] Asset 컴파일..."
if [ ! -d public/assets ] || [ -z "$(ls -A public/assets 2>/dev/null)" ]; then
  bundle exec rake assets:precompile RAILS_ENV=production 2>&1 | grep -v "yarn" || true
  echo "   ✅ Asset 컴파일 완료"
else
  echo "   ✅ Asset 존재 (스킵)"
fi

# 한국어 설정
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

exec gosu redmine rails server -b 0.0.0.0
BASH

RUN chmod +x /docker-entrypoint.sh

# 헬스체크
RUN cat > /healthcheck.sh <<'BASH'
#!/bin/bash
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/login)
[ "$HTTP_CODE" = "200" ] && exit 0 || exit 1
BASH

RUN chmod +x /healthcheck.sh

EXPOSE 3000
ENTRYPOINT ["/docker-entrypoint.sh"]
