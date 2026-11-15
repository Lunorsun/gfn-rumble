// GFN Rumble 실험 기능: 게임 소리 → 햅틱
// 지포스 나우 게임 소리를 이 웹페이지 안에서만 분석해서, 저음 세기(왼쪽·오른쪽 숫자 두 개)만 앱에 보냅니다.
// 녹음·저장·전송 없음. 소리는 원래대로 들립니다. 설정에서 켰을 때만 동작합니다.
(function () {
  'use strict';
  if (window.top !== window || window.__gfnAudioHaptics) return;
  window.__gfnAudioHaptics = true;

  try {
    var AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;

    var enabled = false, band = 0;
    var ctx = null, current = null, nodes = null, timer = null;
    var lastL = -1, lastR = -1;

    function post(l, r) {
      try { window.webkit.messageHandlers.audiohaptics.postMessage({ l: l, r: r }); } catch (e) {}
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
      if (nodes) { try { nodes.source.disconnect(); } catch (e) {} }
      nodes = null;
      current = null;
      if (lastL !== 0 || lastR !== 0) post(0, 0);
      lastL = 0; lastR = 0;
    }

    function setup(stream) {
      teardown();
      if (!ctx) ctx = new AC();
      if (ctx.state === 'suspended' && ctx.resume) ctx.resume();
      var source = ctx.createMediaStreamSource(stream);
      var split = ctx.createChannelSplitter(2);
      source.connect(split);
      function chain(ch) {
        var f = ctx.createBiquadFilter();
        f.type = 'lowpass';
        f.frequency.value = band === 0 ? 160 : 700;
        var a = ctx.createAnalyser();
        a.fftSize = 512;
        split.connect(f, ch);
        f.connect(a);
        return { filter: f, analyser: a, buf: new Float32Array(a.fftSize) };
      }
      // 분석만 하고 스피커로는 보내지 않습니다(원래 소리는 영상 요소가 그대로 재생).
      nodes = { source: source, left: chain(0), right: chain(1) };
      current = stream;
    }

    function rms(ch) {
      ch.analyser.getFloatTimeDomainData(ch.buf);
      var sum = 0;
      for (var i = 0; i < ch.buf.length; i++) sum += ch.buf[i] * ch.buf[i];
      return Math.sqrt(sum / ch.buf.length);
    }

    function tick() {
      if (!enabled) return;
      var stream = findStream();
      if (stream !== current) {
        if (stream) { try { setup(stream); } catch (e) { teardown(); } } else teardown();
      }
      if (!nodes) return;
      if (ctx.state === 'suspended' && ctx.resume) ctx.resume();
      var l = Math.min(1, rms(nodes.left) * 3);
      var r = Math.min(1, rms(nodes.right) * 3);
      l = Math.round(l * 100) / 100;
      r = Math.round(r * 100) / 100;
      if (Math.abs(l - lastL) >= 0.02 || Math.abs(r - lastR) >= 0.02 || ((l || r) && !(lastL || lastR))) {
        lastL = l; lastR = r;
        post(l, r);
      }
    }

    function onConfig(c) {
      var on = !!(c && c.audioHaptics);
      var newBand = c && c.audioHapticsBand === 1 ? 1 : 0;
      if (newBand !== band) {
        band = newBand;
        if (nodes) { nodes.left.filter.frequency.value = band === 0 ? 160 : 700; nodes.right.filter.frequency.value = band === 0 ? 160 : 700; }
      }
      if (on && !enabled) {
        enabled = true;
        timer = setInterval(tick, 20);
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
