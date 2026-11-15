// GFN Rumble 실험 기능: 해상도 강제 요청(1080p~2K) + 실제 화질 확인
// 요청 고치기는 설정에서 '해상도 강제 요청'을 켰을 때만 동작합니다(기본 꺼짐).
// - 지포스 나우가 게임을 시작할 때 보내는 요청(/v2/session)의 '원하는 해상도' 숫자만 바꿉니다.
//   요청은 원래 가던 지포스 나우 서버로만 갑니다. 새 주소로 보내는 것은 없습니다.
// - 받은 영상의 해상도·fps·손실률 숫자만 앱(네이티브)에 알려 줍니다.
// NVIDIA 약관상 '클라이언트 수정'에 해당할 수 있어요. 사용자가 위험을 알고 켜는 기능입니다.
(function () {
  'use strict';
  if (window.top !== window || window.__gfnRes2K) return;
  window.__gfnRes2K = true;

  try {
    function post(msg) {
      try { window.webkit.messageHandlers.quality.postMessage(msg); } catch (e) {}
    }
    var FPS = 60;
    function target() {
      var c = window.__gfnConfig || {};
      var w = Number(c.resWidth), h = Number(c.resHeight);
      if (!(w >= 640 && w <= 3840 && h >= 480 && h <= 2160)) { w = 2560; h = 1440; }
      return { w: Math.round(w), h: Math.round(h) };
    }

    function enabled() { return !!(window.__gfnConfig && window.__gfnConfig.request2K); }

    function isSessionRequest(url, method) {
      if (String(method || 'GET').toUpperCase() !== 'POST') return false;
      try {
        var u = new URL(String(url), location.href);
        return /\.nvidiagrid\.net$/i.test(u.hostname) && u.pathname.indexOf('/v2/session') !== -1;
      } catch (e) { return false; }
    }

    // 요청 본문에서 해상도 숫자만 바꿉니다. 실패하면 원래 본문 그대로.
    function patchBody(text) {
      try {
        var data = JSON.parse(text);
        var size = target(), WIDTH = size.w, HEIGHT = size.h;
        var req = data && data.sessionRequestData;
        if (!req) return text;
        var monitors = req.clientRequestMonitorSettings;
        if (monitors && monitors.length) {
          for (var i = 0; i < monitors.length; i++) {
            monitors[i].widthInPixels = WIDTH;
            monitors[i].heightInPixels = HEIGHT;
            monitors[i].framesPerSecond = FPS;
          }
        }
        var meta = req.metaData;
        if (meta && meta.length) {
          for (var j = 0; j < meta.length; j++) {
            if (meta[j] && meta[j].key === 'clientPhysicalResolution') {
              meta[j].value = JSON.stringify({ horizontalPixels: WIDTH, verticalPixels: HEIGHT });
            }
          }
        }
        return JSON.stringify(data);
      } catch (e) { return text; }
    }

    // 서버가 거부하면 앱에 알려서 다음부터 원래 해상도로 돌립니다.
    function checkResponse(response) {
      try {
        if (response && !response.ok) post({ type: 'sessionFailed', status: response.status });
      } catch (e) {}
      return response;
    }

    // fetch: 지포스 나우가 보내는 요청을 가로채 숫자만 바꿉니다.
    var originalFetch = window.fetch;
    if (typeof originalFetch === 'function') {
      window.fetch = function (input, init) {
        var self = this;
        try {
          if (enabled()) {
            var url = (input && input.url) || input;
            var method = (init && init.method) || (input && input.method);
            if (isSessionRequest(url, method)) {
              if (init && typeof init.body === 'string') {
                var copy = {};
                for (var k in init) copy[k] = init[k];
                copy.body = patchBody(init.body);
                return originalFetch.call(self, input, copy).then(checkResponse);
              }
              if (!init && typeof Request === 'function' && input instanceof Request) {
                return input.clone().text().then(function (text) {
                  return originalFetch.call(self, new Request(input, { body: patchBody(text) }));
                }).then(checkResponse);
              }
            }
          }
        } catch (e) {}
        return originalFetch.apply(self, arguments);
      };
    }
    // XMLHttpRequest도 같은 방식으로
    var XHR = window.XMLHttpRequest;
    if (XHR && XHR.prototype) {
      var open = XHR.prototype.open, send = XHR.prototype.send;
      XHR.prototype.open = function (method, url) {
        this.__gfn2k = isSessionRequest(url, method);
        return open.apply(this, arguments);
      };
      XHR.prototype.send = function (body) {
        try {
          if (this.__gfn2k && enabled() && typeof body === 'string') {
            var xhr = this;
            xhr.addEventListener('loadend', function () {
              if (xhr.status >= 400) post({ type: 'sessionFailed', status: xhr.status });
            });
            return send.call(this, patchBody(body));
          }
        } catch (e) {}
        return send.apply(this, arguments);
      };
    }

    // 받은 영상 화질 확인 (5초마다 숫자만 앱으로)
    var PC = window.RTCPeerConnection;
    if (typeof PC === 'function') {
      var Wrapped = function () {
        var pc = new (Function.prototype.bind.apply(PC, [null].concat(Array.prototype.slice.call(arguments))))();
        watch(pc);
        return pc;
      };
      Wrapped.prototype = PC.prototype;
      for (var key in PC) { try { Wrapped[key] = PC[key]; } catch (e) {} }
      try { Object.defineProperty(Wrapped, 'name', { value: 'RTCPeerConnection' }); } catch (e) {}
      window.RTCPeerConnection = Wrapped;
    }

    function watch(pc) {
      var started = 0, lastFrames = 0, lastLost = 0, lastRecv = 0, timer = null;
      function tick() {
        if (pc.connectionState === 'closed') { clearInterval(timer); return; }
        pc.getStats().then(function (report) {
          report.forEach(function (s) {
            if (s.type !== 'inbound-rtp' || s.kind !== 'video') return;
            if (!started) { started = Date.now(); post({ type: 'streamStarted' }); }
            var frames = s.framesDecoded || 0;
            var lost = s.packetsLost || 0, recv = s.packetsReceived || 0;
            var dLost = lost - lastLost, dRecv = recv - lastRecv;
            post({
              type: 'stats',
              width: s.frameWidth || 0,
              height: s.frameHeight || 0,
              fps: lastFrames ? (frames - lastFrames) / 5 : (s.framesPerSecond || 0),
              loss: dLost > 0 && dRecv + dLost > 0 ? (100 * dLost) / (dRecv + dLost) : 0,
              seconds: (Date.now() - started) / 1000
            });
            lastFrames = frames; lastLost = lost; lastRecv = recv;
          });
        }).catch(function () {});
      }
      timer = setInterval(tick, 5000);
    }
  } catch (e) {}
})();
