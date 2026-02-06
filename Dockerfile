# ==========================================
# STAGE 1: Database (PostgreSQL 18.1 with Korean Locale)
# ==========================================
FROM postgres:18.1 AS database
USER root
RUN apt-get update && apt-get install -y locales && \
    sed -i '/ko_KR.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen
ENV LANG=ko_KR.UTF-8 LC_ALL=ko_KR.UTF-8

# ==========================================
# STAGE 2: Application (Redmine 6.1.1)
# ==========================================
FROM redmine:6.1.1 AS application
USER root

# [1] 패키지 및 폰트 도구 설치
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales locales-all tzdata fonts-nanum \
    git curl unzip wget fontconfig build-essential libpq-dev nodejs npm \
    libyaml-dev pkg-config ghostscript && \
    rm -rf /var/lib/apt/lists/*

# [2] 폰트 3종 설치 (파일명 일치 완료)
RUN mkdir -p /usr/share/fonts/truetype/custom && cd /usr/share/fonts/truetype/custom && \
    curl -fLo Pretendard.zip https://github.com/orioncactus/pretendard/releases/download/v1.3.9/Pretendard-1.3.9.zip && \
    unzip -q Pretendard.zip -d Pretendard && \
    curl -fLo D2Coding.zip https://github.com/naver/d2codingfont/releases/download/VER1.3.2/D2Coding-Ver1.3.2-20180524.zip && \
    unzip -q D2Coding.zip -d D2Coding && \
    curl -fLo Spoqa.zip https://github.com/spoqa/spoqa-han-sans/releases/download/v3.0.0/SpoqaHanSansNeo_all.zip && \
    unzip -q Spoqa.zip -d Spoqa && \
    rm *.zip && fc-cache -f -v

# [3] PDF 폰트 설정
RUN mkdir -p public/fonts && \
    ln -s /usr/share/fonts/truetype/nanum/NanumGothic.ttf public/fonts/NanumGothic.ttf && \
    cp /usr/share/fonts/truetype/custom/Pretendard/public/static/Pretendard-Regular.otf public/fonts/Pretendard.otf

# [4] 환경 변수 설정
ENV LANG=ko_KR.UTF-8 TZ=Asia/Seoul

WORKDIR /usr/src/redmine

# [5] 용어 치환
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml && \
    sed -i 's/새 일감/새 이슈/g' config/locales/ko.yml

# [6] 플러그인 설치
RUN git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize && \
    git clone --depth 1 https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs && \
    git clone --depth 1 https://github.com/akiko-pusu/redmine_issue_templates.git plugins/redmine_issue_templates

# [7] UI 자동 주입 스크립트
RUN echo "if ViewCustomize.where(path_pattern: '.*').empty?; \
  ViewCustomize.create!( \
    path_pattern: '.*', \
    customization_type: 'style', \
    code: \"body, #content, #header, #footer { font-family: 'Pretendard Variable', 'Pretendard', sans-serif !important; } \
           h1, h2, h3 { font-family: 'Pretendard Variable', sans-serif !important; font-weight: 600; } \
           pre, code, .wiki-code, textarea { font-family: 'D2Coding', monospace !important; }\", \
    enabled: true, \
    comments: 'UI auto-injection' \
  ); puts 'Design Injected!'; end" > /usr/src/redmine/init_ui.rb

# [8] ★ 권한 문제 최종 해결
# /home/redmine/.bundle 디렉토리를 명시적으로 생성하고 권한을 부여합니다.
RUN mkdir -p /home/redmine/.bundle && \
    chown -R redmine:redmine /usr/src/redmine /home/redmine

# [9] 빌드 실행
USER redmine
RUN cd plugins/redmine_wbs && npm install && npm run production
RUN bundle install --without development test

# 중요: Entrypoint가 루트 권한으로 볼륨 초기화를 할 수 있도록 root로 복귀
USER root