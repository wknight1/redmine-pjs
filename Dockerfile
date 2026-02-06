# [1] 베이스 이미지: Redmine 6.1.1 최신 안정 버전
FROM redmine:6.1.1

# [2] 환경 설정: 루트 권한으로 시스템 패키지 설치
USER root

# [3] 필수 패키지 설치 (unzip 및 curl 추가)
# - git: 플러그인용
# - curl, unzip: 테마 다운로드 및 압축 해제용
# - build-essential, libpq-dev, nodejs, npm: 빌드 및 WBS 플러그인용
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl unzip build-essential libpq-dev nodejs npm \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/redmine

# [4] 한국어 용어 변경: '일감' -> '이슈' (KBS 업무 표준화 반영)
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml

# [5] 테마 설치 (curl 방식을 사용하여 Git 인증 에러 완벽 차단)
# - Magopale (Opale 6.x 호환 버전)
RUN curl -L https://github.com/VitexSoftware/magopale/archive/refs/heads/master.zip -o opale.zip && \
    unzip opale.zip && mv magopale-master public/themes/opale && rm opale.zip

# - PurpleMine2 (가장 안정적인 테마)
RUN curl -L https://github.com/mrliptontea/PurpleMine2/archive/refs/heads/master.zip -o purple.zip && \
    unzip purple.zip && mv PurpleMine2-master public/themes/purplemine2 && rm purple.zip

# - MinimalFlat2 (6.x 공식 UI 지원 테마)
RUN curl -L https://github.com/akiko-pusu/redmine_minimalflat2/archive/refs/heads/master.zip -o flat.zip && \
    unzip flat.zip && mv redmine_minimalflat2-master public/themes/minimalflat2 && rm flat.zip

# [6] 플러그인 설치 (인증 이슈가 없는 공식 메인 리포지토리 사용)
RUN git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize
RUN git clone --depth 1 https://github.com/akiko-pusu/redmine_issue_templates.git plugins/redmine_issue_templates
RUN git clone --depth 1 https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs

# [7] WBS 플러그인 빌드 및 의존성 설치
RUN cd plugins/redmine_wbs && npm install && npm run production
RUN bundle install --without development test

# [8] 권한 설정: 볼륨 데이터 쓰기 권한 부여
RUN chown -R redmine:redmine files/ plugins/ public/themes/

# [9] 보안을 위해 일반 사용자로 실행
USER redmine