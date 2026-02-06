# [1] 베이스 이미지: Redmine 6.1.1 최신 안정 버전
FROM redmine:6.1.1

# [2] 환경 설정: 루트 권한으로 시스템 패키지 설치
USER root

# [3] 필수 패키지 설치
# - curl -f: 다운로드 실패 시(404 등) 9바이트 파일을 만들지 않고 즉시 중단
# - unzip: 테마 압축 해제용
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl unzip build-essential libpq-dev nodejs npm \
    && rm -rf /var/lib/apt/lists/*

# [4] 작업 디렉토리 고정
WORKDIR /usr/src/redmine

# [5] 한국어 용어 변경: '일감' -> '이슈' (KBS 프로젝트 표준)
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml

# [6] 테마 설치 (브랜치명 전수 교정 및 경로 강제 생성)
RUN mkdir -p /usr/src/redmine/public/themes

# - Magopale (Opale 6.x 호환): master 브랜치 확인
RUN curl -fL https://github.com/VitexSoftware/magopale/archive/refs/heads/master.zip -o opale.zip && \
    unzip opale.zip && mv magopale-master /usr/src/redmine/public/themes/opale && rm opale.zip

# - PurpleMine2: master 브랜치 확인
RUN curl -fL https://github.com/mrliptontea/PurpleMine2/archive/refs/heads/master.zip -o purple.zip && \
    unzip purple.zip && mv PurpleMine2-master /usr/src/redmine/public/themes/purplemine2 && rm purple.zip

# - MinimalFlat2: 브랜치명을 main으로 수정하여 404 에러 해결
RUN curl -fL https://github.com/akiko-pusu/redmine_minimalflat2/archive/refs/heads/main.zip -o flat.zip && \
    unzip flat.zip && mv redmine_minimalflat2-main /usr/src/redmine/public/themes/minimalflat2 && rm flat.zip

# [7] 플러그인 설치 (Git Clone 방식 사용)
RUN git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize && \
    git clone --depth 1 https://github.com/akiko-pusu/redmine_issue_templates.git plugins/redmine_issue_templates && \
    git clone --depth 1 https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs

# [8] WBS 플러그인 빌드 및 의존성 설치
# WBS는 빌드 시점에 npm 라이브러리가 반드시 필요함
RUN cd /usr/src/redmine/plugins/redmine_wbs && npm install && npm run production
RUN bundle install --without development test

# [9] 보안 및 권한 설정: Redmine 계정이 볼륨에 쓸 수 있도록 권한 부여
RUN chown -R redmine:redmine /usr/src/redmine/files /usr/src/redmine/plugins /usr/src/redmine/public/themes

# [10] 실행 계정 전환
USER redmine