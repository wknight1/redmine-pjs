# [1] 베이스 이미지: 공식 Redmine 6.1.1 (Debian 기반)
FROM redmine:6.1.1

USER root

# [2] 빌드 필수 패키지 및 한국어 로케일 설치
# libyaml-dev: psych gem 빌드 필수 / pkg-config: 컴파일러 보조
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales locales-all tzdata \
    git curl unzip build-essential libpq-dev nodejs npm \
    libyaml-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*

# 시스템 환경 변수 한국어 및 서울 시간대 고정
ENV LANG=ko_KR.UTF-8 \
    LANGUAGE=ko_KR.UTF-8 \
    LC_ALL=ko_KR.UTF-8 \
    TZ=Asia/Seoul

WORKDIR /usr/src/redmine

# [3] 한국어 용어 커스텀 (일감 -> 이슈)
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml

# [4] 테마 및 플러그인 설치 (안전한 Public 리포지토리)
RUN mkdir -p public/themes plugins
RUN curl -fL https://github.com/VitexSoftware/magopale/archive/refs/heads/master.zip -o opale.zip && \
    unzip opale.zip && mv magopale-master public/themes/opale && rm opale.zip
RUN curl -fL https://github.com/mrliptontea/PurpleMine2/archive/refs/heads/master.zip -o purple.zip && \
    unzip purple.zip && mv PurpleMine2-master public/themes/purplemine2 && rm purple.zip

RUN git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize && \
    git clone --depth 1 https://github.com/akiko-pusu/redmine_issue_templates.git plugins/redmine_issue_templates && \
    git clone --depth 1 https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs

# [5] WBS 플러그인 빌드 (npm)
RUN cd plugins/redmine_wbs && npm install && npm run production

# [6] 핵심: Gem 의존성 설치 (권한 에러 방지를 위해 루트에서 수행)
RUN bundle install --without development test

# [7] 모든 파일 및 홈 디렉토리 소유권을 redmine 계정으로 변경
RUN chown -R redmine:redmine /usr/src/redmine /home/redmine

# [8] 실행 계정 전환 (보안)
USER redmine