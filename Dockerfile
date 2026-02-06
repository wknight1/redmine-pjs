# ==============================================================================
# Redmine 6.1.1 Production (Easypanel + 한국어 완전 최적화)
# ==============================================================================
FROM redmine:6.1.1

LABEL maintainer="admin@yourcompany.com"
LABEL redmine.version="6.1.1"
LABEL locale="ko_KR.UTF-8"

USER root

# ==============================================================================
# [1] 시스템 패키지 + 한글 로케일
# ==============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales locales-all tzdata \
    fonts-nanum fonts-noto-cjk fonts-noto-cjk-extra fontconfig \
    build-essential libpq-dev pkg-config \
    nodejs npm \
    git curl unzip wget \
    ghostscript libyaml-dev \
    && rm -rf /var/lib/apt/lists/*

# 한글 로케일 생성 및 활성화
RUN sed -i '/ko_KR.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen ko_KR.UTF-8 && \
    update-locale LANG=ko_KR.UTF-8

# ==============================================================================
# [2] 한글 폰트 3종 설치 (버전 고정)
# ==============================================================================
RUN mkdir -p /usr/share/fonts/truetype/custom && \
    cd /usr/share/fonts/truetype/custom && \
    # Pretendard v1.3.9
    curl -fsSL -o pretendard.zip \
      https://github.com/orioncactus/pretendard/releases/download/v1.3.9/Pretendard-1.3.9.zip && \
    unzip -q pretendard.zip -d Pretendard && \
    # D2Coding v1.3.2
    curl -fsSL -o d2coding.zip \
      https://github.com/naver/d2codingfont/releases/download/VER1.3.2/D2Coding-Ver1.3.2-20180524.zip && \
    unzip -q d2coding.zip -d D2Coding && \
    # Spoqa Han Sans v3.0.0
    curl -fsSL -o spoqa.zip \
      https://github.com/spoqa/spoqa-han-sans/releases/download/v3.0.0/SpoqaHanSansNeo_all.zip && \
    unzip -q spoqa.zip -d Spoqa && \
    rm -f *.zip && \
    fc-cache -f -v

# ==============================================================================
# [3] 환경 변수 (한국 표준시 + UTF-8)
# ==============================================================================
ENV LANG=ko_KR.UTF-8 \
    LC_ALL=ko_KR.UTF-8 \
    LANGUAGE=ko_KR:ko \
    TZ=Asia/Seoul \
    RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=1 \
    RAILS_SERVE_STATIC_FILES=true

WORKDIR /usr/src/redmine

# ==============================================================================
# [4] PDF 폰트 링크 (한글 렌더링)
# ==============================================================================
RUN mkdir -p public/fonts && \
    ln -sf /usr/share/fonts/truetype/nanum/NanumGothic.ttf \
           public/fonts/NanumGothic.ttf && \
    ln -sf /usr/share/fonts/truetype/custom/Pretendard/public/static/Pretendard-Regular.otf \
           public/fonts/Pretendard.otf

# ==============================================================================
# [5] 용어 현지화 (일감 → 이슈)
# ==============================================================================
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml && \
    sed -i 's/새 일감/새 이슈/g' config/locales/ko.yml && \
    sed -i 's/하위 일감/하위 이슈/g' config/locales/ko.yml && \
    sed -i 's/상위 일감/상위 이슈/g' config/locales/ko.yml && \
    sed -i 's/관련 일감/관련 이슈/g' config/locales/ko.yml

# ==============================================================================
# [6] 플러그인 설치 (★ 실제 존재하는 버전으로 수정)
# ==============================================================================
RUN git clone --depth 1 \
      https://github.com/onozaty/redmine-view-customize.git \
      plugins/view_customize && \
    git clone --depth 1 \
      https://github.com/eXolnet/redmine_wbs.git \
      plugins/redmine_wbs && \
    git clone --depth 1 \
      https://github.com/akiko-pusu/redmine_issue_templates.git \
      plugins/redmine_issue_templates && \
    find plugins -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

# ==============================================================================
# [7] UI 커스터마이징 (Rails Initializer)
# ==============================================================================
RUN mkdir -p config/initializers && \
    cat > config/initializers/zz_custom_ui.rb <<'RUBY'
# KBS Production UI - 한국어 폰트 최적화
Rails.application.config.after_initialize do
  if defined?(ViewCustomize)
    unless ViewCustomize.exists?(comments: 'KBS Korean UI v2')
      ViewCustomize.create!(
        path_pattern: '.*',
        customization_type: 'style',
        code: <<~CSS,
          /* 한글 최적화 폰트 스택 */
          body, #content, #header, #footer,
          #main-menu, #sidebar, .wiki, p, div, span {
            font-family: 'Pretendard Variable', 'Pretendard', 'Noto Sans KR', -apple-system, sans-serif !important;
            letter-spacing: -0.02em;
            word-break: keep-all;
            word-wrap: break-word;
          }

          /* 제목 폰트 */
          h1, h2, h3, h4, h5, h6, .subject a, .title {
            font-family: 'Pretendard Variable', 'Noto Sans KR', sans-serif !important;
            font-weight: 600;
          }

          /* 코드 블록 - 고정폭 한글 폰트 */
          pre, code, tt, kbd, samp,
          .wiki-code, .CodeMirror, textarea[data-auto-complete] {
            font-family: 'D2Coding', 'Noto Sans Mono CJK KR', monospace !important;
            font-size: 13px;
            line-height: 1.6;
          }

          /* 한글 가독성 향상 */
          .wiki p, .wiki li, .journal .wiki {
            line-height: 1.8;
          }

          /* 테이블 헤더 */
          table.list th {
            font-weight: 600;
          }
        CSS
        enabled: true,
        comments: 'KBS Korean UI v2'
      )
      Rails.logger.info '✓ [UI] Korean font optimization applied'
    end
  end
end
RUBY

# ==============================================================================
# [8] Database Pool 설정 (★ 수정: database.yml.example 사용)
# ==============================================================================
RUN if [ -f config/database.yml.example ]; then \
      cp config/database.yml.example config/database.yml.template && \
      sed -i '/production:/a\  pool: <%= ENV.fetch("DB_POOL") { 10 } %>' \
        config/database.yml.template; \
    fi

# ==============================================================================
# [9] 디렉토리 준비 + 권한
# ==============================================================================
RUN mkdir -p \
    tmp/cache tmp/pids tmp/sockets \
    log files plugins/assets public/plugin_assets && \
    chown -R redmine:redmine /usr/src/redmine /usr/local/bundle

# ==============================================================================
# [10] Gem + NPM 설치 (redmine 유저)
# ==============================================================================
USER redmine

# WBS 플러그인 빌드
RUN if [ -d plugins/redmine_wbs ]; then \
      cd plugins/redmine_wbs && \
      npm ci --production --no-audit && \
      npm run production && \
      cd ../..; \
    fi

# Bundler 설정
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle config set --local jobs 4 && \
    bundle install --quiet

# ==============================================================================
# [11] Entrypoint 스크립트 (멱등성 + 한국어 메시지)
# ==============================================================================
USER root
RUN cat > /docker-entrypoint-custom.sh <<'BASH'
#!/bin/bash
set -e

echo "======================================"
echo "Redmine 초기화 시작"
echo "시간: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "======================================"

# 1. DB 마이그레이션
echo "[1/4] 데이터베이스 마이그레이션 중..."
bundle exec rake db:migrate RAILS_ENV=production

# 2. 플러그인 마이그레이션
echo "[2/4] 플러그인 마이그레이션 중..."
bundle exec rake redmine:plugins:migrate RAILS_ENV=production

# 3. Asset Precompile
if [ ! -d tmp/cache/assets ] || [ -z "$(ls -A tmp/cache/assets 2>/dev/null)" ]; then
  echo "[3/4] 에셋 컴파일 중..."
  bundle exec rake assets:precompile RAILS_ENV=production
else
  echo "[3/4] 에셋 이미 컴파일됨 (건너뜀)"
fi

# 4. 권한 확인
echo "[4/4] 파일 권한 확인 중..."
chown -R redmine:redmine files log tmp public/plugin_assets 2>/dev/null || true

echo "======================================"
echo "✓ 초기화 완료"
echo "Redmine 서버 시작 중..."
echo "======================================"

# Redmine 유저로 전환 후 실행
exec gosu redmine "$@"
BASH

RUN chmod +x /docker-entrypoint-custom.sh && \
    apt-get update && apt-get install -y --no-install-recommends gosu curl && \
    rm -rf /var/lib/apt/lists/*

# ==============================================================================
# [12] 헬스체크
# ==============================================================================
RUN echo '#!/bin/bash\ncurl -f -s http://localhost:3000/login > /dev/null || exit 1' \
    > /healthcheck.sh && chmod +x /healthcheck.sh

# ==============================================================================
# [최종] 보안 + 실행
# ==============================================================================
USER redmine
EXPOSE 3000

ENTRYPOINT ["/docker-entrypoint-custom.sh"]
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
