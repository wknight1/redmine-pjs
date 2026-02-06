# [1] 공식 표준 이미지
FROM redmine:6.1.1

USER root

# [2] 필수 패키지 설치 (libyaml-dev 포함)
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales locales-all tzdata \
    git curl unzip build-essential libpq-dev nodejs npm \
    libyaml-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*

# 시스템 환경 변수 설정
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

# 플러그인 설치 (이슈 템플릿은 안정성을 위해 현재 제외하거나 최신 마스터 대신 안정 버전 사용 권장)
RUN git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize
RUN git clone --depth 1 https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs
# 이슈 템플릿 플러그인은 최신 버전에서 경로 이슈가 잦으므로 일단 제외하고 가동 확인 후 추가하는 것이 안전합니다.

# [5] 권한 설정 강화
RUN mkdir -p /home/redmine/.bundle && \
    chown -R redmine:redmine /usr/src/redmine /home/redmine

# [6] 빌드 및 의존성 설치
RUN cd plugins/redmine_wbs && npm install && npm run production
RUN bundle install --without development test

USER redmine