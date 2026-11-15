// GFN Rumble: 대기열이 끝났을 때와 '활동 없음' 경고가 떴을 때 앱에 알려 줍니다.
// 화면의 글자만 읽고, 앱(네이티브)에만 {type} 하나를 보냅니다. 인터넷 접속 없음.
// 주의: 지포스 나우 화면 문구는 확인되지 않은 추측이 섞여 있어요(일본어·영어·한국어).
(function () {
  'use strict';
  if (window.top !== window || window.__gfnSessionWatch) return;
  window.__gfnSessionWatch = true;

  try {
    var READY = [
      /rig is ready/i, /ready to play/i, /your game is ready/i,
      /準備(が)?(でき|完了)/, /プレイの準備/,
      /게임 준비 완료/, /플레이할 준비/, /준비되었습니다/
    ];
    var IDLE = [
      /inactiv/i, /idle/i, /are you still there/i, /session will end/i,
      /操作がない/, /非アクティブ/, /まもなく(セッションが)?終了/,
      /활동이 없/, /곧 (세션이 )?종료/, /비활성/
    ];
    var enabled = true;
    var lastSent = {};
    var wasQueued = false;

    function send(type) {
      if (!enabled) return;
      var now = Date.now();
      if (lastSent[type] && now - lastSent[type] < 60000) return;
      lastSent[type] = now;
      try { window.webkit.messageHandlers.session.postMessage({ type: type }); } catch (e) {}
    }

    function any(list, text) {
      for (var i = 0; i < list.length; i++) if (list[i].test(text)) return true;
      return false;
    }

    function visibleDialogText() {
      var nodes = document.querySelectorAll('[role="dialog"], [role="alertdialog"], [aria-live], .mat-dialog-container, .cdk-overlay-pane');
      var text = '';
      for (var i = 0; i < nodes.length && text.length < 4000; i++) {
        text += ' ' + (nodes[i].innerText || '');
      }
      return text;
    }

    function check() {
      var text = (document.title || '') + ' ' + visibleDialogText();
      if (/queue|待ち|대기/i.test(text)) wasQueued = true;
      if (any(READY, text) && wasQueued) { wasQueued = false; send('queueReady'); }
      if (any(IDLE, text)) send('idleWarning');
    }

    function onConfig(c) { enabled = !(c && c.sessionAlerts === false); }
    onConfig(window.__gfnConfig);
    if (window.__gfnConfigListeners) window.__gfnConfigListeners.push(onConfig);

    // 1초에 한 번까지만 확인합니다.
    var scheduled = false;
    function schedule() {
      if (scheduled) return;
      scheduled = true;
      setTimeout(function () { scheduled = false; try { check(); } catch (e) {} }, 1000);
    }
    function start() {
      new MutationObserver(schedule).observe(document.documentElement, {
        childList: true, subtree: true, characterData: true
      });
      setInterval(schedule, 5000);
    }
    if (document.documentElement) start();
    else document.addEventListener('DOMContentLoaded', start);
  } catch (e) {}
})();
