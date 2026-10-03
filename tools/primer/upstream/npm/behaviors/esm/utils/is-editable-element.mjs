const nonEditableInputTypes = new Set([
    'button',
    'checkbox',
    'color',
    'file',
    'hidden',
    'image',
    'radio',
    'range',
    'reset',
    'submit',
]);
function isEditableElement(target) {
    var _a, _b;
    if (!(target instanceof HTMLElement))
        return false;
    const name = target.nodeName.toLowerCase();
    const type = (_b = (_a = target.getAttribute('type')) === null || _a === void 0 ? void 0 : _a.toLowerCase()) !== null && _b !== void 0 ? _b : 'text';
    const isReadonly = target.ariaReadOnly === 'true' ||
        target.getAttribute('aria-readonly') === 'true' ||
        target.getAttribute('readonly') !== null;
    return ((name === 'select' ||
        name === 'textarea' ||
        (name === 'input' && !nonEditableInputTypes.has(type)) ||
        target.isContentEditable) &&
        !isReadonly);
}

export { isEditableElement };
