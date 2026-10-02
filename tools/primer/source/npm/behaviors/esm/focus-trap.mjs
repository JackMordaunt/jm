import { getFocusableChild, isTabbable } from './utils/iterate-focusable-elements.mjs';
import { polyfill } from './polyfills/event-listener-signal.mjs';

polyfill();
const suspendedTrapStack = [];
let activeTrap = undefined;
const SR_ONLY_STYLES = 'position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0';
function focusWithDataOpt(el) {
    if (!el)
        return;
    const preventScroll = el.hasAttribute('data-prevent-scroll-on-focus');
    el.focus({ preventScroll });
}
function createSentinel({ onFocus }) {
    const sentinel = document.createElement('span');
    sentinel.setAttribute('class', 'sentinel');
    sentinel.setAttribute('tabindex', '0');
    sentinel.setAttribute('aria-hidden', 'true');
    sentinel.style.cssText = SR_ONLY_STYLES;
    sentinel.onfocus = onFocus;
    return sentinel;
}
function tryReactivate() {
    const trapToReactivate = suspendedTrapStack.pop();
    if (trapToReactivate) {
        focusTrap(trapToReactivate.container, trapToReactivate.initialFocus, trapToReactivate.originalSignal);
    }
}
function followSignal(signal) {
    const controller = new AbortController();
    signal.addEventListener('abort', () => {
        controller.abort();
    });
    return controller;
}
function observeFocusTrap(container, sentinels) {
    const observer = new MutationObserver(mutations => {
        for (const mutation of mutations) {
            if (mutation.type === 'childList' && mutation.addedNodes.length) {
                for (const node of mutation.addedNodes) {
                    if (node instanceof HTMLElement && node.tagName === 'SPAN' && node.classList.contains('sentinel')) {
                        return;
                    }
                }
                const firstChild = container.firstElementChild;
                const lastChild = container.lastElementChild;
                const [sentinelStart, sentinelEnd] = sentinels;
                if (!(firstChild === null || firstChild === void 0 ? void 0 : firstChild.classList.contains('sentinel'))) {
                    container.insertAdjacentElement('afterbegin', sentinelStart);
                }
                if (!(lastChild === null || lastChild === void 0 ? void 0 : lastChild.classList.contains('sentinel'))) {
                    container.insertAdjacentElement('beforeend', sentinelEnd);
                }
            }
        }
    });
    observer.observe(container, { childList: true });
    return observer;
}
function focusTrap(container, initialFocus, abortSignal) {
    const controller = new AbortController();
    const signal = abortSignal !== null && abortSignal !== void 0 ? abortSignal : controller.signal;
    container.setAttribute('data-focus-trap', 'active');
    const sentinelStart = createSentinel({
        onFocus: () => {
            const lastFocusableChild = getFocusableChild(container, true);
            focusWithDataOpt(lastFocusableChild);
        },
    });
    const sentinelEnd = createSentinel({
        onFocus: () => {
            const firstFocusableChild = getFocusableChild(container);
            focusWithDataOpt(firstFocusableChild);
        },
    });
    const hasExistingSentinels = container.querySelector(':scope > span.sentinel') !== null;
    if (!hasExistingSentinels) {
        container.prepend(sentinelStart);
        container.append(sentinelEnd);
    }
    const observer = observeFocusTrap(container, [sentinelStart, sentinelEnd]);
    let lastFocusedChild = undefined;
    function ensureTrapZoneHasFocus(focusedElement) {
        if (focusedElement instanceof HTMLElement && document.contains(container)) {
            if (container.contains(focusedElement)) {
                lastFocusedChild = focusedElement;
                return;
            }
            else {
                if (lastFocusedChild && isTabbable(lastFocusedChild) && container.contains(lastFocusedChild)) {
                    focusWithDataOpt(lastFocusedChild);
                    return;
                }
                else if (initialFocus && container.contains(initialFocus)) {
                    focusWithDataOpt(initialFocus);
                    return;
                }
                else {
                    const firstFocusableChild = getFocusableChild(container);
                    focusWithDataOpt(firstFocusableChild);
                    return;
                }
            }
        }
    }
    const wrappingController = followSignal(signal);
    if (activeTrap) {
        const suspendedTrap = activeTrap;
        activeTrap.container.setAttribute('data-focus-trap', 'suspended');
        activeTrap.controller.abort();
        suspendedTrapStack.push(suspendedTrap);
    }
    wrappingController.signal.addEventListener('abort', () => {
        activeTrap = undefined;
    });
    signal.addEventListener('abort', () => {
        container.removeAttribute('data-focus-trap');
        const sentinels = container.getElementsByClassName('sentinel');
        while (sentinels.length > 0)
            sentinels[0].remove();
        const suspendedTrapIndex = suspendedTrapStack.findIndex(t => t.container === container);
        if (suspendedTrapIndex >= 0) {
            suspendedTrapStack.splice(suspendedTrapIndex, 1);
        }
        observer.disconnect();
        tryReactivate();
    });
    document.addEventListener('focus', event => {
        ensureTrapZoneHasFocus(event.target);
    }, { signal: wrappingController.signal, capture: true });
    ensureTrapZoneHasFocus(document.activeElement);
    activeTrap = {
        container,
        controller: wrappingController,
        initialFocus,
        originalSignal: signal,
    };
    const suspendedTrapIndex = suspendedTrapStack.findIndex(t => t.container === container);
    if (suspendedTrapIndex >= 0) {
        suspendedTrapStack.splice(suspendedTrapIndex, 1);
    }
    if (!abortSignal) {
        return controller;
    }
}

export { focusTrap };
