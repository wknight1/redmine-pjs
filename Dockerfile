# [1] 공식 표준 이미지 (Debian 기반으로 로케일 지원 우수)
FROM redmine:6.1.1

USER root

# [2] 한국어 로케일 및 필수 빌드 도구 설치
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales locales-all tzdata \
    git curl unzip build-essential libpq-dev nodejs npm \
    && rm -rf /var/lib/apt/lists/*

# 시스템 환경 변수 한국어 고정
ENV LANG=ko_KR.UTF-8 \
    LANGUAGE=ko_KR.UTF-8 \
    LC_ALL=ko_KR.UTF-8 \
    TZ=Asia/Seoul

WORKDIR /usr/src/redmine

# [3] 한국어 용어 커스텀 (일감 -> 이슈)
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml

# [4] 테마 설치 (검증된 리포지토리)
RUN mkdir -p public/themes
RUN curl -fL https://github.com/VitexSoftware/magopale/archive/refs/heads/master.zip -o opale.zip && \
    unzip opale.zip && mv magopale-master public/themes/opale && rm opale.zip
RUN curl -fL https://github.com/mrliptontea/PurpleMine2/archive/refs/heads/master.zip -o purple.zip && \
    unzip purple.zip && mv PurpleMine2-master public/themes/purplemine2 && rm purple.zip

# [5] 플러그인 설치 (6.x 공식 지원 버전)
RUN git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize && \
    git clone --depth 1 https://github.com/akiko-pusu/redmine_issue_templates.git plugins/redmine_issue_templates && \
    git clone --depth 1 https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs

# [6] 핵심: 권한 설정 (작업 디렉토리 + 홈 디렉토리)
# Bundler 에러(code 23)를 방지하기 위해 홈 디렉토리까지 권한 부여
RUN chown -R redmine:redmine /usr/src/redmine /home/redmine

# [7] 플러그인 빌드 및 의존성 설치
RUN cd plugins/redmine_wbs && npm install && npm run production
RUN bundle install --without development test

# [8] 실행 계정 전환
USER redmine