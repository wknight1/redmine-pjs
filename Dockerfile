# [1] 베이스 이미지: 공식 Redmine 6.1.1
FROM redmine:6.1.1

USER root

# [2] 시스템 패키지 고도화
# - fonts-nanum: PDF/Gantt 한글 깨짐 방지
# - libyaml-dev: psych 빌드 필수
# - ghostscript: PDF 처리 성능 향상
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales locales-all tzdata \
    fonts-nanum fonts-nanum-coding \
    git curl unzip build-essential libpq-dev nodejs npm \
    libyaml-dev pkg-config ghostscript \
    && rm -rf /var/lib/apt/lists/*

# 시스템 환경 변수 (한국어 표준)
ENV LANG=ko_KR.UTF-8 \
    LANGUAGE=ko_KR.UTF-8 \
    LC_ALL=ko_KR.UTF-8 \
    TZ=Asia/Seoul

WORKDIR /usr/src/redmine

# [3] 한국어 실무 용어 커스텀 (일감 -> 이슈)
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml

# [4] 플러그인 및 테마 (안정 버전 고정)
RUN mkdir -p public/themes plugins
# 테마 설치
RUN curl -fL https://github.com/VitexSoftware/magopale/archive/refs/heads/master.zip -o opale.zip && \
    unzip opale.zip && mv magopale-master public/themes/opale && rm opale.zip
RUN curl -fL https://github.com/mrliptontea/PurpleMine2/archive/refs/heads/master.zip -o purple.zip && \
    unzip purple.zip && mv PurpleMine2-master public/themes/purplemine2 && rm purple.zip

# 플러그인 설치 (경로 에러 방지를 위해 명시적 폴더명 지정)
RUN git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize && \
    git clone --depth 1 https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs && \
    git clone --depth 1 https://github.com/akiko-pusu/redmine_issue_templates.git plugins/redmine_issue_templates

# [5] 권한 및 환경 정리
# Bundler 캐시 경로를 내부로 고정하여 Code 23 에러 원천 차단
ENV BUNDLE_USER_HOME=/usr/src/redmine/.bundle_cache
RUN mkdir -p .bundle_cache && chown -R redmine:redmine /usr/src/redmine

# [6] 빌드 (Production 전용)
RUN cd plugins/redmine_wbs && npm install && npm run production
RUN bundle install --without development test

# [7] 실행 설정
# USER redmine을 명시하지 않습니다. 
# 공식 Entrypoint가 root로 시작해 볼륨 권한을 닦고 스스로 계정을 전환하게 둡니다.