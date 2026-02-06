# [1] 베이스 이미지 설정: 2026년 현재 가장 안정적인 Redmine 6.1.1 버전 사용
FROM redmine:6.1.1

# [2] 루트 권한으로 전환: 패키지 설치 및 환경 설정을 위해 일시적으로 권한 상승
USER root

# [3] 시스템 패키지 업데이트 및 필수 도구 설치
# - git: 플러그인/테마를 GitHub에서 가져오기 위함
# - build-essential, libpq-dev: Ruby Gem 빌드 시 필요한 컴파일 도구
# - nodejs, npm: WBS 플러그인 등 최신 JS 프레임워크 에셋 빌드용
RUN apt-get update && apt-get install -y --no-install-recommends \
    git build-essential libpq-dev nodejs npm \
    && rm -rf /var/lib/apt/lists/*

# [4] 작업 디렉토리 설정: Redmine 설치 기본 경로
WORKDIR /usr/src/redmine

# [5] 한국어 번역 커스터마이징 (가장 요청하신 부분)
# - Redmine의 기본 용어인 '일감'을 '이슈'로 변경합니다.
# - sed 명령어를 사용하여 ko.yml 파일 내의 모든 해당 단어를 치환합니다.
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml

# [6] 테마 설치 (Redmine 6.x 호환성 검증 버전)
# - opale: 모던한 UI 테마 (6.x 호환 포크 버전)
# - purplemine2, circle, abis: 사용자 선택 폭을 넓히기 위한 인기 테마 3종
RUN git clone https://github.com/VitexSoftware/magopale.git public/themes/opale && \
    git clone https://github.com/mrliptontea/PurpleMine2.git public/themes/purplemine2 && \
    git clone https://github.com/RyoSato/redmine_circle_theme.git public/themes/circle && \
    git clone https://github.com/themof/abis.git public/themes/abis

# [7] 플러그인 설치 (Redmine 6.x 및 Rails 7.2+ 호환 버전)
# - view_customize: UI 동적 제어 (CSS/JS 삽입)
# - issue_templates: 이슈 양식 표준화
# - redmine_wbs: 프로젝트 구조 시각화 (WBS)
RUN git clone https://github.com/onozaty/redmine-view-customize.git plugins/view_customize && \
    git clone https://github.com/agileware-jp/redmine_issue_templates.git plugins/redmine_issue_templates && \
    git clone https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs

# [8] 플러그인 에셋 빌드 및 의존성 라이브러리 설치
# - WBS 플러그인은 최신 브라우저 대응을 위해 npm 빌드 과정이 필수입니다.
# - bundle install을 통해 플러그인들이 요구하는 Ruby 라이브러리를 설치합니다.
RUN cd plugins/redmine_wbs && npm install && npm run production
RUN bundle install --without development test

# [9] 권한 보안 설정
# - 볼륨 매핑 시 Redmine 프로세스(redmine 계정)가 파일을 쓰고 읽을 수 있도록 소유권 변경
RUN chown -R redmine:redmine files/ plugins/ public/themes/

# [10] 실행 계정 복구: 보안을 위해 다시 일반 사용자로 전환
USER redmine