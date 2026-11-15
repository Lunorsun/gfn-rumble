// GFN Rumble 실험 기능: 게임 소리 → 햅틱 (듀얼센스)
// 지포스 나우 게임 소리를 이 웹페이지 안에서만 분석해서, 숫자 8개만 앱에 보냅니다:
//   [초저음 왼, 초저음 오, 저음 왼, 저음 오, 중고음 왼, 중고음 오, 타격 왼, 타격 오] (각 0~1)
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
    var last = [0, 0, 0, 0, 0, 0, 0, 0];
    var avg = [0, 0];          // 타격 감지용 평균 에너지 (왼, 오)
    var cooldown = [0, 0];     // 같은 쪽 타격이 너무 자주 나오지 않게

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
      post([0, 0, 0, 0, 0, 0, 0, 0]);
      last = [0, 0, 0, 0, 0, 0, 0, 0];
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
          [band(split, 0, 0, 90, 1024), band(split, 1, 0, 90, 1024)],       // 초저음 (폭발·엔진의 몸통)
          [band(split, 0, 90, 300, 512), band(split, 1, 90, 300, 512)],     // 저음 (충격·발소리)
          [band(split, 0, 900, 5000, 256), band(split, 1, 900, 5000, 256)]  // 중고음 (총소리·금속음)
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
      for (var b = 0; b < 3; b++) {
        out.push(round(rms(graph.bands[b][0]) * 4));
        out.push(round(rms(graph.bands[b][1]) * 4));
      }
      // 타격 감지: 저음+중고음 에너지가 평균보다 갑자기 크게 뛰면
      for (var side = 0; side < 2; side++) {
        var e = out[2 + side] + out[4 + side];
        var hit = 0;
        if (cooldown[side] > 0) cooldown[side]--;
        else if (e > 0.12 && e > avg[side] * 2.2) { hit = Math.min(1, (e - avg[side]) * 1.5); cooldown[side] = 4; }
        avg[side] = avg[side] * 0.9 + e * 0.1;
        out.push(round(hit));
      }

      var changed = false;
      for (var i = 0; i < 8; i++) if (Math.abs(out[i] - last[i]) >= 0.02 || (out[i] > 0) !== (last[i] > 0)) changed = true;
      if (changed || out[6] || out[7]) { last = out; post(out); }
    }

    function onConfig(c) {
      var on = !!(c && c.audioHaptics);
      if (on && !enabled) {
        enabled = true;
        timer = setInterval(tick, 16);   // 1초에 약 60번
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
