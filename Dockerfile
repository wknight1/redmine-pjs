# [1] 베이스 이미지: 2026년 최신 안정 버전인 Redmine 6.1.1 사용
FROM redmine:6.1.1

# [2] 루트 권한으로 시스템 패키지 설치
USER root

# [3] 필수 도구 설치 (전수 검사 결과: git, npm, 빌드 도구 필수)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git build-essential libpq-dev nodejs npm \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/redmine

# [4] 한국어 번역 커스텀: '일감' -> '이슈' 변경
# ko.yml 내의 텍스트를 실시간으로 치환합니다.
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml

# [5] 테마 설치 (전수 검사 통과 리스트)
# 인증 에러가 발생하던 리포지토리를 제거하고 공개된 6.x 호환 리포지토리만 사용
RUN git clone https://github.com/VitexSoftware/magopale.git public/themes/opale && \
    git clone https://github.com/mrliptontea/PurpleMine2.git public/themes/purplemine2 && \
    git clone https://github.com/akiko-pusu/redmine_minimalflat2.git public/themes/minimalflat2

# [6] 플러그인 설치 (전수 검사 통과 리스트)
# Redmine 6.x 아키텍처를 공식 지원하는 리포지토리입니다.
RUN git clone https://github.com/onozaty/redmine-view-customize.git plugins/view_customize && \
    git clone https://github.com/akiko-pusu/redmine_issue_templates.git plugins/redmine_issue_templates && \
    git clone https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs

# [7] WBS 플러그인 빌드 및 전체 의존성 설치
# eXolnet WBS는 최신 환경에서 npm 빌드 과정이 누락되면 작동하지 않습니다.
RUN cd plugins/redmine_wbs && npm install && npm run production
RUN bundle install --without development test

# [8] 권한 설정: 볼륨 데이터 보존을 위해 redmine 계정에 소유권 부여
RUN chown -R redmine:redmine files/ plugins/ public/themes/

# [9] 보안을 위해 일반 사용자로 복귀
USER redmine