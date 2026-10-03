function* iterateFocusableElements(container, options = {}) {
    var _a, _b;
    const strict = (_a = options.strict) !== null && _a !== void 0 ? _a : false;
    const acceptFn = ((_b = options.onlyTabbable) !== null && _b !== void 0 ? _b : false) ? isTabbable : isFocusable;
    const walker = document.createTreeWalker(container, NodeFilter.SHOW_ELEMENT, {
        acceptNode: node => node instanceof HTMLElement && acceptFn(node, strict) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP,
    });
    let nextNode = null;
    if (!options.reverse && acceptFn(container, strict)) {
        yield container;
    }
    if (options.reverse) {
        let lastChild = walker.lastChild();
        while (lastChild) {
            nextNode = lastChild;
            lastChild = walker.lastChild();
        }
    }
    else {
        nextNode = walker.firstChild();
    }
    while (nextNode instanceof HTMLElement) {
        yield nextNode;
        nextNode = options.reverse ? walker.previousNode() : walker.nextNode();
    }
    if (options.reverse && acceptFn(container, strict)) {
        yield container;
    }
    return undefined;
}
function getFocusableChild(container, lastChild = false) {
    return iterateFocusableElements(container, { reverse: lastChild, strict: true, onlyTabbable: true }).next().value;
}
const DISABLEABLE_TAGS = new Set(['BUTTON', 'INPUT', 'SELECT', 'TEXTAREA', 'OPTGROUP', 'OPTION', 'FIELDSET']);
function isFocusable(elem, strict = false) {
    if (elem.hidden)
        return false;
    if (elem.classList.contains('sentinel'))
        return false;
    if (elem instanceof HTMLInputElement && elem.type === 'hidden')
        return false;
    if (DISABLEABLE_TAGS.has(elem.tagName) && elem.disabled)
        return false;
    if (strict) {
        const offsetWidth = elem.offsetWidth;
        const offsetHeight = elem.offsetHeight;
        const offsetParent = elem.offsetParent;
        if (offsetWidth === 0 || offsetHeight === 0)
            return false;
        const style = getComputedStyle(elem);
        if (style.display === 'none')
            return false;
        if (style.visibility === 'hidden' || style.visibility === 'collapse')
            return false;
        const position = style.position;
        if (!offsetParent && position !== 'fixed' && position !== 'sticky')
            return false;
        if (elem.getClientRects().length === 0)
            return false;
    }
    if (elem.getAttribute('tabindex') != null) {
        return true;
    }
    if (elem.getAttribute('contenteditable') === 'true' || elem.getAttribute('contenteditable') === 'plaintext-only') {
        return true;
    }
    if (elem instanceof HTMLAnchorElement && elem.getAttribute('href') == null) {
        return false;
    }
    return elem.tabIndex !== -1;
}
function isTabbable(elem, strict = false) {
    return isFocusable(elem, strict) && elem.getAttribute('tabindex') !== '-1';
}

export { getFocusableChild, isFocusable, isTabbable, iterateFocusableElements };
