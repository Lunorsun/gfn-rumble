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
SWIFT_NO_UPDATE=$(ls GFNRumble/*.swift | grep -v UpdateCheck.swift)
JS=$(ls GFNRumble/*.js)
JS_NO_2K=$(ls GFNRumble/*.js | grep -v resolution-2k.js)

# 1) 앱 전체: 인터넷 직접 접속, 기록(로그), 클립보드, 비공개 API 금지
#    (예외: 새 버전 알림 UpdateCheck.swift 한 곳 — 아래 4번에서 따로 검사)
check "인터넷 직접 접속" 'URLSession|NSURLConnection|NWConnection|NWListener|CFStreamCreatePairWithSocket|Data\(contentsOf: *URL\(string' $SWIFT_NO_UPDATE
check "웹 검사기 켜기" 'isInspectable' $SWIFT
check "기록(로그)" '(^|[^A-Za-z_.])print\(|NSLog\(|os_log\(|Logger\(' $SWIFT
check "클립보드" 'UIPasteboard' $SWIFT
check "비공개 API" '_setEnabled|forFeature:|_features|_webViewDidRequestPointerLock|NSClassFromString|performSelector' $SWIFT
check "JS 인터넷 접속" 'XMLHttpRequest|new WebSocket|EventSource|sendBeacon|(^|[^A-Za-z_.])fetch\(|console\.log' $JS_NO_2K
check "기기 위장" 'maxTouchPoints|WorkerNavigator|navigator\.platform' $JS

# 2) 2K 기능: 지포스 나우 요청 고치기는 resolution-2k.js 한 곳에서만, 설정이 켜졌을 때만
#    (MessageOrigin.swift는 허용 주소 목록에 nvidiagrid.net이 있어서 제외 — 5번에서 목록 자체를 고정 검사)
check "지포스 나우 요청 고치기가 다른 파일에 있음" 'nvidiagrid|v2/session|clientRequestMonitorSettings' $JS_NO_2K $(ls GFNRumble/*.swift | grep -v MessageOrigin.swift)
grep -q 'function enabled() { return !!(window.__gfnConfig && window.__gfnConfig.request2K); }' GFNRumble/resolution-2k.js \
  || { echo "::error::보안 검사 실패 - 2K 기능의 켜짐 확인이 사라졌어요"; fail=1; }
check "2K 기능이 새 주소로 보냄" 'new WebSocket|EventSource|sendBeacon|console\.log' GFNRumble/resolution-2k.js

# 3) 만료 알림: 서명 파일에서 ExpirationDate 하나만 읽기, 저장·접속·기록 금지
E=GFNRumble/ExpiryMonitor.swift
check "만료 알림이 저장/접속을 씀" 'UserDefaults|FileManager|\.write\(|URLSession|WKWebView|evaluateJavaScript' $E
others=$(grep -oE 'dictionary\["[A-Za-z]+"\]' $E | grep -v 'dictionary\["ExpirationDate"\]' || true)
if [ -n "$others" ]; then echo "::error::보안 검사 실패 - 만료 알림이 다른 값을 읽음: $others"; fail=1; fi

# 4) 새 버전 알림: 고정 주소 하나만, 읽기(GET)만, 쿠키·캐시 없이
U=GFNRumble/UpdateCheck.swift
urls=$(grep -oE 'URL\(string: *"[^"]*"' $U | sort -u)
if [ "$urls" != 'URL(string: "https://github.com/Lunorsun/gfn-rumble/releases/latest/download/source.json"' ]; then
  echo "::error::보안 검사 실패 - 새 버전 알림의 주소가 바뀌었거나 늘었어요: $urls"; fail=1
fi
check "새 버전 알림이 무언가를 보냄" 'httpBody|uploadTask|"POST"|"PUT"|webSocketTask|downloadTask|UserDefaults\.standard\.dictionaryRepresentation' $U
grep -q 'URLSessionConfiguration.ephemeral' $U \
  || { echo "::error::보안 검사 실패 - 새 버전 알림이 기록 없는(ephemeral) 연결을 쓰지 않아요"; fail=1; }

# 5) 앱 통로: 모든 메시지 받는 곳에 출처 확인(MessageOrigin.isTrusted)이 있어야 함
for f in $SWIFT; do
  handlers=$(grep -c 'didReceive message: WKScriptMessage' "$f" || true)
  guards=$(grep -c 'MessageOrigin.isTrusted(message)' "$f" || true)
  if [ "$handlers" -gt 0 ] && [ "$guards" -lt "$handlers" ]; then
    echo "::error::보안 검사 실패 - $f: 메시지 받는 곳 ${handlers}개 중 출처 확인 ${guards}개"; fail=1
  fi
done
grep -q 'static let trustedDomains = \["geforcenow.com", "nvidia.com", "nvidiagrid.net"\]' GFNRumble/MessageOrigin.swift \
  || { echo "::error::보안 검사 실패 - 통로 허용 주소 목록이 바뀌었어요"; fail=1; }
grep -q 'origin.protocol == "https"' GFNRumble/MessageOrigin.swift \
  || { echo "::error::보안 검사 실패 - 통로 출처 확인에서 https 확인이 빠졌어요"; fail=1; }

# 6) 설정 백업: 앱 설정('settings.')만, 인터넷 없이
B=GFNRumble/SettingsBackup.swift
check "설정 백업이 인터넷을 씀" 'URLSession|URL\(string|WKWebView' $B
grep -q 'private static let prefix = "settings."' $B \
  || { echo "::error::보안 검사 실패 - 설정 백업 범위('settings.')가 바뀌었어요"; fail=1; }

if [ $fail -ne 0 ]; then exit 1; fi
echo "보안 검사 통과"
