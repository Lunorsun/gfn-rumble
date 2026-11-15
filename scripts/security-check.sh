#!/bin/bash
# GFN Rumble 보안 벽: 금지된 코드가 들어가면 빌드를 멈춥니다.
set -u
cd "$(dirname "$0")/.."
fail=0

check() {  # check "설명" "정규식" 파일...
  local what="$1" pattern="$2"; shift 2
  local hits
  hits=$(grep -nE "$pattern" "$@" 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "::error::보안 검사 실패 - $what"
    echo "$hits"
    fail=1
  fi
}

SWIFT=$(ls GFNRumble/*.swift)
JS=$(ls GFNRumble/*.js)
JS_NO_2K=$(ls GFNRumble/*.js | grep -v resolution-2k.js)

# 1) 앱 전체: 인터넷 직접 접속, 기록(로그), 클립보드, 비공개 API 금지
check "인터넷 직접 접속" 'URLSession|NSURLConnection|NWConnection|NWListener|CFStreamCreatePairWithSocket' $SWIFT
check "기록(로그)" '(^|[^A-Za-z_.])print\(|NSLog\(|os_log\(|Logger\(' $SWIFT
check "클립보드" 'UIPasteboard' $SWIFT
check "비공개 API" '_setEnabled|forFeature:|_features|_webViewDidRequestPointerLock|NSClassFromString|performSelector' $SWIFT
check "JS 인터넷 접속" 'XMLHttpRequest|new WebSocket|EventSource|sendBeacon|(^|[^A-Za-z_.])fetch\(|console\.log' $JS_NO_2K
check "기기 위장" 'maxTouchPoints|WorkerNavigator|navigator\.platform' $JS

# 2) 2K 기능: 지포스 나우 요청 고치기는 resolution-2k.js 한 곳에서만, 설정이 켜졌을 때만
check "지포스 나우 요청 고치기가 다른 파일에 있음" 'nvidiagrid|v2/session|clientRequestMonitorSettings' $JS_NO_2K $SWIFT
grep -q 'function enabled() { return !!(window.__gfnConfig && window.__gfnConfig.request2K); }' GFNRumble/resolution-2k.js \
  || { echo "::error::보안 검사 실패 - 2K 기능의 켜짐 확인이 사라졌어요"; fail=1; }
check "2K 기능이 새 주소로 보냄" 'new WebSocket|EventSource|sendBeacon|console\.log' GFNRumble/resolution-2k.js

# 3) 만료 알림: 서명 파일에서 ExpirationDate 하나만 읽기, 저장·접속·기록 금지
E=GFNRumble/ExpiryMonitor.swift
check "만료 알림이 저장/접속을 씀" 'UserDefaults|FileManager|\.write\(|URLSession|WKWebView|evaluateJavaScript' $E
others=$(grep -oE 'dictionary\["[A-Za-z]+"\]' $E | grep -v 'dictionary\["ExpirationDate"\]' || true)
if [ -n "$others" ]; then echo "::error::보안 검사 실패 - 만료 알림이 다른 값을 읽음: $others"; fail=1; fi

if [ $fail -ne 0 ]; then exit 1; fi
echo "보안 검사 통과"
