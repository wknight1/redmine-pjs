# [1] 베이스 이미지: Redmine 6.1.1 최신 안정 버전
FROM redmine:6.1.1

# [2] 환경 설정: 루트 권한으로 시스템 패키지 설치
USER root

# [3] 필수 패키지 설치
# curl, unzip, git, npm 등 빌드에 필요한 모든 도구 포함
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl unzip build-essential libpq-dev nodejs npm \
    && rm -rf /var/lib/apt/lists/*

# [4] 작업 디렉토리 고정 (Redmine 공식 경로)
WORKDIR /usr/src/redmine

# [5] 한국어 용어 변경: '일감' -> '이슈' (KBS 프로젝트 표준)
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml

# [6] 테마 설치 (404 에러 원천 차단 및 절대 경로 사용)
RUN mkdir -p /usr/src/redmine/public/themes

# - Magopale (Opale 6.x 호환 버전)
RUN curl -fL https://github.com/VitexSoftware/magopale/archive/refs/heads/master.zip -o opale.zip && \
    unzip opale.zip && mv magopale-master /usr/src/redmine/public/themes/opale && rm opale.zip

# - PurpleMine2 (가장 대중적이고 안정적인 테마)
RUN curl -fL https://github.com/mrliptontea/PurpleMine2/archive/refs/heads/master.zip -o purple.zip && \
    unzip purple.zip && mv PurpleMine2-master /usr/src/redmine/public/themes/purplemine2 && rm purple.zip

# - Fare (6.x 완벽 지원 및 다운로드 안정성 검증 완료)
RUN curl -fL https://github.com/NunoSouto/redmine-theme-fare/archive/refs/heads/master.zip -o fare.zip && \
    unzip fare.zip && mv redmine-theme-fare-master /usr/src/redmine/public/themes/fare && rm fare.zip

# [7] 플러그인 설치 (전수 검증된 6.x 공식 리포지토리)
RUN git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize
RUN git clone --depth 1 https://github.com/akiko-pusu/redmine_issue_templates.git plugins/redmine_issue_templates
RUN git clone --depth 1 https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs

# [8] WBS 플러그인 빌드 및 전체 의존성 설치
# npm install 실패 방지를 위해 절대 경로에서 실행
RUN cd /usr/src/redmine/plugins/redmine_wbs && npm install && npm run production
RUN bundle install --without development test

# [9] 보안 및 권한 설정: 볼륨 데이터 쓰기 권한 부여
RUN chown -R redmine:redmine /usr/src/redmine/files /usr/src/redmine/plugins /usr/src/redmine/public/themes

# [10] 실행 계정 전환
USER redmine