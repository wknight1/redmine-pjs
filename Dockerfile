# [1] 베이스 이미지
FROM redmine:6.1.1

USER root

# [2] 필수 패키지 설치
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales locales-all tzdata fonts-nanum \
    git curl unzip fontconfig build-essential libpq-dev nodejs npm \
    libyaml-dev pkg-config ghostscript \
    && rm -rf /var/lib/apt/lists/*

# [3] 유명 한글 무료 폰트 설치 (안정적인 공식 링크로 전면 교체)
RUN mkdir -p /usr/share/fonts/truetype/custom && cd /usr/share/fonts/truetype/custom && \
    # 1. Pretendard (가독성 1위)
    curl -fLo Pretendard.zip https://github.com/orioncactus/pretendard/releases/download/v1.3.9/Pretendard-1.3.9.zip && \
    unzip -q Pretendard.zip -d Pretendard && \
    # 2. D2Coding (네이버 코딩 폰트)
    curl -fLo D2Coding.zip https://github.com/naver/d2codingfont/releases/download/VER1.3.2/D2Coding-Ver1.3.2-20180524.zip && \
    unzip -q D2Coding.zip -d D2Coding && \
    # 3. Spoqa Han Sans Neo (세련된 고딕)
    curl -fLo Spoqa.zip https://github.com/spoqa/spoqa-han-sans/releases/download/v3.0.0/SpoqaHanSansNeo_all.zip && \
    unzip -q Spoqa.zip -d Spoqa && \
    # 정리 및 캐시 갱신
    rm *.zip && fc-cache -f -v

ENV LANG=ko_KR.UTF-8 TZ=Asia/Seoul
WORKDIR /usr/src/redmine

# [4] 용어 치환 (일감 -> 이슈)
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml

# [5] 플러그인 설치
RUN git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize && \
    git clone --depth 1 https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs && \
    git clone --depth 1 https://github.com/akiko-pusu/redmine_issue_templates.git plugins/redmine_issue_templates

# [6] UI 디자인 자동화 스크립트 (3종 폰트 완벽 반영)
RUN echo "if ViewCustomize.where(path_pattern: '.*').empty?; \
  ViewCustomize.create!( \
    path_pattern: '.*', \
    customization_type: 'style', \
    code: \"body, #content, #header, #footer { font-family: 'Pretendard Variable', 'Pretendard', 'Spoqa Han Sans Neo', sans-serif !important; } \
           h1, h2, h3 { font-family: 'Pretendard Variable', sans-serif !important; font-weight: 600; } \
           pre, code, .wiki-code, textarea { font-family: 'D2Coding', monospace !important; }\", \
    enabled: true, \
    comments: 'Production UI Auto-Config' \
  ); puts 'UI 디자인 자동 주입 완료!'; end" > /usr/src/redmine/init_ui.rb

# [7] 권한 정리 및 빌드
RUN chown -R redmine:redmine /usr/src/redmine
RUN cd plugins/redmine_wbs && npm install && npm run production
RUN bundle install --without development test