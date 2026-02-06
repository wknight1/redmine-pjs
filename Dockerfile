# [1] 베이스 이미지
FROM redmine:6.1.1

USER root

# [2] 필수 패키지 및 폰트 설치 (fonts-nanum-coding 제거)
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales locales-all tzdata fonts-nanum \
    git curl unzip wget fontconfig build-essential libpq-dev nodejs npm \
    libyaml-dev pkg-config ghostscript \
    && rm -rf /var/lib/apt/lists/*

# Pretendard & Gmarket Sans 설치 (UI 디자인 최적화)
RUN mkdir -p /usr/share/fonts/truetype/custom && \
    wget https://github.com/orioncactus/pretendard/releases/download/v1.3.9/Pretendard-1.3.9.zip && \
    unzip Pretendard-1.3.9.zip -d /usr/share/fonts/truetype/custom/Pretendard && \
    wget http://www.gmarket.co.kr/company/bbs/download.asp?idx=1 -O GmarketSans.zip && \
    unzip GmarketSans.zip -d /usr/share/fonts/truetype/custom/GmarketSans && \
    rm Pretendard-1.3.9.zip GmarketSans.zip && fc-cache -f -v

ENV LANG=ko_KR.UTF-8 TZ=Asia/Seoul

WORKDIR /usr/src/redmine

# [3] 용어 치환 자동화 (일감 -> 이슈)
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml

# [4] 플러그인 설치
RUN git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize && \
    git clone --depth 1 https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs && \
    git clone --depth 1 https://github.com/akiko-pusu/redmine_issue_templates.git plugins/redmine_issue_templates

# [5] UI 디자인 자동 주입 스크립트 생성
RUN echo "if ViewCustomize.where(path_pattern: '.*').empty?; \
  ViewCustomize.create!( \
    path_pattern: '.*', \
    customization_type: 'style', \
    code: \"body, #content, #header, #footer { font-family: 'Pretendard Variable', 'Pretendard', sans-serif !important; } \
           h1, h2, h3 { font-family: 'Gmarket Sans', sans-serif !important; font-weight: 500; }\", \
    enabled: true, \
    comments: 'Auto-configured Design' \
  ); puts 'Design Injected!'; end" > /usr/src/redmine/init_ui.rb

# [6] 권한 정리 및 빌드
RUN chown -R redmine:redmine /usr/src/redmine
RUN cd plugins/redmine_wbs && npm install && npm run production
RUN bundle install --without development test