// GFN 진동 브리지
// 웹페이지가 로드되기 전에 주입됩니다.
//  1) 지포스 나우가 "홈 화면에 추가된 앱"으로 인식하게 합니다.
//  2) 웹 게임패드 진동 기능(vibrationActuator)을 만들어서,
//     게임이 보내는 진동 명령을 앱(네이티브)으로 넘깁니다.
(function () {
  'use strict';
  if (window.__gfnRumbleBridge) return;
  window.__gfnRumbleBridge = true;

  function post(message) {
    try {
      window.webkit.messageHandlers.rumble.postMessage(message);
    } catch (e) { /* 앱 밖에서 열린 경우 무시 */ }
  }

  // ---- 1) 홈 화면 앱(PWA)처럼 보이게 ----
  try {
    Object.defineProperty(Navigator.prototype, 'standalone', {
      configurable: true,
      get: function () { return true; }
    });
  } catch (e) {}

  try {
    var originalMatchMedia = window.matchMedia;
    if (typeof originalMatchMedia === 'function') {
      window.matchMedia = function (query) {
        var list = originalMatchMedia.call(window, query);
        var text = String(query);
        var forced = null;
        if (/display-mode\s*:\s*(standalone|fullscreen)/i.test(text)) forced = true;
        else if (/display-mode\s*:\s*browser/i.test(text)) forced = false;
        if (forced !== null) {
          try {
            Object.defineProperty(list, 'matches', {
              configurable: true,
              get: function () { return forced; }
            });
          } catch (e) {}
        }
        return list;
      };
    }
  } catch (e) {}

  // ---- 2) 진동 브리지 ----
  if (typeof Gamepad === 'undefined') {
    post({ type: 'ready', installed: false });
    return;
  }

  var MAX_MS = 5000;
  var actuators = {};
  var padIds = {};
  var probed = false;

  function clamp01(value) {
    value = Number(value);
    if (!isFinite(value)) return 0;
    return Math.min(1, Math.max(0, value));
  }

  function clampMs(value) {
    value = Number(value);
    if (!isFinite(value)) return 0;
    return Math.min(MAX_MS, Math.max(0, value));
  }

  function makeActuator(index) {
    var pendingResolve = null;
    var timer = null;

    function settle(result) {
      if (timer !== null) { clearTimeout(timer); timer = null; }
      if (pendingResolve) {
        var resolve = pendingResolve;
        pendingResolve = null;
        resolve(result);
      }
    }

    var actuator = {
      type: 'dual-rumble',
      effects: ['dual-rumble', 'trigger-rumble'],

      playEffect: function (type, params) {
        params = params || {};
        var duration = clampMs(params.duration);
        var delay = clampMs(params.startDelay);
        settle('preempted');
        post({
          type: 'play',
          index: index,
          id: padIds[index] || '',
          strong: clamp01(params.strongMagnitude),
          weak: clamp01(params.weakMagnitude),
          leftTrigger: clamp01(params.leftTrigger),
          rightTrigger: clamp01(params.rightTrigger),
          duration: duration,
          delay: delay
        });
        return new Promise(function (resolve) {
          pendingResolve = resolve;
          timer = setTimeout(function () {
            timer = null;
            settle('complete');
          }, delay + duration);
        });
      },

      reset: function () {
        settle('preempted');
        post({ type: 'stop', index: index, id: padIds[index] || '' });
        return Promise.resolve('complete');
      },

      // 예전 방식(Firefox 계열) 호환
      pulse: function (value, duration) {
        return actuator.playEffect('dual-rumble', {
          duration: duration,
          strongMagnitude: value,
          weakMagnitude: value
        }).then(function () { return true; });
      }
    };
    return actuator;
  }

  function actuatorFor(pad) {
    var index;
    try {
      index = pad.index;
      padIds[index] = pad.id;
    } catch (e) {
      return null; // Gamepad.prototype 자체에서 읽은 경우
    }
    if (typeof index !== 'number') return null;
    if (!probed) {
      probed = true;
      post({ type: 'probe' });
    }
    if (!actuators[index]) actuators[index] = makeActuator(index);
    return actuators[index];
  }

  var installed = false;
  try {
    Object.defineProperty(Gamepad.prototype, 'vibrationActuator', {
      configurable: true,
      enumerable: true,
      get: function () { return actuatorFor(this); }
    });
    Object.defineProperty(Gamepad.prototype, 'hapticActuators', {
      configurable: true,
      enumerable: true,
      get: function () {
        var actuator = actuatorFor(this);
        return actuator ? [actuator] : [];
      }
    });
    installed = true;
  } catch (e) {}

  if (typeof window.GamepadHapticActuator === 'undefined') {
    window.GamepadHapticActuator = function GamepadHapticActuator() {};
  }

  window.addEventListener('pagehide', function () {
    post({ type: 'stopAll' });
  });

  post({ type: 'ready', installed: installed });
})();
