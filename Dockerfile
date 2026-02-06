# [1] 공식 표준 이미지 (Redmine 6.1.1)
FROM redmine:6.1.1

USER root

# [2] 필수 패키지 설치
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales locales-all tzdata \
    git curl unzip build-essential libpq-dev nodejs npm \
    libyaml-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*

# 시스템 환경 변수 설정
ENV LANG=ko_KR.UTF-8 \
    LANGUAGE=ko_KR.UTF-8 \
    LC_ALL=ko_KR.UTF-8 \
    TZ=Asia/Seoul \
    # 핵심: 번들러 캐시 경로를 앱 디렉토리 내부로 강제 이전
    BUNDLE_USER_HOME=/usr/src/redmine/.bundle_cache

WORKDIR /usr/src/redmine

# [3] 한국어 용어 커스텀
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml

# [4] 테마 및 플러그인 설치 (안정성이 검증된 것만 우선 포함)
RUN mkdir -p public/themes plugins
RUN curl -fL https://github.com/VitexSoftware/magopale/archive/refs/heads/master.zip -o opale.zip && \
    unzip opale.zip && mv magopale-master public/themes/opale && rm opale.zip
RUN curl -fL https://github.com/mrliptontea/PurpleMine2/archive/refs/heads/master.zip -o purple.zip && \
    unzip purple.zip && mv PurpleMine2-master public/themes/purplemine2 && rm purple.zip

RUN git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize && \
    git clone --depth 1 https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs

# [5] 권한 설정 강화 (새로 만든 캐시 폴더 포함)
RUN mkdir -p /usr/src/redmine/.bundle_cache && \
    chown -R redmine:redmine /usr/src/redmine

# [6] WBS 빌드
RUN cd plugins/redmine_wbs && npm install && npm run production

# [7] Gem 의존성 설치
RUN bundle install --without development test

USER redmine