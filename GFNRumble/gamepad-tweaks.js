// GFN Rumble: 컨트롤러 조정 (데드존, 반응 곡선, 상하 반전, A/B 바꾸기)
// 설정이 모두 기본값이면 아무것도 바꾸지 않습니다. 인터넷 접속 없음.
(function () {
  'use strict';
  if (window.__gfnGamepadTweaks) return;
  window.__gfnGamepadTweaks = true;

  try {
    if (!navigator.getGamepads) return;
    var original = navigator.getGamepads.bind(navigator);
    var cfg = { deadzone: 0, curve: 1, invertY: false, swapAB: false, gyro: false };
    var gyroX = 0, gyroY = 0;
    // 앱이 자이로 값을 넣어 줍니다 (오른쪽 스틱에 더함)
    window.__gfnGyro = {
      set: function (x, y) {
        gyroX = isFinite(x) ? Math.max(-1, Math.min(1, x)) : 0;
        gyroY = isFinite(y) ? Math.max(-1, Math.min(1, y)) : 0;
      }
    };
    var active = false;

    function num(v, d, lo, hi) {
      v = Number(v);
      if (!isFinite(v)) return d;
      return Math.min(hi, Math.max(lo, v));
    }

    function applyConfig(c) {
      c = c || {};
      cfg.deadzone = num(c.deadzone, 0, 0, 0.3);
      cfg.curve = num(c.curve, 1, 0.5, 2);
      cfg.invertY = !!c.invertY;
      cfg.swapAB = !!c.swapAB;
      cfg.gyro = !!c.gyro;
      if (!cfg.gyro) { gyroX = 0; gyroY = 0; }
      active = cfg.deadzone > 0 || Math.abs(cfg.curve - 1) > 0.001 || cfg.invertY || cfg.swapAB || cfg.gyro;
    }

    // 스틱 하나(x, y): 원형 데드존 + 반응 곡선
    function stick(x, y, out, i) {
      var mag = Math.sqrt(x * x + y * y);
      if (mag <= cfg.deadzone || mag === 0) { out[i] = 0; out[i + 1] = 0; return; }
      var m = Math.min(1, (mag - cfg.deadzone) / (1 - cfg.deadzone));
      m = Math.pow(m, cfg.curve);
      out[i] = (x / mag) * m;
      out[i + 1] = (y / mag) * m;
    }

    // 매번 '새' 스냅샷을 만듭니다. 같은 객체를 재사용하면 게임이 이전 프레임과
    // 지금 프레임을 비교하지 못해 버튼이 계속 눌린 것처럼 보일 수 있어요.
    function snapshotButton(btn) {
      return { pressed: !!btn.pressed, touched: !!btn.touched, value: Number(btn.value) || 0 };
    }

    function wrap(pad) {
      var w = {
        id: pad.id,
        index: pad.index,
        connected: pad.connected,
        mapping: pad.mapping,
        timestamp: pad.timestamp,
        axes: [],
        buttons: []
      };
      Object.defineProperty(w, 'vibrationActuator', { get: function () { return pad.vibrationActuator; } });
      Object.defineProperty(w, 'hapticActuators', { get: function () { return pad.hapticActuators; } });

      var a = pad.axes;
      for (var i = 0; i < a.length; i++) w.axes.push(a[i]);
      if (a.length >= 2) stick(a[0], a[1], w.axes, 0);
      if (a.length >= 4) {
        stick(a[2], a[3], w.axes, 2);
        if (cfg.invertY) w.axes[3] = -w.axes[3];
        if (cfg.gyro && pad.index === 0) {
          w.axes[2] = Math.max(-1, Math.min(1, w.axes[2] + gyroX));
          w.axes[3] = Math.max(-1, Math.min(1, w.axes[3] + gyroY));
          // 스틱을 안 움직여도 자이로가 바뀌면 새 입력으로 보이게
          if (gyroX || gyroY) w.timestamp = Math.max(pad.timestamp, performance.now());
        }
      }

      var b = pad.buttons;
      for (var j = 0; j < b.length; j++) w.buttons.push(snapshotButton(b[j]));
      if (cfg.swapAB && b.length >= 4) {
        var t0 = w.buttons[0], t2 = w.buttons[2];
        w.buttons[0] = w.buttons[1]; w.buttons[1] = t0;
        w.buttons[2] = w.buttons[3]; w.buttons[3] = t2;
      }
      return w;
    }
    navigator.getGamepads = function () {
      var pads = original();
      if (!active || !pads) return pads;
      var result = [];
      for (var i = 0; i < pads.length; i++) {
        var p = pads[i];
        result.push(p ? wrap(p) : null);
      }
      return result;
    };

    applyConfig(window.__gfnConfig);
    if (window.__gfnConfigListeners) window.__gfnConfigListeners.push(applyConfig);
  } catch (e) {}
})();
