# ==============================================================================
# Redmine 6.1.1 Production (Easypanel 최적화)
# ==============================================================================
FROM redmine:6.1.1

# 메타 정보
LABEL maintainer="your-email@example.com"
LABEL redmine.version="6.1.1"
LABEL easypanel.managed="true"

USER root

# ==============================================================================
# [STAGE 1] 시스템 패키지 (캐시 레이어 최적화)
# ==============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # 로케일 + 타임존
    locales locales-all tzdata \
    # 폰트
    fonts-nanum fontconfig \
    # 빌드 도구
    build-essential libpq-dev pkg-config \
    # Node.js (플러그인용)
    nodejs npm \
    # 유틸리티
    git curl unzip wget \
    # PDF 생성
    ghostscript libyaml-dev \
    && rm -rf /var/lib/apt/lists/*

# ==============================================================================
# [STAGE 2] 한글 폰트 설치 (버전 고정 + 캐시 활용)
# ==============================================================================
RUN mkdir -p /usr/share/fonts/truetype/custom && \
    cd /usr/share/fonts/truetype/custom && \
    # Pretendard v1.3.9 (가변 폰트)
    curl -fsSL -o pretendard.zip \
      https://github.com/orioncactus/pretendard/releases/download/v1.3.9/Pretendard-1.3.9.zip && \
    unzip -q pretendard.zip -d Pretendard && \
    # D2Coding v1.3.2 (코드 폰트)
    curl -fsSL -o d2coding.zip \
      https://github.com/naver/d2codingfont/releases/download/VER1.3.2/D2Coding-Ver1.3.2-20180524.zip && \
    unzip -q d2coding.zip -d D2Coding && \
    # Spoqa Han Sans v3.0.0 (본문 폰트)
    curl -fsSL -o spoqa.zip \
      https://github.com/spoqa/spoqa-han-sans/releases/download/v3.0.0/SpoqaHanSansNeo_all.zip && \
    unzip -q spoqa.zip -d Spoqa && \
    # 정리 및 캐시 갱신
    rm -f *.zip && \
    fc-cache -f -v

# ==============================================================================
# [STAGE 3] PDF 폰트 링크 설정
# ==============================================================================
WORKDIR /usr/src/redmine
RUN mkdir -p public/fonts && \
    ln -sf /usr/share/fonts/truetype/nanum/NanumGothic.ttf \
           public/fonts/NanumGothic.ttf && \
    ln -sf /usr/share/fonts/truetype/custom/Pretendard/public/static/Pretendard-Regular.otf \
           public/fonts/Pretendard.otf

# ==============================================================================
# [STAGE 4] 환경 변수 설정
# ==============================================================================
ENV LANG=ko_KR.UTF-8 \
    LC_ALL=ko_KR.UTF-8 \
    TZ=Asia/Seoul \
    RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=1 \
    RAILS_SERVE_STATIC_FILES=true \
    GEM_HOME=/usr/local/bundle \
    BUNDLE_PATH=/usr/local/bundle

# ==============================================================================
# [STAGE 5] Redmine 용어 현지화 (일감 → 이슈)
# ==============================================================================
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml && \
    sed -i 's/새 일감/새 이슈/g' config/locales/ko.yml

# ==============================================================================
# [STAGE 6] 플러그인 설치 (버전 고정 + 태그 검증)
# ==============================================================================
RUN git clone --depth 1 --branch 3.0.1 \
      https://github.com/onozaty/redmine-view-customize.git \
      plugins/view_customize && \
    git clone --depth 1 --branch 2.1.0 \
      https://github.com/eXolnet/redmine_wbs.git \
      plugins/redmine_wbs && \
    git clone --depth 1 --branch 1.2.0 \
      https://github.com/akiko-pusu/redmine_issue_templates.git \
      plugins/redmine_issue_templates && \
    # Git 히스토리 제거 (용량 절감)
    find plugins -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

# ==============================================================================
# [STAGE 7] UI 커스터마이징 (Rails Initializer 방식)
# ==============================================================================
RUN mkdir -p config/initializers && \
    cat > config/initializers/zz_custom_ui.rb <<'RUBY'
# KBS Production UI Customization
# 파일명 zz_로 시작 → 다른 initializer 이후 실행 보장

Rails.application.config.after_initialize do
  # ViewCustomize 플러그인이 로드된 경우에만 실행
  if defined?(ViewCustomize)
    # 멱등성 보장: 동일 설정이 없을 때만 생성
    unless ViewCustomize.exists?(
      path_pattern: '.*',
      comments: 'KBS Production UI v2'
    )
      ViewCustomize.create!(
        path_pattern: '.*',
        customization_type: 'style',
        code: <<~CSS,
          /* 기본 폰트: Pretendard */
          body, #content, #header, #footer,
          #main-menu, #sidebar, .wiki {
            font-family: 'Pretendard Variable', 'Pretendard', -apple-system, BlinkMacSystemFont, sans-serif !important;
          }

          /* 제목 폰트: Pretendard SemiBold */
          h1, h2, h3, h4, h5, h6,
          .subject a, .title {
            font-family: 'Pretendard Variable', sans-serif !important;
            font-weight: 600;
          }

          /* 코드 폰트: D2Coding */
          pre, code, tt, kbd, samp,
          .wiki-code, .CodeMirror,
          textarea[data-auto-complete],
          .autoscroll {
            font-family: 'D2Coding', 'Consolas', 'Monaco', monospace !important;
            font-size: 13px;
            line-height: 1.6;
          }

          /* 한글 가독성 개선 */
          body {
            letter-spacing: -0.02em;
            word-break: keep-all;
          }
        CSS
        enabled: true,
        comments: 'KBS Production UI v2'
      )
      
      Rails.logger.info '✓ [INIT] UI Customization created successfully'
    else
      Rails.logger.info '✓ [INIT] UI Customization already exists (skip)'
    end
  else
    Rails.logger.warn '⚠ [INIT] ViewCustomize plugin not found (skip UI injection)'
  end
end
RUBY

# ==============================================================================
# [STAGE 8] Database.yml Connection Pool 최적화
# ==============================================================================
RUN sed -i '/production:/a\  pool: <%= ENV.fetch("DB_POOL") { 10 } %>' \
    config/database.yml

# ==============================================================================
# [STAGE 9] 디렉토리 준비 + 권한 설정
# ==============================================================================
RUN mkdir -p \
    tmp/cache tmp/pids tmp/sockets \
    log files plugins/assets \
    public/plugin_assets && \
    chown -R redmine:redmine \
      /usr/src/redmine \
      /usr/local/bundle

# ==============================================================================
# [STAGE 10] Gem 의존성 설치 (redmine 유저로 전환)
# ==============================================================================
USER redmine

# WBS 플러그인 빌드 (Dockerfile에서만 실행)
RUN if [ -d plugins/redmine_wbs ]; then \
      cd plugins/redmine_wbs && \
      npm ci --production --no-audit && \
      npm run production && \
      cd ../..; \
    fi

# Bundler 설정 + Gem 설치
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle config set --local jobs 4 && \
    bundle install --quiet

# ==============================================================================
# [STAGE 11] Entrypoint 스크립트 (멱등성 보장)
# ==============================================================================
USER root
RUN cat > /docker-entrypoint-custom.sh <<'BASH'
#!/bin/bash
set -e

echo "======================================"
echo "Redmine Initialization (Easypanel)"
echo "Time: $(date)"
echo "======================================"

# 1. 데이터베이스 마이그레이션
echo "[1/4] Running database migration..."
bundle exec rake db:migrate RAILS_ENV=production

# 2. 플러그인 마이그레이션
echo "[2/4] Running plugin migration..."
bundle exec rake redmine:plugins:migrate RAILS_ENV=production

# 3. Asset Precompile (변경 시에만)
if [ ! -d tmp/cache/assets ] || [ -z "$(ls -A tmp/cache/assets)" ]; then
  echo "[3/4] Precompiling assets..."
  bundle exec rake assets:precompile RAILS_ENV=production
else
  echo "[3/4] Assets already compiled (skip)"
fi

# 4. 권한 확인
echo "[4/4] Verifying permissions..."
chown -R redmine:redmine files log tmp public/plugin_assets 2>/dev/null || true

echo "======================================"
echo "✓ Initialization Complete"
echo "Starting Redmine server..."
echo "======================================"

# Redmine 유저로 전환 후 서버 실행
exec gosu redmine "$@"
BASH

RUN chmod +x /docker-entrypoint-custom.sh && \
    apt-get update && apt-get install -y --no-install-recommends gosu && \
    rm -rf /var/lib/apt/lists/*

# ==============================================================================
# [STAGE 12] 헬스체크 스크립트
# ==============================================================================
RUN cat > /healthcheck.sh <<'BASH'
#!/bin/bash
# Redmine 로그인 페이지가 200 OK를 반환하는지 확인
curl -f -s -o /dev/null -w "%{http_code}" http://localhost:3000/login | grep -q "200" || exit 1
BASH

RUN chmod +x /healthcheck.sh && \
    apt-get update && apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

# ==============================================================================
# [최종] 보안 설정 + 기본 명령어
# ==============================================================================
USER redmine
EXPOSE 3000

ENTRYPOINT ["/docker-entrypoint-custom.sh"]
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
