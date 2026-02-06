# [1] 베이스 이미지: Redmine 6.1.1 최신 안정 버전
FROM redmine:6.1.1

# [2] 루트 권한으로 시스템 패키지 설치
USER root

# [3] 필수 패키지 설치 (unzip 및 curl 추가)
# - curl, unzip: 테마 아카이브 다운로드 및 압축 해제용
# - git: 플러그인 리포지토리 클론용
# - build-essential, nodejs, npm: 빌드 및 WBS 플러그인 최적화용
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl unzip build-essential libpq-dev nodejs npm \
    && rm -rf /var/lib/apt/lists/*

# [4] 작업 디렉토리 고정
WORKDIR /usr/src/redmine

# [5] 한국어 용어 변경: '일감' -> '이슈' (KBS 업무 표준 반영)
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml

# [6] 테마 설치 (강력한 경로 보장 로직 적용)
# 에러 방지 핵심: mkdir -p를 통해 부모 디렉토리를 확실히 생성합니다.
RUN mkdir -p /usr/src/redmine/public/themes

# - Magopale 테마 (Opale 6.x 호환)
RUN curl -L https://github.com/VitexSoftware/magopale/archive/refs/heads/master.zip -o opale.zip && \
    unzip opale.zip && mv magopale-master /usr/src/redmine/public/themes/opale && rm opale.zip

# - PurpleMine2 테마 (가장 안정적인 테마)
RUN curl -L https://github.com/mrliptontea/PurpleMine2/archive/refs/heads/master.zip -o purple.zip && \
    unzip purple.zip && mv PurpleMine2-master /usr/src/redmine/public/themes/purplemine2 && rm purple.zip

# - MinimalFlat2 테마 (6.x 공식 UI 지원)
RUN curl -L https://github.com/akiko-pusu/redmine_minimalflat2/archive/refs/heads/master.zip -o flat.zip && \
    unzip flat.zip && mv redmine_minimalflat2-master /usr/src/redmine/public/themes/minimalflat2 && rm flat.zip

# [7] 플러그인 설치 (전수 검증된 공식 리포지토리)
RUN git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize && \
    git clone --depth 1 https://github.com/akiko-pusu/redmine_issue_templates.git plugins/redmine_issue_templates && \
    git clone --depth 1 https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs

# [8] WBS 플러그인 빌드 및 전체 의존성 설치
# npm install 과정에서 오류가 나지 않도록 플러그인 디렉토리에서 직접 수행
RUN cd /usr/src/redmine/plugins/redmine_wbs && npm install && npm run production
RUN bundle install --without development test

# [9] 보안 및 권한 설정
# Docker 볼륨에 데이터를 안전하게 쓰기 위해 redmine 계정에 소유권 부여
RUN chown -R redmine:redmine /usr/src/redmine/files /usr/src/redmine/plugins /usr/src/redmine/public/themes

# [10] 실행 계정 전환 (보안 권고 사항)
USER redmine