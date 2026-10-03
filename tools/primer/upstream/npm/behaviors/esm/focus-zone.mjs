import { polyfill } from './polyfills/event-listener-signal.mjs';
import { isMacOS } from './utils/user-agent.mjs';
import { iterateFocusableElements } from './utils/iterate-focusable-elements.mjs';
import { uniqueId } from './utils/unique-id.mjs';
import { isEditableElement } from './utils/is-editable-element.mjs';
import { IndexedSet } from './utils/indexed-set.mjs';

polyfill();
var FocusKeys;
(function (FocusKeys) {
    FocusKeys[FocusKeys["ArrowHorizontal"] = 1] = "ArrowHorizontal";
    FocusKeys[FocusKeys["ArrowVertical"] = 2] = "ArrowVertical";
    FocusKeys[FocusKeys["JK"] = 4] = "JK";
    FocusKeys[FocusKeys["HL"] = 8] = "HL";
    FocusKeys[FocusKeys["HomeAndEnd"] = 16] = "HomeAndEnd";
    FocusKeys[FocusKeys["PageUpDown"] = 256] = "PageUpDown";
    FocusKeys[FocusKeys["WS"] = 32] = "WS";
    FocusKeys[FocusKeys["AD"] = 64] = "AD";
    FocusKeys[FocusKeys["Tab"] = 128] = "Tab";
    FocusKeys[FocusKeys["Backspace"] = 512] = "Backspace";
    FocusKeys[FocusKeys["ArrowAll"] = 3] = "ArrowAll";
    FocusKeys[FocusKeys["HJKL"] = 12] = "HJKL";
    FocusKeys[FocusKeys["WASD"] = 96] = "WASD";
    FocusKeys[FocusKeys["All"] = 511] = "All";
})(FocusKeys || (FocusKeys = {}));
const KEY_TO_BIT = {
    ArrowLeft: FocusKeys.ArrowHorizontal,
    ArrowDown: FocusKeys.ArrowVertical,
    ArrowUp: FocusKeys.ArrowVertical,
    ArrowRight: FocusKeys.ArrowHorizontal,
    h: FocusKeys.HL,
    j: FocusKeys.JK,
    k: FocusKeys.JK,
    l: FocusKeys.HL,
    a: FocusKeys.AD,
    s: FocusKeys.WS,
    w: FocusKeys.WS,
    d: FocusKeys.AD,
    Tab: FocusKeys.Tab,
    Home: FocusKeys.HomeAndEnd,
    End: FocusKeys.HomeAndEnd,
    PageUp: FocusKeys.PageUpDown,
    PageDown: FocusKeys.PageUpDown,
    Backspace: FocusKeys.Backspace,
};
const KEY_TO_DIRECTION = {
    ArrowLeft: 'previous',
    ArrowDown: 'next',
    ArrowUp: 'previous',
    ArrowRight: 'next',
    h: 'previous',
    j: 'next',
    k: 'previous',
    l: 'next',
    a: 'previous',
    s: 'next',
    w: 'previous',
    d: 'next',
    Tab: 'next',
    Home: 'start',
    End: 'end',
    PageUp: 'start',
    PageDown: 'end',
    Backspace: 'previous',
};
function getDirection(keyboardEvent) {
    const direction = KEY_TO_DIRECTION[keyboardEvent.key];
    if (keyboardEvent.key === 'Tab' && keyboardEvent.shiftKey) {
        return 'previous';
    }
    const isMac = isMacOS();
    if ((isMac && keyboardEvent.metaKey) || (!isMac && keyboardEvent.ctrlKey)) {
        if (keyboardEvent.key === 'ArrowLeft' || keyboardEvent.key === 'ArrowUp') {
            return 'start';
        }
        else if (keyboardEvent.key === 'ArrowRight' || keyboardEvent.key === 'ArrowDown') {
            return 'end';
        }
    }
    return direction;
}
function shouldIgnoreFocusHandling(keyboardEvent, activeElement) {
    const key = keyboardEvent.key;
    const isSingleChar = key.length === 1 || (key.length === 2 && key.charCodeAt(0) >= 0xd800 && key.charCodeAt(0) <= 0xdbff);
    const isEditable = isEditableElement(activeElement);
    const isSelect = activeElement instanceof HTMLSelectElement;
    if (isEditable && (isSingleChar || key === 'Home' || key === 'End')) {
        return true;
    }
    if (isSelect) {
        const isMac = isMacOS();
        if (key === 'ArrowDown' && isMac && !keyboardEvent.metaKey) {
            return true;
        }
        if (key === 'ArrowDown' && !isMac && keyboardEvent.altKey) {
            return true;
        }
        return false;
    }
    if (isEditable && !isSelect) {
        const isInputElement = activeElement instanceof HTMLTextAreaElement || activeElement instanceof HTMLInputElement;
        const cursorAtStart = isInputElement && activeElement.selectionStart === 0 && activeElement.selectionEnd === 0;
        const cursorAtEnd = isInputElement &&
            activeElement.selectionStart === activeElement.value.length &&
            activeElement.selectionEnd === activeElement.value.length;
        if (key === 'ArrowLeft' && !cursorAtStart) {
            return true;
        }
        if (key === 'ArrowRight' && !cursorAtEnd) {
            return true;
        }
        const isContentEditable = activeElement instanceof HTMLElement && activeElement.isContentEditable;
        if (activeElement instanceof HTMLTextAreaElement || isContentEditable) {
            if (key === 'PageUp' || key === 'PageDown') {
                return true;
            }
            if (key === 'ArrowUp' && !cursorAtStart) {
                return true;
            }
            if (key === 'ArrowDown' && !cursorAtEnd) {
                return true;
            }
        }
    }
    return false;
}
const isActiveDescendantAttribute = 'data-is-active-descendant';
const activeDescendantActivatedDirectly = 'activated-directly';
const activeDescendantActivatedIndirectly = 'activated-indirectly';
const hasActiveDescendantAttribute = 'data-has-active-descendant';
function focusZone(container, settings) {
    var _a, _b, _c, _d, _e, _f, _g;
    const focusableElements = new IndexedSet();
    const savedTabIndex = new WeakMap();
    const bindKeys = (_a = settings === null || settings === void 0 ? void 0 : settings.bindKeys) !== null && _a !== void 0 ? _a : ((settings === null || settings === void 0 ? void 0 : settings.getNextFocusable) ? FocusKeys.ArrowAll : FocusKeys.ArrowVertical) | FocusKeys.HomeAndEnd;
    const focusOutBehavior = (_b = settings === null || settings === void 0 ? void 0 : settings.focusOutBehavior) !== null && _b !== void 0 ? _b : 'stop';
    const focusInStrategy = (_c = settings === null || settings === void 0 ? void 0 : settings.focusInStrategy) !== null && _c !== void 0 ? _c : 'previous';
    const activeDescendantControl = settings === null || settings === void 0 ? void 0 : settings.activeDescendantControl;
    const activeDescendantCallback = settings === null || settings === void 0 ? void 0 : settings.onActiveDescendantChanged;
    const ignoreHoverEvents = (_d = settings === null || settings === void 0 ? void 0 : settings.ignoreHoverEvents) !== null && _d !== void 0 ? _d : false;
    const focusPrependedElements = (_e = settings === null || settings === void 0 ? void 0 : settings.focusPrependedElements) !== null && _e !== void 0 ? _e : false;
    let currentFocusedElement;
    let wasDirectlyActivated = false;
    const preventScroll = (_f = settings === null || settings === void 0 ? void 0 : settings.preventScroll) !== null && _f !== void 0 ? _f : false;
    const preventInitialFocus = focusInStrategy === 'initial' && (settings === null || settings === void 0 ? void 0 : settings.activeDescendantControl);
    function getFirstFocusableElement() {
        return focusableElements.get(0);
    }
    function isActiveDescendantInputFocused() {
        return document.activeElement === activeDescendantControl;
    }
    function updateFocusedElement(to, directlyActivated = false) {
        const from = currentFocusedElement;
        currentFocusedElement = to;
        wasDirectlyActivated = directlyActivated;
        if (activeDescendantControl) {
            if (to && isActiveDescendantInputFocused()) {
                setActiveDescendant(from, to, directlyActivated);
            }
            else {
                clearActiveDescendant();
            }
            return;
        }
        if (from && from !== to && savedTabIndex.has(from)) {
            from.setAttribute('tabindex', '-1');
        }
        to === null || to === void 0 ? void 0 : to.setAttribute('tabindex', '0');
    }
    function setActiveDescendant(from, to, directlyActivated = false) {
        if (!to.id) {
            to.setAttribute('id', uniqueId());
        }
        if (from && from !== to) {
            from.removeAttribute(isActiveDescendantAttribute);
        }
        if (!activeDescendantControl ||
            (!directlyActivated && activeDescendantControl.getAttribute('aria-activedescendant') === to.id)) {
            return;
        }
        activeDescendantControl.setAttribute('aria-activedescendant', to.id);
        container.setAttribute(hasActiveDescendantAttribute, to.id);
        to.setAttribute(isActiveDescendantAttribute, directlyActivated ? activeDescendantActivatedDirectly : activeDescendantActivatedIndirectly);
        activeDescendantCallback === null || activeDescendantCallback === void 0 ? void 0 : activeDescendantCallback(to, from, directlyActivated);
    }
    function clearActiveDescendant(previouslyActiveElement = currentFocusedElement) {
        if (focusInStrategy === 'first') {
            currentFocusedElement = undefined;
        }
        activeDescendantControl === null || activeDescendantControl === void 0 ? void 0 : activeDescendantControl.removeAttribute('aria-activedescendant');
        container.removeAttribute(hasActiveDescendantAttribute);
        previouslyActiveElement === null || previouslyActiveElement === void 0 ? void 0 : previouslyActiveElement.removeAttribute(isActiveDescendantAttribute);
        const items = container.querySelectorAll(`[${isActiveDescendantAttribute}]`);
        for (let i = 0; i < items.length; i++) {
            items[i].removeAttribute(isActiveDescendantAttribute);
        }
        activeDescendantCallback === null || activeDescendantCallback === void 0 ? void 0 : activeDescendantCallback(undefined, previouslyActiveElement, false);
    }
    function beginFocusManagement(...elements) {
        const filteredElements = (settings === null || settings === void 0 ? void 0 : settings.focusableElementFilter)
            ? elements.filter(e => settings.focusableElementFilter(e))
            : elements;
        if (filteredElements.length === 0) {
            return;
        }
        const insertionIndex = findInsertionIndex(filteredElements);
        focusableElements.insertAt(insertionIndex, filteredElements);
        for (const element of filteredElements) {
            if (!savedTabIndex.has(element)) {
                savedTabIndex.set(element, element.getAttribute('tabindex'));
            }
            element.setAttribute('tabindex', '-1');
        }
        const shouldFocusPrepended = focusPrependedElements && insertionIndex === 0 && !wasDirectlyActivated;
        if (!preventInitialFocus && shouldFocusPrepended) {
            reinitializeWithFreshElements();
        }
        else if (!preventInitialFocus && !currentFocusedElement) {
            updateFocusedElement(getFirstFocusableElement());
        }
    }
    function reinitializeWithFreshElements() {
        const freshElements = [...iterateFocusableElements(container, iterateFocusableElementsOptions)];
        focusableElements.clear();
        focusableElements.insertAt(0, freshElements);
        for (const element of freshElements) {
            if (!savedTabIndex.has(element)) {
                savedTabIndex.set(element, element.getAttribute('tabindex'));
            }
            element.setAttribute('tabindex', '-1');
        }
        updateFocusedElement(getFirstFocusableElement());
    }
    function findInsertionIndex(elementsToInsert) {
        const firstElementToInsert = elementsToInsert[0];
        if (focusableElements.size === 0)
            return 0;
        let iMin = 0;
        let iMax = focusableElements.size - 1;
        while (iMin <= iMax) {
            const i = Math.floor((iMin + iMax) / 2);
            const element = focusableElements.get(i);
            if (followsInDocument(firstElementToInsert, element)) {
                iMax = i - 1;
            }
            else {
                iMin = i + 1;
            }
        }
        return iMin;
    }
    function followsInDocument(first, second) {
        return (second.compareDocumentPosition(first) & Node.DOCUMENT_POSITION_PRECEDING) > 0;
    }
    function endFocusManagement(...elements) {
        for (const element of elements) {
            focusableElements.delete(element);
            const savedIndex = savedTabIndex.get(element);
            if (savedIndex !== undefined) {
                if (savedIndex === null) {
                    element.removeAttribute('tabindex');
                }
                else {
                    element.setAttribute('tabindex', savedIndex);
                }
                savedTabIndex.delete(element);
            }
            if (element === currentFocusedElement) {
                const nextElementToFocus = getFirstFocusableElement();
                updateFocusedElement(nextElementToFocus);
            }
        }
    }
    const iterateFocusableElementsOptions = {
        reverse: settings === null || settings === void 0 ? void 0 : settings.reverse,
        strict: settings === null || settings === void 0 ? void 0 : settings.strict,
        onlyTabbable: settings === null || settings === void 0 ? void 0 : settings.onlyTabbable,
    };
    beginFocusManagement(...iterateFocusableElements(container, iterateFocusableElementsOptions));
    const initialElement = typeof focusInStrategy === 'function' ? focusInStrategy(document.body) : getFirstFocusableElement();
    if (!preventInitialFocus)
        updateFocusedElement(initialElement);
    const observer = new MutationObserver(mutations => {
        const elementsToRemove = new Set();
        const elementsToAdd = new Set();
        const attributeRemovals = new Set();
        const attributeAdditions = new Set();
        for (const mutation of mutations) {
            if (mutation.type === 'childList') {
                for (const removedNode of mutation.removedNodes) {
                    if (removedNode instanceof HTMLElement) {
                        elementsToRemove.add(removedNode);
                    }
                }
                for (const addedNode of mutation.addedNodes) {
                    if (addedNode instanceof HTMLElement) {
                        elementsToAdd.add(addedNode);
                    }
                }
            }
            else if (mutation.type === 'attributes' && mutation.target instanceof HTMLElement) {
                const attributeName = mutation.attributeName;
                const hasAttribute = attributeName ? mutation.target.hasAttribute(attributeName) : false;
                if (hasAttribute) {
                    attributeRemovals.add(mutation.target);
                }
                else {
                    attributeAdditions.add(mutation.target);
                }
            }
        }
        if (elementsToRemove.size > 0) {
            const toRemove = [];
            for (const node of elementsToRemove) {
                for (const el of iterateFocusableElements(node)) {
                    toRemove.push(el);
                }
            }
            if (toRemove.length > 0) {
                endFocusManagement(...toRemove);
            }
        }
        if (attributeRemovals.size > 0) {
            endFocusManagement(...attributeRemovals);
        }
        if (elementsToAdd.size > 0) {
            const toAdd = [];
            for (const node of elementsToAdd) {
                for (const el of iterateFocusableElements(node, iterateFocusableElementsOptions)) {
                    toAdd.push(el);
                }
            }
            if (toAdd.length > 0) {
                if (focusPrependedElements) {
                    reinitializeWithFreshElements();
                }
                else {
                    beginFocusManagement(...toAdd);
                }
            }
        }
        if (attributeAdditions.size > 0) {
            beginFocusManagement(...attributeAdditions);
        }
    });
    observer.observe(container, {
        subtree: true,
        childList: true,
        attributeFilter: ['hidden', 'disabled'],
        attributeOldValue: true,
    });
    const controller = new AbortController();
    const signal = (_g = settings === null || settings === void 0 ? void 0 : settings.abortSignal) !== null && _g !== void 0 ? _g : controller.signal;
    signal.addEventListener('abort', () => {
        observer.disconnect();
        endFocusManagement(...focusableElements);
        focusableElements.clear();
    });
    let elementIndexFocusedByClick = undefined;
    container.addEventListener('mousedown', event => {
        if (event.target instanceof HTMLElement && event.target !== document.activeElement) {
            elementIndexFocusedByClick = focusableElements.indexOf(event.target);
        }
    }, { signal });
    if (activeDescendantControl) {
        container.addEventListener('focusin', event => {
            if (event.target instanceof HTMLElement && focusableElements.has(event.target)) {
                activeDescendantControl.focus({ preventScroll });
                updateFocusedElement(event.target);
            }
        }, { signal });
        if (!ignoreHoverEvents) {
            container.addEventListener('mousemove', ({ target }) => {
                if (!(target instanceof Node)) {
                    return;
                }
                if (target instanceof HTMLElement && focusableElements.has(target)) {
                    updateFocusedElement(target);
                    return;
                }
                const focusableElement = focusableElements.find(element => element.contains(target));
                if (focusableElement) {
                    updateFocusedElement(focusableElement);
                }
            }, { signal, capture: true });
        }
        activeDescendantControl.addEventListener('focusin', () => {
            if (!currentFocusedElement) {
                if (!preventInitialFocus)
                    updateFocusedElement(getFirstFocusableElement());
            }
            else {
                setActiveDescendant(undefined, currentFocusedElement);
            }
        }, { signal });
        activeDescendantControl.addEventListener('focusout', () => {
            clearActiveDescendant();
        }, { signal });
    }
    else {
        container.addEventListener('focusin', event => {
            if (event.target instanceof HTMLElement) {
                if (elementIndexFocusedByClick !== undefined) {
                    if (elementIndexFocusedByClick >= 0) {
                        const clickedElement = focusableElements.get(elementIndexFocusedByClick);
                        if (clickedElement && clickedElement !== currentFocusedElement) {
                            updateFocusedElement(clickedElement);
                        }
                    }
                    elementIndexFocusedByClick = undefined;
                }
                else {
                    if (focusInStrategy === 'previous') {
                        updateFocusedElement(event.target);
                    }
                    else if (focusInStrategy === 'closest' || focusInStrategy === 'first') {
                        if (event.relatedTarget instanceof Element && !container.contains(event.relatedTarget)) {
                            const targetElementIndex = lastKeyboardFocusDirection === 'previous' ? focusableElements.size - 1 : 0;
                            const targetElement = focusableElements.get(targetElementIndex);
                            targetElement === null || targetElement === void 0 ? void 0 : targetElement.focus({ preventScroll });
                            return;
                        }
                        else {
                            updateFocusedElement(event.target);
                        }
                    }
                    else if (typeof focusInStrategy === 'function') {
                        if (event.relatedTarget instanceof Element && !container.contains(event.relatedTarget)) {
                            const elementToFocus = focusInStrategy(event.relatedTarget);
                            if (elementToFocus && focusableElements.has(elementToFocus)) {
                                elementToFocus.focus({ preventScroll });
                                return;
                            }
                            else {
                                console.warn('Element requested is not a known focusable element.');
                            }
                        }
                        else {
                            updateFocusedElement(event.target);
                        }
                    }
                }
            }
            lastKeyboardFocusDirection = undefined;
        }, { signal });
    }
    const keyboardEventRecipient = activeDescendantControl !== null && activeDescendantControl !== void 0 ? activeDescendantControl : container;
    let lastKeyboardFocusDirection = undefined;
    if (focusInStrategy === 'closest') {
        document.addEventListener('keydown', event => {
            if (event.key === 'Tab') {
                lastKeyboardFocusDirection = getDirection(event);
            }
        }, { signal, capture: true });
    }
    function getCurrentFocusedIndex() {
        if (!currentFocusedElement) {
            return preventInitialFocus ? -1 : 0;
        }
        const focusedIndex = focusableElements.indexOf(currentFocusedElement);
        const fallbackIndex = currentFocusedElement === container ? -1 : 0;
        return focusedIndex !== -1 ? focusedIndex : fallbackIndex;
    }
    keyboardEventRecipient.addEventListener('keydown', event => {
        var _a;
        if (event.key in KEY_TO_DIRECTION) {
            const keyBit = KEY_TO_BIT[event.key];
            if (!event.defaultPrevented &&
                (keyBit & bindKeys) > 0 &&
                !shouldIgnoreFocusHandling(event, document.activeElement)) {
                const direction = getDirection(event);
                let nextElementToFocus = undefined;
                if (settings === null || settings === void 0 ? void 0 : settings.getNextFocusable) {
                    nextElementToFocus = settings.getNextFocusable(direction, (_a = document.activeElement) !== null && _a !== void 0 ? _a : undefined, event);
                }
                if (!nextElementToFocus) {
                    const lastFocusedIndex = getCurrentFocusedIndex();
                    let nextFocusedIndex = lastFocusedIndex;
                    if (direction === 'previous') {
                        nextFocusedIndex -= 1;
                    }
                    else if (direction === 'start') {
                        nextFocusedIndex = 0;
                    }
                    else if (direction === 'next') {
                        nextFocusedIndex += 1;
                    }
                    else {
                        nextFocusedIndex = focusableElements.size - 1;
                    }
                    if (nextFocusedIndex < 0) {
                        if (focusOutBehavior === 'wrap' && event.key !== 'Tab') {
                            nextFocusedIndex = focusableElements.size - 1;
                        }
                        else {
                            nextFocusedIndex = 0;
                        }
                    }
                    if (nextFocusedIndex >= focusableElements.size) {
                        if (focusOutBehavior === 'wrap' && event.key !== 'Tab') {
                            nextFocusedIndex = 0;
                        }
                        else {
                            nextFocusedIndex = focusableElements.size - 1;
                        }
                    }
                    if (lastFocusedIndex !== nextFocusedIndex) {
                        nextElementToFocus = focusableElements.get(nextFocusedIndex);
                    }
                }
                if (activeDescendantControl) {
                    updateFocusedElement(nextElementToFocus || currentFocusedElement, true);
                }
                else if (nextElementToFocus) {
                    lastKeyboardFocusDirection = direction;
                    nextElementToFocus.focus({ preventScroll });
                }
                if (event.key !== 'Tab' || nextElementToFocus) {
                    event.preventDefault();
                }
            }
        }
    }, { signal });
    return controller;
}

export { FocusKeys, activeDescendantActivatedDirectly, activeDescendantActivatedIndirectly, focusZone, hasActiveDescendantAttribute, isActiveDescendantAttribute };
