#!/bin/bash
set -e

CANARY_TAG=$1
CANARY_WEIGHT=${2:-10}
APP_DIR=/home/sw_team_4/ci-practice-deploy-server

cd $APP_DIR

# ── 0. 사전 헬스체크: stable 살아있는지 확인 ──────
echo ">>> stable 헬스체크..."
STABLE_STATUS=$(docker inspect --format='{{.State.Health.Status}}' \
    sw_team4_spring_stable 2>/dev/null || echo "none")

if [ "$STABLE_STATUS" != "healthy" ]; then
    echo "❌ stable 서버가 healthy하지 않음: $STABLE_STATUS"
    echo "배포 중단 - stable 서버 점검 필요"
    exit 1
fi
echo "✅ stable 정상 확인"

# ── 1. .env 업데이트 ──────────────────────────────
sed -i "s/CANARY_TAG=.*/CANARY_TAG=${CANARY_TAG}/" .env

# ── 1.5 기존 이미지 정리 (현재 태그 제외) ───────────
echo ">>> 기존 이미지 정리..."

CURRENT_CANARY_TAG=${CANARY_TAG}
CURRENT_STABLE_TAG=$(grep STABLE_TAG .env | cut -d'=' -f2)

docker images "jaypark0205/recommendation-api" --format "{{.Repository}}:{{.Tag}}" | \
grep -v "$CURRENT_CANARY_TAG" | \
grep -v "$CURRENT_STABLE_TAG" | \
xargs -r docker rmi -f

echo "✅ 사용하지 않는 이미지 정리 완료"

# ── 2. canary pull & 재시작 ───────────────────────
docker compose pull spring-canary
docker compose up -d --no-deps spring-canary

# ── 3. canary 헬스체크 ────────────────────────────
echo ">>> canary 헬스체크..."
CANARY_STATUS=""
for i in $(seq 1 10); do
    CANARY_STATUS=$(docker inspect --format='{{.State.Health.Status}}' \
        sw_team4_spring_canary 2>/dev/null || echo "none")

    if [ "$CANARY_STATUS" = "healthy" ]; then
        echo "✅ canary 정상 확인"
        break
    fi

    echo "대기중... ($i/10) 현재상태: $CANARY_STATUS"
    sleep 5
done

if [ "$CANARY_STATUS" != "healthy" ]; then
    echo "❌ canary 헬스체크 실패 - 롤백"
    STABLE_TAG=$(grep STABLE_TAG .env | cut -d'=' -f2)
    sed -i "s/CANARY_TAG=.*/CANARY_TAG=${STABLE_TAG}/" .env
    docker compose up -d --no-deps spring-canary
    exit 1
fi

# ── 4. 둘 다 healthy → Nginx 비율 적용 ───────────
cp $APP_DIR/nginx/conf.d/canary_${CANARY_WEIGHT}.conf \
   $APP_DIR/nginx/conf.d/default.conf

docker compose exec nginx nginx -s reload

echo "✅ 배포 완료: canary ${CANARY_WEIGHT}% 트래픽 적용"
