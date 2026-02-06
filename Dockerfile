# [1] 베이스 이미지: Redmine 6.1.1 (2026년 최신 안정 버전)
FROM redmine:6.1.1

# [2] 환경 설정: 루트 권한으로 시스템 패키지 설치
USER root

# [3] 필수 패키지 설치 (전수 검사 완료)
# curl, unzip, git, nodejs, npm 등 빌드에 필요한 도구 일체
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl unzip build-essential libpq-dev nodejs npm \
    && rm -rf /var/lib/apt/lists/*

# [4] 작업 디렉토리 고정
WORKDIR /usr/src/redmine

# [5] 한국어 용어 변경: '일감' -> '이슈' (KBS 프로젝트 표준 반영)
# ko.yml 내의 텍스트를 직접 치환하여 한국어 설정 시 즉시 적용되게 합니다.
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml

# [6] 테마 설치 (404 에러 원천 차단 로직)
# 부모 디렉토리를 강제로 생성하여 경로 에러를 방지합니다.
RUN mkdir -p /usr/src/redmine/public/themes

# - Magopale (Opale의 6.x 대응 버전): 현재 Public 상태 확인 완료
RUN curl -fL https://github.com/VitexSoftware/magopale/archive/refs/heads/master.zip -o opale.zip && \
    unzip opale.zip && mv magopale-master /usr/src/redmine/public/themes/opale && rm opale.zip

# - PurpleMine2 (가장 안정적이고 대중적인 테마): 현재 Public 상태 확인 완료
RUN curl -fL https://github.com/mrliptontea/PurpleMine2/archive/refs/heads/master.zip -o purple.zip && \
    unzip purple.zip && mv PurpleMine2-master /usr/src/redmine/public/themes/purplemine2 && rm purple.zip

# [7] 플러그인 설치 (6.x 공식 지원 리포지토리)
# depth 1 옵션으로 클론 속도를 최적화합니다.
RUN git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize
RUN git clone --depth 1 https://github.com/akiko-pusu/redmine_issue_templates.git plugins/redmine_issue_templates
RUN git clone --depth 1 https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs

# [8] WBS 플러그인 빌드 및 전체 의존성 설치
# WBS는 최신 환경에서 npm 빌드가 누락되면 화면이 깨집니다.
RUN cd /usr/src/redmine/plugins/redmine_wbs && npm install && npm run production
RUN bundle install --without development test

# [9] 보안 및 권한 설정: Redmine 계정이 볼륨 데이터를 관리할 수 있도록 소유권 부여
RUN chown -R redmine:redmine /usr/src/redmine/files /usr/src/redmine/plugins /usr/src/redmine/public/themes

# [10] 실행 계정 전환 (보안 권고 사항)
USER redmine