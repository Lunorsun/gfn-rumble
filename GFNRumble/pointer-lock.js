// GFN Rumble 실험 기능: 마우스 고정(Pointer Lock) 흉내
// 아이패드 웹뷰에는 Pointer Lock이 없어서, 앱이 마우스 움직임을 받아 웹페이지에 넣어 줍니다.
// 마우스·키보드 모드를 켰을 때만 주입됩니다. 인터넷 접속 없음.
(function () {
  'use strict';
  if (window.top !== window || window.__gfnPointer) return;

  var locked = null;
  var sensitivity = 1;

  function post(msg) {
    try { window.webkit.messageHandlers.pointer.postMessage(msg); } catch (e) {}
  }

  function fire(type) {
    try { document.dispatchEvent(new Event(type)); } catch (e) {}
  }

  try {
    Object.defineProperty(Document.prototype, 'pointerLockElement', {
      configurable: true,
      get: function () { return locked; }
    });
  } catch (e) {}

  Element.prototype.requestPointerLock = function () {
    locked = this;
    post('lock');
    fire('pointerlockchange');
    return Promise.resolve();
  };

  Document.prototype.exitPointerLock = function () {
    if (!locked) return;
    locked = null;
    post('unlock');
    fire('pointerlockchange');
  };

  function onConfig(c) {
    var s = Number(c && c.mouseSensitivity);
    sensitivity = isFinite(s) && s > 0 ? s : 1;
  }
  onConfig(window.__gfnConfig);
  if (window.__gfnConfigListeners) window.__gfnConfigListeners.push(onConfig);

  var buttonsDown = 0;
  var BIT = [1, 4, 2]; // 왼쪽, 가운데, 오른쪽 (index 0, 1, 2)

  function mouse(type, init) {
    var target = locked || document.activeElement || document.body;
    if (!target) return;
    init.bubbles = true;
    init.cancelable = true;
    init.buttons = buttonsDown;
    try { target.dispatchEvent(new MouseEvent(type, init)); } catch (e) {}
    if (type === 'mousemove' || type === 'mousedown' || type === 'mouseup') {
      var ptype = type.replace('mouse', 'pointer');
      init.pointerType = 'mouse';
      init.pointerId = 1;
      init.isPrimary = true;
      try { target.dispatchEvent(new PointerEvent(ptype, init)); } catch (e) {}
    }
  }

  // 앱이 한 프레임에 한 번 부릅니다: [["m",dx,dy],["b",index,1|0],["w",dx,dy], ...]
  window.__gfnPointer = {
    batch: function (events) {
      if (!locked || !events) return;
      for (var i = 0; i < events.length; i++) {
        var e = events[i];
        if (e[0] === 'm') {
          var mx = e[1] * sensitivity, my = e[2] * sensitivity;
          mouse('mousemove', { movementX: mx, movementY: my });
        } else if (e[0] === 'b') {
          var index = e[1] | 0, down = !!e[2];
          if (down) buttonsDown |= BIT[index] || 0; else buttonsDown &= ~(BIT[index] || 0);
          mouse(down ? 'mousedown' : 'mouseup', { button: index });
          if (!down && index === 0) mouse('click', { button: 0 });
          if (!down && index === 2) mouse('contextmenu', { button: 2 });
        } else if (e[0] === 'w') {
          var target = locked || document.body;
          try {
            target.dispatchEvent(new WheelEvent('wheel', {
              deltaX: e[1], deltaY: e[2], bubbles: true, cancelable: true
            }));
          } catch (err) {}
        }
      }
    },
    unlock: function () { document.exitPointerLock(); }
  };
})();
