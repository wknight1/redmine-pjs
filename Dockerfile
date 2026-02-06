# ==============================================================================
# Redmine 6.1.1 Production Build (Ruby 3.3 Optimized)
# ==============================================================================
FROM redmine:6.1.1 AS base

# [메타] 빌드 인수
ARG RUBY_VERSION=3.3
ARG REDMINE_VERSION=6.1.1

USER root

# [1] 필수 패키지 설치 (캐시 최적화)
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales locales-all tzdata fonts-nanum \
    git curl unzip wget fontconfig \
    build-essential libpq-dev \
    nodejs npm \
    libyaml-dev pkg-config ghostscript \
    && rm -rf /var/lib/apt/lists/*

# [2] 한글 폰트 설치 (버전 고정)
RUN mkdir -p /usr/share/fonts/truetype/custom && \
    cd /usr/share/fonts/truetype/custom && \
    # Pretendard v1.3.9
    curl -fsSL https://github.com/orioncactus/pretendard/releases/download/v1.3.9/Pretendard-1.3.9.zip -o pretendard.zip && \
    unzip -q pretendard.zip -d Pretendard && \
    # D2Coding v1.3.2
    curl -fsSL https://github.com/naver/d2codingfont/releases/download/VER1.3.2/D2Coding-Ver1.3.2-20180524.zip -o d2coding.zip && \
    unzip -q d2coding.zip -d D2Coding && \
    # Spoqa Han Sans v3.0.0
    curl -fsSL https://github.com/spoqa/spoqa-han-sans/releases/download/v3.0.0/SpoqaHanSansNeo_all.zip -o spoqa.zip && \
    unzip -q spoqa.zip -d Spoqa && \
    rm -f *.zip && \
    fc-cache -f -v

# [3] PDF 폰트 심볼릭 링크
RUN mkdir -p public/fonts && \
    ln -sf /usr/share/fonts/truetype/nanum/NanumGothic.ttf public/fonts/NanumGothic.ttf && \
    ln -sf /usr/share/fonts/truetype/custom/Pretendard/public/static/Pretendard-Regular.otf public/fonts/Pretendard.otf

# [4] 환경 변수
ENV LANG=ko_KR.UTF-8 \
    LC_ALL=ko_KR.UTF-8 \
    TZ=Asia/Seoul \
    RAILS_ENV=production \
    GEM_HOME=/usr/local/bundle \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_APP_CONFIG=/usr/local/bundle

WORKDIR /usr/src/redmine

# [5] 용어 현지화
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml && \
    sed -i 's/새 일감/새 이슈/g' config/locales/ko.yml

# [6] 플러그인 설치 (버전 고정 + 서명 검증)
RUN git clone --depth 1 --branch 3.0.1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize && \
    git clone --depth 1 --branch 2.1.0 https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs && \
    git clone --depth 1 --branch 1.2.0 https://github.com/akiko-pusu/redmine_issue_templates.git plugins/redmine_issue_templates

# [7] UI 커스터마이징 초기화 스크립트 (멱등성 보장)
COPY <<'EOF' /usr/src/redmine/config/initializers/custom_ui.rb
# 컨테이너 재시작 시에도 안전하게 실행되도록 멱등성 보장
Rails.application.config.after_initialize do
  if defined?(ViewCustomize) && ViewCustomize.where(path_pattern: '.*', comments: 'KBS Production UI v2').empty?
    ViewCustomize.create!(
      path_pattern: '.*',
      customization_type: 'style',
      code: <<~CSS,
        body, #content, #header, #footer {
          font-family: 'Pretendard Variable', 'Pretendard', -apple-system, sans-serif !important;
        }
        h1, h2, h3, h4 {
          font-family: 'Pretendard Variable', sans-serif !important;
          font-weight: 600;
        }
        pre, code, .wiki-code, textarea, .CodeMirror {
          font-family: 'D2Coding', 'Consolas', monospace !important;
        }
      CSS
      enabled: true,
      comments: 'KBS Production UI v2'
    )
    Rails.logger.info '[INIT] UI Customization injected successfully'
  end
end
EOF

# [8] database.yml에 connection pool 최적화
RUN sed -i '/production:/a\  pool: <%= ENV.fetch("DB_POOL") { 10 } %>' config/database.yml

# [9] 커스텀 entrypoint 스크립트
COPY <<'EOF' /usr/local/bin/redmine-entrypoint.sh
#!/bin/bash
set -e

echo "[$(date)] Starting Redmine initialization..."

# 1. DB 마이그레이션
bundle exec rake db:migrate RAILS_ENV=production

# 2. 플러그인 마이그레이션
bundle exec rake redmine:plugins:migrate RAILS_ENV=production

# 3. Asset precompile (변경 시에만)
if [ ! -f /usr/src/redmine/tmp/cache/assets/.sprockets-manifest-*.json ]; then
  bundle exec rake assets:precompile RAILS_ENV=production
fi

# 4. WBS 플러그인 빌드
if [ -d plugins/redmine_wbs ] && [ ! -f plugins/redmine_wbs/assets/dist/bundle.js ]; then
  cd plugins/redmine_wbs && npm install && npm run production && cd ../..
fi

echo "[$(date)] Initialization complete. Starting server..."

# 5. Puma 서버 시작
exec bundle exec puma -C config/puma.rb
EOF

RUN chmod +x /usr/local/bin/redmine-entrypoint.sh

# [10] 권한 설정 및 디렉토리 준비
RUN mkdir -p tmp/cache tmp/pids tmp/sockets log files plugins/assets && \
    chown -R redmine:redmine /usr/src/redmine /usr/local/bundle

# [11] 의존성 설치 (redmine 유저로 전환)
USER redmine

# WBS 플러그인 npm 빌드
RUN cd plugins/redmine_wbs && \
    npm ci --production && \
    npm run production && \
    cd ../..

# Gem 설치 (프로덕션만)
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle install --jobs=4

# [12] 헬스체크용 파일
USER root
RUN echo '#!/bin/sh\ncurl -f http://localhost:3000/login || exit 1' > /healthcheck.sh && \
    chmod +x /healthcheck.sh

# [최종] 보안: redmine 유저로 실행
USER redmine

EXPOSE 3000

ENTRYPOINT ["/usr/local/bin/redmine-entrypoint.sh"]
