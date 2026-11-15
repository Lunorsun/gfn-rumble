// GFN Rumble: 16:9 게임 화면을 4:3 아이패드 화면에 맞추는 방법 (전체 보이기 / 꽉 채우기 / 늘리기)
// 화면 표시 방식만 바꿉니다. 인터넷 접속 없음.
(function () {
  'use strict';
  if (window.top !== window || window.__gfnVideoFit) return;
  window.__gfnVideoFit = true;

  try {
    var FIT = { fit: 'contain', fill: 'cover', stretch: 'fill' };
    var mode = 'fit';

    function apply() {
      var style = document.getElementById('gfn-video-fit');
      if (mode === 'fit') {
        if (style && style.parentNode) style.parentNode.removeChild(style);
        return;
      }
      if (!document.documentElement) return;
      if (!style) {
        style = document.createElement('style');
        style.id = 'gfn-video-fit';
        (document.head || document.documentElement).appendChild(style);
      }
      var css = 'video { object-fit: ' + FIT[mode] + ' !important; }';
      if (style.textContent !== css) style.textContent = css;
    }

    function onConfig(c) {
      var m = c && c.videoFit;
      mode = FIT[m] ? m : 'fit';
      apply();
    }

    onConfig(window.__gfnConfig);
    if (window.__gfnConfigListeners) window.__gfnConfigListeners.push(onConfig);

    // 페이지가 다시 그려져 스타일이 사라지면 다시 넣습니다.
    var pending = false;
    function start() {
      new MutationObserver(function () {
        if (pending) return;
        pending = true;
        setTimeout(function () { pending = false; apply(); }, 1000);
      }).observe(document.documentElement, { childList: true, subtree: false });
      apply();
    }
    if (document.documentElement) start();
    else document.addEventListener('DOMContentLoaded', start);
  } catch (e) {}
})();
