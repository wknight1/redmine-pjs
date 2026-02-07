# ==============================================================================
# Redmine 6.1.1 Korean Pro Edition v1.0.2
# ==============================================================================

FROM redmine:6.1.1

USER root

# 시스템 패키지
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
    ln -sf /usr/share/fonts/truetype/nanum/NanumGothic.ttf public/fonts/NanumGothic.ttf && \
    ln -sf /usr/share/fonts/truetype/nanum/NanumGothicBold.ttf public/fonts/NanumGothicBold.ttf

# 용어 현지화
RUN if [ -f config/locales/ko.yml ]; then sed -i 's/일감/이슈/g' config/locales/ko.yml; fi

# 플러그인
RUN mkdir -p plugins && \
    git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize && \
    git clone --depth 1 -b master https://github.com/alphanodes/additionals.git plugins/additionals && \
    git clone --depth 1 https://github.com/akiko-pusu/redmine_banner.git plugins/redmine_banner && \
    git clone --depth 1 https://github.com/paginagmbh/redmine_lightbox2.git plugins/redmine_lightbox2 && \
    git clone --depth 1 https://github.com/AlphaNodes/redmine_collapsible_sidebar.git plugins/redmine_collapsible_sidebar && \
    find plugins -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

# 테마
RUN mkdir -p public/themes && \
    git clone -b feature/redmine-6-support --single-branch --depth 1 \
    https://github.com/gagnieray/PurpleMine2.git public/themes/PurpleMine2 && \
    git clone --depth 1 https://github.com/redmineup/circle_theme.git public/themes/circle && \
    find public/themes -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

# Bundle
RUN bundle config set --local without 'development test' && \
    bundle config set --local jobs 4 && \
    bundle install

# 권한
RUN mkdir -p tmp/cache tmp/pids log files public/plugin_assets /home/redmine/.bundle && \
    chown -R redmine:redmine /usr/src/redmine /usr/local/bundle /home/redmine

# Entrypoint (핵심: DB 커넥션 풀 최적화)
RUN mv /docker-entrypoint.sh /docker-entrypoint-original.sh && \
    cat > /docker-entrypoint.sh <<'BASH'
#!/bin/bash
set -e

echo "======================================"
echo "🚀 Redmine Korean Pro v1.0.2"
echo "======================================"

# [1/8] DB 연결 대기
echo "[1/8] DB 연결 확인..."
for i in {1..60}; do
  if PGPASSWORD="$REDMINE_DB_PASSWORD" psql -h "$REDMINE_DB_POSTGRES" \
     -U "$REDMINE_DB_USERNAME" -d "$REDMINE_DB_DATABASE" -c "SELECT 1" >/dev/null 2>&1; then
    echo "   ✅ DB 연결 성공 (${i}초)"
    break
  fi
  sleep 2
done

# [2/8] database.yml (커넥션 풀 증가)
echo "[2/8] DB 설정..."
cat > config/database.yml <<EOF
production:
  adapter: postgresql
  database: ${REDMINE_DB_DATABASE}
  host: ${REDMINE_DB_POSTGRES}
  username: ${REDMINE_DB_USERNAME}
  password: ${REDMINE_DB_PASSWORD}
  encoding: utf8
  pool: 25
  timeout: 10000
  connect_timeout: 10
  checkout_timeout: 10
EOF
echo "   ✅ Pool: 25 (기존 20)"

# [3/8] Secret token
echo "[3/8] Secret token..."
bundle exec rake generate_secret_token RAILS_ENV=production 2>&1 >/dev/null || true
echo "   ✅ 완료"

# [4/8] 코어 마이그레이션
echo "[4/8] 코어 마이그레이션..."
if bundle exec rake db:migrate RAILS_ENV=production 2>&1 >/dev/null; then
  echo "   ✅ 성공"
else
  echo "   ❌ 실패"
  exit 1
fi

# [5/8] 플러그인 마이그레이션
echo "[5/8] 플러그인 마이그레이션..."
if bundle exec rake redmine:plugins:migrate RAILS_ENV=production 2>&1 >/dev/null; then
  echo "   ✅ 성공"
else
  echo "   ⚠️  실패 (계속)"
fi

# [6/8] 기본 데이터
echo "[6/8] 기본 데이터..."
if [ ! -f /usr/src/redmine/files/.initialized ]; then
  bundle exec rake redmine:load_default_data REDMINE_LANG=ko RAILS_ENV=production 2>&1 >/dev/null || true
  touch /usr/src/redmine/files/.initialized
  echo "   ✅ 로드 완료"
else
  echo "   ✅ 스킵"
fi

# [7/8] Asset
echo "[7/8] Asset 컴파일..."
if [ ! -d public/assets ] || [ -z "$(ls -A public/assets 2>/dev/null)" ]; then
  bundle exec rake assets:precompile RAILS_ENV=production 2>&1 >/dev/null || true
  echo "   ✅ 완료"
else
  echo "   ✅ 스킵"
fi

# [8/8] 한국어 UI (Rails runner 사용)
echo "[8/8] 한국어 설정..."
sleep 2

bundle exec rails runner -e production <<'RUBY' 2>&1 || true
begin
  if defined?(ViewCustomize) && ActiveRecord::Base.connection.table_exists?('view_customizes')
    unless ViewCustomize.exists?(comments: 'Korean UI Pro')
      css_code = <<~CSS
        body, #content, .wiki, input, select, textarea, button {
          font-family: 'Pretendard', -apple-system, sans-serif !important;
          letter-spacing: -0.02em;
          word-break: keep-all;
        }
        pre, code, .CodeMirror, tt, .wiki pre {
          font-family: 'D2Coding', Consolas, monospace !important;
        }
        body { font-size: 14px; line-height: 1.6; }
        h1, h2, h3, h4, h5, h6 { font-weight: 600; }
        .button, input[type="button"], input[type="submit"] {
          border-radius: 4px;
          transition: all 0.2s;
        }
      CSS
      
      ViewCustomize.create!(
        path_pattern: '.*',
        customization_type: 'style',
        code: css_code,
        enabled: true,
        comments: 'Korean UI Pro'
      )
      puts "✅ 한국어 UI 생성"
    else
      puts "✅ 한국어 UI 존재"
    end
  end
  
  Setting.default_language = 'ko' rescue nil
  Setting.ui_theme = 'PurpleMine2' rescue nil
  puts "✅ 기본 설정 완료"
rescue => e
  puts "⚠️ #{e.message}"
end
RUBY

echo "   ✅ 완료"

echo "======================================"
echo "✅ 초기화 완료"
echo "======================================"

exec gosu redmine rails server -b 0.0.0.0
BASH

RUN chmod +x /docker-entrypoint.sh

EXPOSE 3000
ENTRYPOINT ["/docker-entrypoint.sh"]
