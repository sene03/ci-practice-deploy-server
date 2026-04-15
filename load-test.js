// load-test.js
import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  vus: 50, // 동시 사용자 50명
  duration: "30s", // 30초간
};

export default function () {
  const res = http.get("http://172.21.33.26:8303/recommendations");

  check(res, {
    "status 200": (r) => r.status === 200,
    "response < 500ms": (r) => r.timings.duration < 500,
  });

  sleep(1);
}
