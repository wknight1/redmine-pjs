# [1] 베이스 이미지
FROM redmine:6.1.1

USER root

# [2] 필수 패키지 설치
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales locales-all tzdata fonts-nanum \
    git curl unzip wget fontconfig build-essential libpq-dev nodejs npm \
    libyaml-dev pkg-config ghostscript \
    && rm -rf /var/lib/apt/lists/*

# [3] 유명 한글 무료 폰트 수동 추가 (우회 경로 및 D2Coding 포함)
RUN mkdir -p /usr/share/fonts/truetype/custom && \
    # Pretendard
    wget https://github.com/orioncactus/pretendard/releases/download/v1.3.9/Pretendard-1.3.9.zip && \
    unzip Pretendard-1.3.9.zip -d /usr/share/fonts/truetype/custom/Pretendard && \
    # Gmarket Sans (Github 미러 사용으로 403 에러 해결)
    wget https://github.com/hbin9339/font-mirror/raw/main/GmarketSans.zip && \
    unzip GmarketSans.zip -d /usr/share/fonts/truetype/custom/GmarketSans && \
    # D2Coding (네이버 코딩 폰트 추가)
    wget https://github.com/naver/d2codingfont/releases/download/VER1.3.2/D2Coding-Ver1.3.2-20180524.zip && \
    unzip D2Coding-Ver1.3.2-20180524.zip -d /usr/share/fonts/truetype/custom/D2Coding && \
    # 정리 및 캐시 갱신
    rm Pretendard-1.3.9.zip GmarketSans.zip D2Coding-Ver1.3.2-20180524.zip && fc-cache -f -v

ENV LANG=ko_KR.UTF-8 TZ=Asia/Seoul
WORKDIR /usr/src/redmine

# [4] 용어 치환 (일감 -> 이슈) 및 플러그인 설치
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml
RUN git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize && \
    git clone --depth 1 https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs && \
    git clone --depth 1 https://github.com/akiko-pusu/redmine_issue_templates.git plugins/redmine_issue_templates

# [5] ★ UI 디자인 3종 폰트 자동 주입 스크립트 (Pretendard, Gmarket, D2Coding)
RUN echo "if ViewCustomize.where(path_pattern: '.*').empty?; \
  ViewCustomize.create!( \
    path_pattern: '.*', \
    customization_type: 'style', \
    code: \"/* 본문: 프리텐다드 */ \
           body, #content, #header, #footer { font-family: 'Pretendard Variable', 'Pretendard', sans-serif !important; } \
           /* 제목: G마켓 산스 */ \
           h1, h2, h3 { font-family: 'Gmarket Sans', sans-serif !important; font-weight: 500; } \
           /* 코드/데이터: D2Coding */ \
           pre, code, .wiki-code, textarea { font-family: 'D2Coding', monospace !important; }\", \
    enabled: true, \
    comments: 'UI/Typography Auto-Config' \
  ); puts 'UI 최적화 완료!'; end" > /usr/src/redmine/init_ui.rb

# [6] 권한 정리 및 빌드
RUN chown -R redmine:redmine /usr/src/redmine
RUN cd plugins/redmine_wbs && npm install && npm run production
RUN bundle install --without development test