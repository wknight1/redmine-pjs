# ==========================================
# STAGE 1: Database (PostgreSQL 18.1)
# ==========================================
FROM postgres:18.1 AS database
USER root
RUN apt-get update && apt-get install -y locales && \
    sed -i '/ko_KR.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=ko_KR.UTF-8 LC_ALL=ko_KR.UTF-8

# ==========================================
# STAGE 2: Application (Redmine 6.1.1)
# ==========================================
FROM redmine:6.1.1 AS application
USER root

# [1] 필수 패키지 및 모든 한글 폰트 설치 (PDF/Gantt 대응)
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales locales-all tzdata fonts-nanum \
    git curl unzip wget fontconfig build-essential libpq-dev nodejs npm \
    libyaml-dev pkg-config ghostscript && \
    rm -rf /var/lib/apt/lists/*

# 폰트 3종 세트 설치 (Pretendard, D2Coding, Spoqa)
RUN mkdir -p /usr/share/fonts/truetype/custom && cd /usr/share/fonts/truetype/custom && \
    curl -fLo Pretendard.zip https://github.com/orioncactus/pretendard/releases/download/v1.3.9/Pretendard-1.3.9.zip && \
    unzip -q Pretendard.zip -d Pretendard && \
    curl -fLo D2Coding.zip https://github.com/naver/d2codingfont/releases/download/VER1.3.2/D2Coding-Ver1.3.2-20180524.zip && \
    unzip -q D2Coding-Ver1.3.2-20180524.zip -d D2Coding && \
    curl -fLo Spoqa.zip https://github.com/spoqa/spoqa-han-sans/releases/download/v3.0.0/SpoqaHanSansNeo_all.zip && \
    unzip -q SpoqaHanSansNeo_all.zip -d Spoqa && \
    rm *.zip && fc-cache -f -v

# [2] PDF 한글 깨짐 방지를 위한 폰트 링크 설정
# 레드마인이 내부적으로 나눔고딕을 인식하게 만듭니다.
RUN ln -s /usr/share/fonts/truetype/nanum/NanumGothic.ttf /usr/src/redmine/public/fonts/NanumGothic.ttf && \
    ln -s /usr/share/fonts/truetype/custom/Pretendard/public/static/Pretendard-Regular.otf /usr/src/redmine/public/fonts/Pretendard.otf

# [3] 번들러 경로 격리 및 환경 설정
ENV GEM_HOME=/usr/local/bundle BUNDLE_PATH=/usr/local/bundle LANG=ko_KR.UTF-8 TZ=Asia/Seoul

WORKDIR /usr/src/redmine

# [4] 용어 치환 (일감 -> 이슈, 결함 -> 버그 등 실무 용어화)
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml && \
    sed -i 's/새 일감/새 이슈/g' config/locales/ko.yml

# [5] 플러그인 설치
RUN git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize && \
    git clone --depth 1 https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs && \
    git clone --depth 1 https://github.com/akiko-pusu/redmine_issue_templates.git plugins/redmine_issue_templates

# [6] UI 디자인 및 PDF 설정 자동 주입 스크립트
RUN echo "if ViewCustomize.where(path_pattern: '.*').empty?; \
  ViewCustomize.create!( \
    path_pattern: '.*', \
    customization_type: 'style', \
    code: \"body, #content, #header, #footer { font-family: 'Pretendard Variable', 'Pretendard', sans-serif !important; } \
           h1, h2, h3 { font-family: 'Pretendard Variable', sans-serif !important; font-weight: 600; } \
           pre, code, .wiki-code, textarea { font-family: 'D2Coding', monospace !important; }\", \
    enabled: true, \
    comments: 'Production UI' \
  ); end" > /usr/src/redmine/init_all.rb

# [7] 권한 정리 및 빌드
RUN chown -R redmine:redmine /usr/src/redmine /usr/local/bundle
RUN cd plugins/redmine_wbs && npm install && npm run production
RUN bundle install --without development test