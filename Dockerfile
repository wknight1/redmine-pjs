# ==============================================================================
# STAGE 1: Database (PostgreSQL 18.1 with Korean Locale / ICU Support)
# ==============================================================================
FROM postgres:18.1 AS database
USER root

# [OS 최적화] 데비안 OS 레벨에서 한국어 로케일 물리적 생성
# 이것이 없으면 DB가 정렬을 할 때 한글을 제대로 인식하지 못합니다.
RUN apt-get update && apt-get install -y locales && \
    sed -i '/ko_KR.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen

# 환경 변수 강제 지정
ENV LANG=ko_KR.UTF-8 \
    LC_ALL=ko_KR.UTF-8

# ==============================================================================
# STAGE 2: Application (Redmine 6.1.1 / KBS Custom Edition)
# ==============================================================================
FROM redmine:6.1.1 AS application
USER root

# [1] 필수 패키지 설치 (경량화 및 캐시 제거 포함)
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales locales-all tzdata fonts-nanum \
    git curl unzip wget fontconfig build-essential libpq-dev nodejs npm \
    libyaml-dev pkg-config ghostscript && \
    rm -rf /var/lib/apt/lists/*

# [2] 폰트 3종 세트 설치 (파일명 고정으로 빌드 실패 원천 차단)
RUN mkdir -p /usr/share/fonts/truetype/custom && cd /usr/share/fonts/truetype/custom && \
    # Pretendard (UI 가독성용)
    curl -fLo pretendard.zip https://github.com/orioncactus/pretendard/releases/download/v1.3.9/Pretendard-1.3.9.zip && \
    unzip -q pretendard.zip -d Pretendard && \
    # D2Coding (코드 가독성용)
    curl -fLo d2coding.zip https://github.com/naver/d2codingfont/releases/download/VER1.3.2/D2Coding-Ver1.3.2-20180524.zip && \
    unzip -q d2coding.zip -d D2Coding && \
    # Spoqa Han Sans (보조용)
    curl -fLo spoqa.zip https://github.com/spoqa/spoqa-han-sans/releases/download/v3.0.0/SpoqaHanSansNeo_all.zip && \
    unzip -q spoqa.zip -d Spoqa && \
    rm *.zip && fc-cache -f -v

# [3] PDF 출력 시 한글 깨짐 방지 (심볼릭 링크)
# Redmine PDF 엔진은 기본 폰트 경로를 참조하므로 링크를 걸어줍니다.
RUN mkdir -p public/fonts && \
    ln -s /usr/share/fonts/truetype/nanum/NanumGothic.ttf public/fonts/NanumGothic.ttf && \
    cp /usr/share/fonts/truetype/custom/Pretendard/public/static/Pretendard-Regular.otf public/fonts/Pretendard.otf

# [4] 환경 변수 설정
ENV LANG=ko_KR.UTF-8 \
    TZ=Asia/Seoul \
    GEM_HOME=/usr/local/bundle \
    BUNDLE_PATH=/usr/local/bundle

WORKDIR /usr/src/redmine

# [5] 용어 현지화 (일감 -> 이슈, 결함 -> 버그)
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml && \
    sed -i 's/새 일감/새 이슈/g' config/locales/ko.yml

# [6] 필수 플러그인 설치
RUN git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize && \
    git clone --depth 1 https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs && \
    git clone --depth 1 https://github.com/akiko-pusu/redmine_issue_templates.git plugins/redmine_issue_templates

# [7] UI 디자인 자동 주입 스크립트 (Pretendard & D2Coding 적용)
RUN echo "if ViewCustomize.where(path_pattern: '.*').empty?; \
  ViewCustomize.create!( \
    path_pattern: '.*', \
    customization_type: 'style', \
    code: \"body, #content, #header, #footer { font-family: 'Pretendard Variable', 'Pretendard', sans-serif !important; } \
           h1, h2, h3 { font-family: 'Pretendard Variable', sans-serif !important; font-weight: 600; } \
           pre, code, .wiki-code, textarea { font-family: 'D2Coding', monospace !important; }\", \
    enabled: true, \
    comments: 'KBS Digital Service Standard UI' \
  ); puts 'Standard UI Injected'; end" > /usr/src/redmine/init_ui.rb

# [8] ★ 핵심 보안 및 권한 설정 (Code 23 해결의 Key)
# 홈 디렉토리와 번들 디렉토리를 미리 생성하고 소유권을 redmine에게 넘깁니다.
RUN mkdir -p /home/redmine/.bundle && \
    chown -R redmine:redmine /usr/src/redmine /home/redmine /usr/local/bundle

# [9] 빌드 실행 (redmine 유저로 전환하여 안전하게 빌드)
USER redmine
RUN cd plugins/redmine_wbs && npm install && npm run production
RUN bundle install --without development test

# Entrypoint가 다시 root 권한으로 볼륨 셋업을 할 수 있도록 root로 복귀 (공식 이미지 표준 준수)
USER root