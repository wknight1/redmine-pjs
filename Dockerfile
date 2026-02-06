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
# STAGE 2: Redmine 6.1.1 + 완전 자동화
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
    && rm -rf /var/lib/apt/lists/* && \
    sed -i '/ko_KR.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen ko_KR.UTF-8

# 한글 폰트
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

# PDF 폰트
RUN mkdir -p public/fonts && \
    ln -sf /usr/share/fonts/truetype/nanum/NanumGothic.ttf public/fonts/NanumGothic.ttf

# 용어 현지화
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml

# 플러그인 설치
RUN git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize && \
    git clone --depth 1 https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs && \
    git clone --depth 1 https://github.com/akiko-pusu/redmine_issue_templates.git plugins/redmine_issue_templates && \
    find plugins -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

# Rake 태스크
RUN mkdir -p lib/tasks && cat > lib/tasks/korean_ui.rake <<'RUBY'
namespace :redmine do
  desc 'Setup Korean UI (멱등성 보장)'
  task setup_korean_ui: :environment do
    if defined?(ViewCustomize) && ViewCustomize.table_exists?
      unless ViewCustomize.exists?(comments: 'KBS Korean UI v2')
        ViewCustomize.create!(
          path_pattern: '.*',
          customization_type: 'style',
          code: "body,#content{font-family:'Pretendard',sans-serif!important;letter-spacing:-0.02em;word-break:keep-all}pre,code{font-family:'D2Coding',monospace!important}",
          enabled: true,
          comments: 'KBS Korean UI v2'
        )
        puts "✓ 한국어 UI 생성 완료"
      else
        puts "✓ 한국어 UI 이미 설정됨"
      end
    else
      puts "⚠ ViewCustomize 플러그인 미설치 또는 마이그레이션 필요"
    end
  end
end
RUBY

# 디렉토리
RUN mkdir -p tmp/cache tmp/pids log files plugins/assets public/plugin_assets /home/redmine/.bundle

# WBS 빌드
RUN if [ -d plugins/redmine_wbs ]; then cd plugins/redmine_wbs && npm ci --no-audit --silent && npm run production; fi

# Bundler
RUN bundle config set --local without 'development test' && \
    bundle config set --local jobs 4 && \
    bundle install

# 권한
RUN chown -R redmine:redmine /usr/src/redmine /usr/local/bundle /home/redmine

# ★ 개선된 Entrypoint (위 코드 삽입)
RUN mv /docker-entrypoint.sh /docker-entrypoint-original.sh && \
    cat > /docker-entrypoint.sh <<'BASH'
#!/bin/bash
set -e

echo "======================================"
echo "🚀 Redmine Korean Edition"
echo "======================================"

# DB 대기
echo "[1/5] DB 대기..."
for i in {1..60}; do
  PGPASSWORD="$REDMINE_DB_PASSWORD" psql -h "$REDMINE_DB_POSTGRES" \
    -U "$REDMINE_DB_USERNAME" -d "$REDMINE_DB_DATABASE" -c "SELECT 1" >/dev/null 2>&1 && break
  sleep 2
done

# database.yml 생성
echo "[2/5] DB 설정..."
[ ! -f config/database.yml ] && cat > config/database.yml <<EOF
production:
  adapter: postgresql
  database: ${REDMINE_DB_DATABASE}
  host: ${REDMINE_DB_POSTGRES}
  username: ${REDMINE_DB_USERNAME}
  password: ${REDMINE_DB_PASSWORD}
  encoding: utf8
EOF

# 마이그레이션
echo "[3/5] Redmine 마이그레이션..."
bundle exec rake db:migrate RAILS_ENV=production

echo "[4/5] 플러그인 마이그레이션..."
bundle exec rake redmine:plugins:migrate RAILS_ENV=production

# Asset (필요시)
[ ! -d tmp/cache/assets ] && bundle exec rake assets:precompile RAILS_ENV=production 2>/dev/null || true

# UI 설정
echo "[5/5] 한국어 UI..."
sleep 2
bundle exec rake redmine:setup_korean_ui RAILS_ENV=production 2>&1 || true

echo "✅ 초기화 완료"
echo "======================================"

exec gosu redmine rails server -b 0.0.0.0
BASH

RUN chmod +x /docker-entrypoint.sh

# 헬스체크
RUN echo '#!/bin/bash\ncurl -f -s http://localhost:3000/login >/dev/null' > /healthcheck.sh && chmod +x /healthcheck.sh

EXPOSE 3000
ENTRYPOINT ["/docker-entrypoint.sh"]
