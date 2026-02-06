# ==============================================================================
# STAGE 1: PostgreSQL 18.1 + 한국어 로케일
# ==============================================================================
FROM postgres:18.1 AS database

USER root

RUN apt-get update && apt-get install -y --no-install-recommends locales && \
    rm -rf /var/lib/apt/lists/* && \
    sed -i '/ko_KR.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen ko_KR.UTF-8

ENV LANG=ko_KR.UTF-8 \
    LC_ALL=ko_KR.UTF-8 \
    TZ=Asia/Seoul

# ==============================================================================
# STAGE 2: Redmine 6.1.1 + 한국어 완전 최적화 + 자동 UI 설정
# ==============================================================================
FROM redmine:6.1.1 AS application

USER root

# ==============================================================================
# [1] 시스템 패키지 + 한글 로케일
# ==============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales locales-all tzdata \
    fonts-nanum fonts-noto-cjk fontconfig \
    build-essential libpq-dev pkg-config \
    nodejs npm git curl unzip wget \
    ghostscript libyaml-dev postgresql-client \
    && rm -rf /var/lib/apt/lists/* && \
    sed -i '/ko_KR.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen ko_KR.UTF-8

# ==============================================================================
# [2] 한글 폰트 설치
# ==============================================================================
RUN mkdir -p /usr/share/fonts/truetype/custom && cd /usr/share/fonts/truetype/custom && \
    curl -fsSL -o pretendard.zip https://github.com/orioncactus/pretendard/releases/download/v1.3.9/Pretendard-1.3.9.zip && \
    unzip -q pretendard.zip -d Pretendard && \
    curl -fsSL -o d2coding.zip https://github.com/naver/d2codingfont/releases/download/VER1.3.2/D2Coding-Ver1.3.2-20180524.zip && \
    unzip -q d2coding.zip -d D2Coding && \
    rm -f *.zip && fc-cache -f -v

# ==============================================================================
# [3] 환경 변수
# ==============================================================================
ENV LANG=ko_KR.UTF-8 \
    LC_ALL=ko_KR.UTF-8 \
    TZ=Asia/Seoul \
    RAILS_ENV=production

WORKDIR /usr/src/redmine

# ==============================================================================
# [4] PDF 폰트 링크
# ==============================================================================
RUN mkdir -p public/fonts && \
    ln -sf /usr/share/fonts/truetype/nanum/NanumGothic.ttf public/fonts/NanumGothic.ttf && \
    ln -sf /usr/share/fonts/truetype/custom/Pretendard/public/static/Pretendard-Regular.otf public/fonts/Pretendard.otf

# ==============================================================================
# [5] 용어 현지화 (일감 → 이슈)
# ==============================================================================
RUN sed -i 's/일감/이슈/g' config/locales/ko.yml && \
    sed -i 's/새 일감/새 이슈/g' config/locales/ko.yml && \
    sed -i 's/하위 일감/하위 이슈/g' config/locales/ko.yml

# ==============================================================================
# [6] 플러그인 설치
# ==============================================================================
RUN git clone --depth 1 https://github.com/onozaty/redmine-view-customize.git plugins/view_customize && \
    git clone --depth 1 https://github.com/eXolnet/redmine_wbs.git plugins/redmine_wbs && \
    git clone --depth 1 https://github.com/akiko-pusu/redmine_issue_templates.git plugins/redmine_issue_templates && \
    find plugins -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

# ==============================================================================
# [7] 한국어 UI 자동 설정 Rake 태스크
# ==============================================================================
RUN mkdir -p lib/tasks && cat > lib/tasks/korean_ui.rake <<'RUBY'
namespace :redmine do
  desc 'Setup Korean UI customization (완전 자동화, 멱등성 보장)'
  task setup_korean_ui: :environment do
    puts ""
    puts "=" * 50
    puts "🎨 한국어 UI 커스터마이징 시작..."
    puts "=" * 50
    
    if defined?(ViewCustomize)
      # 중복 체크
      if ViewCustomize.exists?(comments: 'KBS Korean UI v2')
        puts "✓ 한국어 UI가 이미 설정되어 있습니다."
      else
        ViewCustomize.create!(
          path_pattern: '.*',
          customization_type: 'style',
          code: <<~CSS,
            /* ===================================== */
            /* KBS Korean UI - Pretendard 폰트 적용 */
            /* ===================================== */
            
            body, #content, #header, #footer,
            #main-menu, #sidebar, #top-menu,
            .wiki, p, div, span, li, td, th,
            input, textarea, select, button {
              font-family: 'Pretendard Variable', 'Pretendard', 'Noto Sans KR', 
                           -apple-system, BlinkMacSystemFont, 'Apple SD Gothic Neo',
                           sans-serif !important;
              letter-spacing: -0.02em;
              word-break: keep-all;
              word-wrap: break-word;
            }

            /* 제목 폰트 */
            h1, h2, h3, h4, h5, h6,
            .subject a, .title, .wiki h1, .wiki h2 {
              font-family: 'Pretendard Variable', 'Noto Sans KR', sans-serif !important;
              font-weight: 600;
              letter-spacing: -0.03em;
            }

            /* 코드/터미널 폰트 */
            pre, code, tt, kbd, samp,
            .wiki-code, .CodeMirror, 
            textarea[data-auto-complete],
            .syntaxhl, .code {
              font-family: 'D2Coding', 'D2Coding ligature', 
                           'Noto Sans Mono CJK KR', 
                           'Courier New', monospace !important;
              font-size: 13px;
              line-height: 1.6;
              letter-spacing: 0;
            }

            /* 위키 본문 가독성 */
            .wiki p, .wiki li, .journal .wiki {
              line-height: 1.8;
            }

            /* 테이블 헤더 */
            table.list th {
              font-weight: 600;
            }

            /* 버튼 가독성 */
            .button, input[type="submit"], input[type="button"] {
              font-weight: 500;
            }

            /* 한글 줄바꿈 최적화 */
            .description, .wiki-page {
              word-break: keep-all;
              overflow-wrap: break-word;
            }
          CSS
          enabled: true,
          comments: 'KBS Korean UI v2'
        )
        
        puts "✓ 한국어 UI 커스터마이징이 성공적으로 생성되었습니다!"
        puts "  - Pretendard 폰트 적용"
        puts "  - D2Coding 코드 폰트 적용"
        puts "  - 한글 가독성 최적화"
      end
    else
      puts "⚠ ViewCustomize 플러그인을 찾을 수 없습니다."
      puts "  플러그인 마이그레이션이 완료되었는지 확인하세요."
    end
    
    puts "=" * 50
    puts ""
  rescue => e
    puts "❌ UI 설정 중 오류 발생: #{e.message}"
    puts e.backtrace.first(5).join("\n")
  end
end
RUBY

# ==============================================================================
# [8] 디렉토리 준비
# ==============================================================================
RUN mkdir -p tmp/cache tmp/pids log files plugins/assets public/plugin_assets /home/redmine/.bundle

# ==============================================================================
# [9] WBS 플러그인 빌드
# ==============================================================================
RUN if [ -d plugins/redmine_wbs ]; then \
      cd plugins/redmine_wbs && \
      npm ci --no-audit --silent && \
      npm run production && \
      cd ../..; \
    fi

# ==============================================================================
# [10] Bundler 설정 + Gem 설치
# ==============================================================================
RUN bundle config set --local without 'development test' && \
    bundle config set --local jobs 4 && \
    bundle install

# ==============================================================================
# [11] 권한 설정
# ==============================================================================
RUN chown -R redmine:redmine /usr/src/redmine /usr/local/bundle /home/redmine

# ==============================================================================
# [12] 커스텀 Entrypoint (원본 보존 + 자동화 추가)
# ==============================================================================
RUN mv /docker-entrypoint.sh /docker-entrypoint-original.sh && \
    cat > /docker-entrypoint.sh <<'BASH'
#!/bin/bash
set -e

echo ""
echo "======================================"
echo "🚀 Redmine Korean Edition"
echo "   Version: 6.1.1"
echo "   Time: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "======================================"
echo ""

# 원본 entrypoint 함수화
run_original_entrypoint() {
    exec /docker-entrypoint-original.sh "$@"
}

# DB 연결 대기
wait_for_db() {
    echo "[1/4] 데이터베이스 연결 대기 중..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if PGPASSWORD="$REDMINE_DB_PASSWORD" psql \
            -h "$REDMINE_DB_POSTGRES" \
            -U "$REDMINE_DB_USERNAME" \
            -d "$REDMINE_DB_DATABASE" \
            -c "SELECT 1" > /dev/null 2>&1; then
            echo "✓ 데이터베이스 연결 성공"
            return 0
        fi
        echo "  시도 $attempt/$max_attempts..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo "❌ 데이터베이스 연결 실패"
    return 1
}

# 플러그인 마이그레이션 확인
check_plugin_migration() {
    echo "[2/4] 플러그인 마이그레이션 확인 중..."
    
    if bundle exec rails runner "puts ViewCustomize.table_exists?" 2>/dev/null | grep -q "true"; then
        echo "✓ View Customize 플러그인 준비 완료"
        return 0
    else
        echo "⚠ View Customize 테이블 미생성 (첫 실행 시 정상)"
        return 1
    fi
}

# 한국어 UI 설정
setup_korean_ui() {
    echo "[3/4] 한국어 UI 설정 중..."
    
    # 5초 대기 (Rails 완전 초기화)
    sleep 5
    
    if bundle exec rake redmine:setup_korean_ui RAILS_ENV=production 2>&1; then
        echo "✓ 한국어 UI 설정 완료"
    else
        echo "⚠ UI 설정 건너뜀 (서버는 정상 시작됨)"
    fi
}

# 메인 로직
main() {
    # 원본 entrypoint를 백그라운드로 실행
    run_original_entrypoint "$@" &
    REDMINE_PID=$!
    
    # DB 대기
    if wait_for_db; then
        # 플러그인 확인 후 UI 설정
        sleep 10  # Rails 초기화 대기
        if check_plugin_migration; then
            setup_korean_ui
        fi
    fi
    
    echo "[4/4] Redmine 서버 시작 완료"
    echo ""
    echo "======================================"
    echo "✅ 접속: http://localhost:3000"
    echo "   계정: admin / admin"
    echo "======================================"
    echo ""
    
    # 원본 프로세스 대기
    wait $REDMINE_PID
}

# 스크립트 실행
main "$@"
BASH

RUN chmod +x /docker-entrypoint.sh

# ==============================================================================
# [13] 헬스체크
# ==============================================================================
RUN echo '#!/bin/bash\ncurl -f -s http://localhost:3000/login > /dev/null || exit 1' > /healthcheck.sh && \
    chmod +x /healthcheck.sh

# ==============================================================================
# [최종] 사용자 및 포트 설정
# ==============================================================================
USER redmine
EXPOSE 3000

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["rails", "server", "-b", "0.0.0.0"]
