# [1] 공식 표준 이미지
FROM redmine:6.1.1

USER root

# [2] 한국어 및 필수 도구 설치
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales locales-all tzdata \
    git curl unzip build-essential libpq-dev nodejs npm \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=ko_KR.UTF-8 \
    LANGUAGE=ko_KR.UTF-8 \
    LC_ALL=ko_KR.UTF-8 \
    TZ=Asia/Seoul

WORKDIR /usr/src/redmine

# [3] 한국어 용어 커스텀
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml

# [4] 테마 및 플러그인 설치
RUN mkdir -p public/themes plugins
RUN curl -fL https://github.com/VitexSoftware/magopale/archive/refs/heads/master.zip -o opale.zip && \
    unzip opale.zip && mv magopale-master public/themes/opale && rm opale.zip
RUN curl -fL https://github.com/mrliptontea/PurpleMine2/archive/refs/heads/master.zip -o purple.zip && \
    unzip purple.zip && mv PurpleMine2-master public/themes/purplemine2 && rm purple.zip

RUN git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize && \
    git clone --depth 1 https://github.com/akiko-pusu/redmine_issue_templates.git plugins/redmine_issue_templates && \
    git clone --depth 1 https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs

# [5] 권한 설정 강화: 홈 디렉토리와 번들러 캐시 경로를 미리 생성
RUN mkdir -p /home/redmine/.bundle && \
    chown -R redmine:redmine /usr/src/redmine /home/redmine

# [6] 플러그인 빌드 (권한 부여 후 실행)
RUN cd plugins/redmine_wbs && npm install && npm run production

# [7] 의존성 설치 (캐시 경로 무시 옵션 추가)
RUN bundle config set --local path 'vendor/bundle' && \
    bundle install --without development test

USER redmine