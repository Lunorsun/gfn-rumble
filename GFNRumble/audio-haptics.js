// GFN Rumble 실험 기능: 게임 소리 → 햅틱 (듀얼센스)
// 지포스 나우 게임 소리를 이 웹페이지 안에서만 분석해서, 숫자 14개만 앱에 보냅니다:
//   음역 5개(초저음·저음·중음·중고음·고음) × 왼/오 + 킥(쿠웅) 왼/오 + 타격(탁) 왼/오  (각 0~1)
// 녹음·저장·전송 없음. 소리는 원래대로 들립니다. 설정에서 켰을 때만 동작합니다.
(function () {
  'use strict';
  if (window.top !== window || window.__gfnAudioHaptics) return;
  window.__gfnAudioHaptics = true;

  try {
    var AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;

    var enabled = false;
    var ctx = null, current = null, graph = null, timer = null;
    var N = 14;
    function zeros() { var a = []; for (var i = 0; i < N; i++) a.push(0); return a; }
    var last = zeros();
    var avgLow = [0, 0], avgHigh = [0, 0];   // 킥·타격 감지용 평균 에너지 (왼, 오)
    var coolLow = [0, 0], coolHigh = [0, 0]; // 너무 자주 나오지 않게

    function post(values) {
      try { window.webkit.messageHandlers.audiohaptics.postMessage({ v: values }); } catch (e) {}
    }

    function findStream() {
      var media = document.querySelectorAll('video, audio');
      for (var i = 0; i < media.length; i++) {
        var s = media[i].srcObject;
        if (s && s.getAudioTracks && s.getAudioTracks().length) return s;
      }
      return null;
    }

    function teardown() {
      if (graph) { try { graph.source.disconnect(); } catch (e) {} }
      graph = null;
      current = null;
      post(zeros());
      last = zeros();
    }

    // 한 채널에서 음역 하나를 뽑는 필터 + 분석기
    function band(split, ch, lowCut, highCut, size) {
      var node = null, first = null;
      function add(f) { if (node) node.connect(f); else first = f; node = f; }
      if (lowCut) { var hp = ctx.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = lowCut; add(hp); }
      if (highCut) { var lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = highCut; add(lp); }
      var a = ctx.createAnalyser();
      a.fftSize = size;
      a.smoothingTimeConstant = 0;
      add(a);
      split.connect(first, ch);
      return { analyser: a, buf: new Float32Array(size) };
    }

    function setup(stream) {
      teardown();
      if (!ctx) ctx = new AC();
      if (ctx.state === 'suspended' && ctx.resume) ctx.resume();
      var source = ctx.createMediaStreamSource(stream);
      var split = ctx.createChannelSplitter(2);
      source.connect(split);
      // 분석만 하고 스피커로는 보내지 않습니다(원래 소리는 영상 요소가 그대로 재생).
      graph = {
        source: source,
        bands: [
          [band(split, 0, 0, 90, 1024), band(split, 1, 0, 90, 1024)],          // 초저음 (폭발·엔진·킥드럼)
          [band(split, 0, 90, 250, 512), band(split, 1, 90, 250, 512)],        // 저음 (충격·베이스)
          [band(split, 0, 250, 1000, 256), band(split, 1, 250, 1000, 256)],    // 중음 (목소리·악기 몸통)
          [band(split, 0, 1000, 4000, 256), band(split, 1, 1000, 4000, 256)],  // 중고음 (총소리·스네어)
          [band(split, 0, 4000, 12000, 128), band(split, 1, 4000, 12000, 128)] // 고음 (하이햇·금속·파편)
        ]
      };
      current = stream;
    }

    function rms(b) {
      b.analyser.getFloatTimeDomainData(b.buf);
      var sum = 0;
      for (var i = 0; i < b.buf.length; i++) sum += b.buf[i] * b.buf[i];
      return Math.sqrt(sum / b.buf.length);
    }

    function round(v) { return Math.round(Math.min(1, Math.max(0, v)) * 100) / 100; }

    function tick() {
      if (!enabled) return;
      var stream = findStream();
      if (stream !== current) {
        if (stream) { try { setup(stream); } catch (e) { teardown(); } } else if (graph) teardown();
      }
      if (!graph) return;
      if (ctx.state === 'suspended' && ctx.resume) ctx.resume();

      var out = [];
      for (var b = 0; b < 5; b++) {
        out.push(round(rms(graph.bands[b][0]) * 4));
        out.push(round(rms(graph.bands[b][1]) * 4));
      }
      // 킥(쿠웅): 초저음+저음이 갑자기 뛰면 / 타격(탁): 중고음+고음이 갑자기 뛰면
      var kicks = [0, 0], hits = [0, 0];
      for (var side = 0; side < 2; side++) {
        var low = out[0 + side] + out[2 + side];
        if (coolLow[side] > 0) coolLow[side]--;
        else if (low > 0.15 && low > avgLow[side] * 1.8) { kicks[side] = Math.min(1, (low - avgLow[side]) * 1.5); coolLow[side] = 12; }
        avgLow[side] = avgLow[side] * 0.95 + low * 0.05;
        var high = out[6 + side] + out[8 + side];
        if (coolHigh[side] > 0) coolHigh[side]--;
        else if (high > 0.1 && high > avgHigh[side] * 2.0) { hits[side] = Math.min(1, (high - avgHigh[side]) * 1.8); coolHigh[side] = 8; }
        avgHigh[side] = avgHigh[side] * 0.93 + high * 0.07;
      }
      out.push(round(kicks[0]), round(kicks[1]), round(hits[0]), round(hits[1]));

      var changed = false;
      for (var i = 0; i < N; i++) if (Math.abs(out[i] - last[i]) >= 0.02 || (out[i] > 0) !== (last[i] > 0)) changed = true;
      if (changed || out[10] || out[11] || out[12] || out[13]) { last = out; post(out); }
    }

    function onConfig(c) {
      var on = !!(c && c.audioHaptics);
      if (on && !enabled) {
        enabled = true;
        timer = setInterval(tick, 8);    // 1초에 약 120번
      } else if (!on && enabled) {
        enabled = false;
        clearInterval(timer);
        timer = null;
        teardown();
      }
    }

    // 브라우저 정책상 소리 분석은 화면을 한 번 터치해야 시작될 수 있어요.
    function resume() { if (ctx && ctx.state === 'suspended' && ctx.resume) ctx.resume(); }
    document.addEventListener('touchstart', resume, true);
    document.addEventListener('keydown', resume, true);

    onConfig(window.__gfnConfig);
    if (window.__gfnConfigListeners) window.__gfnConfigListeners.push(onConfig);
  } catch (e) {}
})();
