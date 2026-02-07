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
# STAGE 2: Redmine 6.1.1 + 한국어 완전 최적화 + 프로덕션 강화
# ==============================================================================
FROM redmine:6.1.1 AS application

USER root

# 시스템 패키지
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales locales-all tzdata \
    fonts-nanum fonts-noto-cjk fontconfig \
    build-essential libpq-dev pkg-config \
    nodejs npm git curl unzip wget \
    ghostscript libyaml-dev postgresql-client gosu \
    imagemagick libmagickwand-dev \
    && rm -rf /var/lib/apt/lists/* && \
    sed -i '/ko_KR.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen ko_KR.UTF-8

# 한글 폰트 설치
RUN mkdir -p /usr/share/fonts/truetype/custom && cd /usr/share/fonts/truetype/custom && \
    curl -fsSL -o pretendard.zip https://github.com/orioncactus/pretendard/releases/download/v1.3.9/Pretendard-1.3.9.zip && \
    unzip -q pretendard.zip -d Pretendard && \
    curl -fsSL -o d2coding.zip https://github.com/naver/d2codingfont/releases/download/VER1.3.2/D2Coding-Ver1.3.2-20180524.zip && \
    unzip -q d2coding.zip -d D2Coding && \
    rm -f *.zip && fc-cache -f -v

ENV LANG=ko_KR.UTF-8 \
    LC_ALL=ko_KR.UTF-8 \
    TZ=Asia/Seoul \
    RAILS_ENV=production

WORKDIR /usr/src/redmine

# PDF 폰트 링크
RUN mkdir -p public/fonts && \
    ln -sf /usr/share/fonts/truetype/nanum/NanumGothic.ttf public/fonts/NanumGothic.ttf

# 용어 현지화 (일감 → 이슈)
RUN if [ -f config/locales/ko.yml ]; then sed -i 's/일감/이슈/g' config/locales/ko.yml; fi

# ==============================================================================
# 플러그인 설치 (빌드 타임)
# ==============================================================================
RUN mkdir -p plugins && \
    git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize && \
    git clone --depth 1 https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs && \
    git clone --depth 1 https://github.com/akiko-pusu/redmine_issue_templates.git plugins/redmine_issue_templates && \
    find plugins -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

# ==============================================================================
# 테마 설치 (PurpleMine2 - Redmine 6 지원)
# ==============================================================================
RUN mkdir -p public/themes && \
    git clone -b feature/redmine-6-support --single-branch --depth 1 \
    https://github.com/gagnieray/PurpleMine2.git public/themes/PurpleMine2 && \
    find public/themes -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

# WBS 플러그인 빌드
RUN if [ -d plugins/redmine_wbs ]; then \
    cd plugins/redmine_wbs && \
    npm ci --no-audit --silent && \
    npm run production; \
    fi

# Bundler 설정 및 의존성 설치
RUN bundle config set --local without 'development test' && \
    bundle config set --local jobs 4 && \
    bundle install

# ==============================================================================
# Rake 태스크 (개선된 버전 - 멱등성 보장)
# ==============================================================================
RUN mkdir -p lib/tasks && cat > lib/tasks/korean_ui.rake <<'RUBY'
namespace :redmine do
  desc 'Setup Korean UI with safe checks'
  task setup_korean_ui: :environment do
    begin
      # ViewCustomize 모델이 존재하고 테이블이 있는지 확인
      if defined?(ViewCustomize)
        # 테이블 존재 여부 확인
        unless ActiveRecord::Base.connection.table_exists?('view_customizes')
          puts "⚠️  view_customizes 테이블이 아직 생성되지 않았습니다. 플러그인 마이그레이션을 먼저 실행하세요."
          next
        end
        
        # 중복 확인
        unless ViewCustomize.exists?(comments: 'KBS Korean UI v2')
          ViewCustomize.create!(
            path_pattern: '.*',
            customization_type: 'style',
            code: "body,#content{font-family:'Pretendard',sans-serif!important;letter-spacing:-0.02em;word-break:keep-all}pre,code{font-family:'D2Coding',monospace!important}",
            enabled: true,
            comments: 'KBS Korean UI v2'
          )
          puts "✅ 한국어 UI 커스터마이징 생성 완료"
        else
          puts "✅ 한국어 UI 이미 설정됨 (스킵)"
        end
      else
        puts "⚠️  ViewCustomize 플러그인이 로드되지 않았습니다."
      end
    rescue => e
      puts "⚠️  한국어 UI 설정 중 오류 발생: #{e.message}"
      puts "    (이 오류는 무시해도 Redmine은 정상 작동합니다)"
    end
  end
end
RUBY

# 디렉토리 생성 및 권한 설정
RUN mkdir -p tmp/cache tmp/pids log files public/plugin_assets /home/redmine/.bundle && \
    chown -R redmine:redmine /usr/src/redmine /usr/local/bundle /home/redmine

# ==============================================================================
# 개선된 Entrypoint (에러 핸들링 강화 + 순차 실행)
# ==============================================================================
RUN mv /docker-entrypoint.sh /docker-entrypoint-original.sh && \
    cat > /docker-entrypoint.sh <<'BASH'
#!/bin/bash
set -e

echo "======================================"
echo "🚀 Redmine Korean Edition v2.0"
echo "======================================"

# ==========================================
# [1/6] DB 연결 대기
# ==========================================
echo "[1/6] 데이터베이스 연결 대기중..."
DB_READY=0
for i in {1..60}; do
  if PGPASSWORD="$REDMINE_DB_PASSWORD" psql \
     -h "$REDMINE_DB_POSTGRES" \
     -U "$REDMINE_DB_USERNAME" \
     -d "$REDMINE_DB_DATABASE" \
     -c "SELECT 1" >/dev/null 2>&1; then
    DB_READY=1
    echo "   ✅ DB 연결 성공 (${i}초 소요)"
    break
  fi
  sleep 2
done

if [ $DB_READY -eq 0 ]; then
  echo "   ❌ DB 연결 실패 - 60초 타임아웃"
  exit 1
fi

# ==========================================
# [2/6] database.yml 생성
# ==========================================
echo "[2/6] 데이터베이스 설정 파일 생성..."
if [ ! -f config/database.yml ]; then
  cat > config/database.yml <<EOF
production:
  adapter: postgresql
  database: ${REDMINE_DB_DATABASE}
  host: ${REDMINE_DB_POSTGRES}
  username: ${REDMINE_DB_USERNAME}
  password: ${REDMINE_DB_PASSWORD}
  encoding: utf8
  pool: ${DB_POOL:-10}
EOF
  echo "   ✅ database.yml 생성 완료"
else
  echo "   ✅ database.yml 이미 존재 (스킵)"
fi

# ==========================================
# [3/6] Redmine 코어 마이그레이션
# ==========================================
echo "[3/6] Redmine 코어 마이그레이션..."
if bundle exec rake db:migrate RAILS_ENV=production 2>&1; then
  echo "   ✅ 코어 마이그레이션 완료"
else
  echo "   ❌ 코어 마이그레이션 실패"
  exit 1
fi

# ==========================================
# [4/6] 플러그인 마이그레이션
# ==========================================
echo "[4/6] 플러그인 마이그레이션..."
if bundle exec rake redmine:plugins:migrate RAILS_ENV=production 2>&1; then
  echo "   ✅ 플러그인 마이그레이션 완료"
else
  echo "   ⚠️  플러그인 마이그레이션 실패 (계속 진행)"
fi

# ==========================================
# [5/6] Asset 사전 컴파일
# ==========================================
echo "[5/6] Asset 사전 컴파일..."
if [ ! -d public/assets ] || [ -z "$(ls -A public/assets 2>/dev/null)" ]; then
  if bundle exec rake assets:precompile RAILS_ENV=production 2>&1 | grep -v "yarn install"; then
    echo "   ✅ Asset 컴파일 완료"
  else
    echo "   ⚠️  Asset 컴파일 실패 (무시하고 계속)"
  fi
else
  echo "   ✅ Asset 이미 존재 (스킵)"
fi

# ==========================================
# [6/6] 한국어 UI 설정 (안전하게 실행)
# ==========================================
echo "[6/6] 한국어 UI 커스터마이징..."
sleep 3  # 플러그인 완전 로드 대기
if bundle exec rake redmine:setup_korean_ui RAILS_ENV=production 2>&1; then
  echo "   ✅ 한국어 UI 설정 완료"
else
  echo "   ⚠️  한국어 UI 설정 실패 (수동 설정 가능)"
fi

echo "======================================"
echo "✅ 초기화 완료 - Redmine 시작"
echo "======================================"
echo ""
echo "📌 접속 정보:"
echo "   URL: http://localhost:3000"
echo "   기본 계정: admin / admin"
echo "   테마: PurpleMine2"
echo ""
echo "🔧 관리자 메뉴에서 설정:"
echo "   1. Administration > Settings > Display"
echo "   2. Theme: PurpleMine2 선택"
echo "   3. Default language: Korean (한국어) 선택"
echo ""

# Redmine 시작 (gosu로 redmine 유저로 실행)
exec gosu redmine rails server -b 0.0.0.0
BASH

RUN chmod +x /docker-entrypoint.sh

# ==============================================================================
# 개선된 헬스체크
# ==============================================================================
RUN cat > /healthcheck.sh <<'BASH'
#!/bin/bash
# HTTP 응답 확인
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/login)
if [ "$HTTP_CODE" = "200" ]; then
  exit 0
else
  exit 1
fi
BASH

RUN chmod +x /healthcheck.sh

EXPOSE 3000
ENTRYPOINT ["/docker-entrypoint.sh"]
