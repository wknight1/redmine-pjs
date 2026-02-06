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
# STAGE 2: Redmine 6.1.1 + 한국어 최적화
# ==============================================================================
FROM redmine:6.1.1 AS application

USER root

# 시스템 패키지 + 한글 로케일
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales locales-all tzdata \
    fonts-nanum fonts-noto-cjk fontconfig \
    build-essential libpq-dev pkg-config \
    nodejs npm git curl unzip wget \
    ghostscript libyaml-dev \
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
    ln -sf /usr/share/fonts/truetype/nanum/NanumGothic.ttf public/fonts/NanumGothic.ttf && \
    ln -sf /usr/share/fonts/truetype/custom/Pretendard/public/static/Pretendard-Regular.otf public/fonts/Pretendard.otf

# 용어 현지화
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml && \
    sed -i 's/새 일감/새 이슈/g' config/locales/ko.yml && \
    sed -i 's/하위 일감/하위 이슈/g' config/locales/ko.yml

# 플러그인 설치
RUN git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize && \
    git clone --depth 1 https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs && \
    git clone --depth 1 https://github.com/akiko-pusu/redmine_issue_templates.git plugins/redmine_issue_templates && \
    find plugins -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

# UI 커스터마이징
RUN cat > config/initializers/zz_custom_ui.rb <<'RUBY'
Rails.application.config.after_initialize do
  if defined?(ViewCustomize) && !ViewCustomize.exists?(comments: 'KBS Korean UI v2')
    ViewCustomize.create!(
      path_pattern: '.*',
      customization_type: 'style',
      code: "body,#content,#header,#footer{font-family:'Pretendard',-apple-system,sans-serif!important;letter-spacing:-0.02em;word-break:keep-all}pre,code,.wiki-code{font-family:'D2Coding',monospace!important}",
      enabled: true,
      comments: 'KBS Korean UI v2'
    )
  end
end
RUBY

# 디렉토리 준비
RUN mkdir -p tmp/cache tmp/pids log files plugins/assets public/plugin_assets /home/redmine/.bundle

# WBS 플러그인 빌드
RUN if [ -d plugins/redmine_wbs ]; then cd plugins/redmine_wbs && npm ci --no-audit && npm run production && cd ../..; fi

# Bundler 설정
RUN bundle config set --local without 'development test' && \
    bundle config set --local jobs 4 && \
    bundle install

# ★ 핵심: 권한 설정 (redmine 유저에게 모든 권한)
RUN chown -R redmine:redmine /usr/src/redmine /usr/local/bundle /home/redmine

# 헬스체크
RUN echo '#!/bin/bash\ncurl -f -s http://localhost:3000/login > /dev/null || exit 1' > /healthcheck.sh && chmod +x /healthcheck.sh

USER redmine
EXPOSE 3000

# ★ 원본 ENTRYPOINT 사용 (수정 안함!)
