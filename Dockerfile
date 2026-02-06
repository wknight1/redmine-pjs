# ==============================================================================
# STAGE 1: PostgreSQL 18.1 + 한국어 로케일
# ==============================================================================
FROM postgres:18.1 AS database

USER root

# 한국어 로케일 패키지 설치
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales \
    && rm -rf /var/lib/apt/lists/*

# ko_KR.UTF-8 로케일 생성
RUN sed -i '/ko_KR.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen ko_KR.UTF-8 && \
    update-locale LANG=ko_KR.UTF-8

# 환경 변수 설정
ENV LANG=ko_KR.UTF-8 \
    LC_ALL=ko_KR.UTF-8 \
    LANGUAGE=ko_KR:ko \
    TZ=Asia/Seoul

# ==============================================================================
# STAGE 2: Redmine 6.1.1 + 한국어 완전 최적화
# ==============================================================================
FROM redmine:6.1.1 AS application

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
# [2] 한글 폰트 설치
# ==============================================================================
RUN mkdir -p /usr/share/fonts/truetype/custom && \
    cd /usr/share/fonts/truetype/custom && \
    curl -fsSL -o pretendard.zip \
      https://github.com/orioncactus/pretendard/releases/download/v1.3.9/Pretendard-1.3.9.zip && \
    unzip -q pretendard.zip -d Pretendard && \
    curl -fsSL -o d2coding.zip \
      https://github.com/naver/d2codingfont/releases/download/VER1.3.2/D2Coding-Ver1.3.2-20180524.zip && \
    unzip -q d2coding.zip -d D2Coding && \
    curl -fsSL -o spoqa.zip \
      https://github.com/spoqa/spoqa-han-sans/releases/download/v3.0.0/SpoqaHanSansNeo_all.zip && \
    unzip -q spoqa.zip -d Spoqa && \
    rm -f *.zip && \
    fc-cache -f -v

# ==============================================================================
# [3] 환경 변수
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
# [4] PDF 폰트 링크
# ==============================================================================
RUN mkdir -p public/fonts && \
    ln -sf /usr/share/fonts/truetype/nanum/NanumGothic.ttf \
           public/fonts/NanumGothic.ttf && \
    ln -sf /usr/share/fonts/truetype/custom/Pretendard/public/static/Pretendard-Regular.otf \
           public/fonts/Pretendard.otf

# ==============================================================================
# [5] 용어 현지화
# ==============================================================================
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml && \
    sed -i 's/새 일감/새 이슈/g' config/locales/ko.yml && \
    sed -i 's/하위 일감/하위 이슈/g' config/locales/ko.yml && \
    sed -i 's/상위 일감/상위 이슈/g' config/locales/ko.yml && \
    sed -i 's/관련 일감/관련 이슈/g' config/locales/ko.yml

# ==============================================================================
# [6] 플러그인 설치
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
# [7] UI 커스터마이징
# ==============================================================================
RUN cat > config/initializers/zz_custom_ui.rb <<'RUBY'
# KBS Production UI - 한국어 폰트 최적화
Rails.application.config.after_initialize do
  if defined?(ViewCustomize)
    unless ViewCustomize.exists?(comments: 'KBS Korean UI v2')
      ViewCustomize.create!(
        path_pattern: '.*',
        customization_type: 'style',
        code: <<~CSS,
          body, #content, #header, #footer,
          #main-menu, #sidebar, .wiki, p, div, span {
            font-family: 'Pretendard Variable', 'Pretendard', 'Noto Sans KR', -apple-system, sans-serif !important;
            letter-spacing: -0.02em;
            word-break: keep-all;
            word-wrap: break-word;
          }

          h1, h2, h3, h4, h5, h6, .subject a, .title {
            font-family: 'Pretendard Variable', 'Noto Sans KR', sans-serif !important;
            font-weight: 600;
          }

          pre, code, tt, kbd, samp,
          .wiki-code, .CodeMirror, textarea[data-auto-complete] {
            font-family: 'D2Coding', 'Noto Sans Mono CJK KR', monospace !important;
            font-size: 13px;
            line-height: 1.6;
          }

          .wiki p, .wiki li, .journal .wiki {
            line-height: 1.8;
          }

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
# [8] 디렉토리 준비
# ==============================================================================
RUN mkdir -p \
    tmp/cache tmp/pids tmp/sockets \
    log files plugins/assets public/plugin_assets

# ==============================================================================
# [9] WBS 플러그인 빌드
# ==============================================================================
RUN if [ -d plugins/redmine_wbs ]; then \
      cd plugins/redmine_wbs && \
      npm ci --no-audit && \
      npm run production && \
      cd ../..; \
    fi

# ==============================================================================
# [10] Bundler 설정 + Gem 설치
# ==============================================================================
RUN bundle config set --local without 'development test' && \
    bundle config set --local jobs 4 && \
    bundle install

# ==============================================================================
# [11] 권한 설정
# ==============================================================================
RUN chown -R redmine:redmine \
    /usr/src/redmine \
    /usr/local/bundle

# ==============================================================================
# [12] 커스텀 초기화 스크립트 (★ 수정: 원본 entrypoint 호출 후 실행)
# ==============================================================================
RUN cat > /usr/local/bin/redmine-init.sh <<'BASH'
#!/bin/bash
set -e

echo "======================================"
echo "Redmine 추가 초기화 시작"
echo "시간: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "======================================"

# 1. 플러그인 마이그레이션
echo "[1/3] 플러그인 마이그레이션 중..."
bundle exec rake redmine:plugins:migrate RAILS_ENV=production

# 2. Asset Precompile (필요시)
if [ ! -d tmp/cache/assets ] || [ -z "$(ls -A tmp/cache/assets 2>/dev/null)" ]; then
  echo "[2/3] 에셋 컴파일 중..."
  bundle exec rake assets:precompile RAILS_ENV=production
else
  echo "[2/3] 에셋 이미 컴파일됨 (건너뜀)"
fi

# 3. 권한 확인
echo "[3/3] 파일 권한 확인 중..."
chown -R redmine:redmine files log tmp public/plugin_assets 2>/dev/null || true

echo "======================================"
echo "✓ 추가 초기화 완료"
echo "======================================"
BASH

RUN chmod +x /usr/local/bin/redmine-init.sh

# ==============================================================================
# [13] 원본 entrypoint 래핑 (★ 핵심: database.yml 생성 보장)
# ==============================================================================
RUN mv /docker-entrypoint.sh /docker-entrypoint-original.sh && \
    cat > /docker-entrypoint.sh <<'BASH'
#!/bin/bash
set -e

# 1. 원본 entrypoint 실행 (database.yml 생성)
echo "🚀 [1/2] Redmine 기본 초기화 중..."
source /docker-entrypoint-original.sh

# 2. 커스텀 초기화 (플러그인 등)
echo "🚀 [2/2] 한국어 환경 초기화 중..."
/usr/local/bin/redmine-init.sh

# 3. 서버 시작
echo "✅ 초기화 완료. Redmine 서버 시작 중..."
exec "$@"
BASH

RUN chmod +x /docker-entrypoint.sh

# ==============================================================================
# [14] 헬스체크
# ==============================================================================
RUN echo '#!/bin/bash\ncurl -f -s http://localhost:3000/login > /dev/null || exit 1' \
    > /healthcheck.sh && chmod +x /healthcheck.sh

# ==============================================================================
# [최종] 기본 설정 유지
# ==============================================================================
USER redmine
EXPOSE 3000

# ★ 원본 ENTRYPOINT 유지 (database.yml 생성 보장)
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["rails", "server", "-b", "0.0.0.0"]
