import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '30s', target: 10 },   // ramp up
    { duration: '60s', target: 50 },   // sustain → triggers scale-up
    { duration: '30s', target: 0  },   // ramp down → triggers scale-down
  ],
  thresholds: {
    http_req_failed:   ['rate<0.01'],
    http_req_duration: ['p(95)<2000'],
  },
};

export default function () {
  let res = http.post(
    'http://127.0.0.1:8080/function/factorial',
    '10',
    { headers: { 'Content-Type': 'text/plain' } }
  );
  check(res, {
    'status 200':     (r) => r.status === 200,
    'correct answer': (r) => r.body.trim() === '3628800',
  });
  sleep(0.1);
}
