const alternateOrders = {
    'outside-top': ['outside-bottom', 'outside-right', 'outside-left', 'outside-bottom'],
    'outside-bottom': ['outside-top', 'outside-right', 'outside-left', 'outside-bottom'],
    'outside-left': ['outside-right', 'outside-bottom', 'outside-top', 'outside-bottom'],
    'outside-right': ['outside-left', 'outside-bottom', 'outside-top', 'outside-bottom'],
};
const alternateAlignments = {
    start: ['end', 'center'],
    end: ['start', 'center'],
    center: ['end', 'start'],
};
function getAnchoredPosition(floatingElement, anchorElement, settings = {}) {
    const { positionedParent: parentElement, clippingNode, positionedParentStyle, clippingNodeStyle, } = getPositionedParentAndClippingNode(floatingElement);
    const clippingRect = getClippingRect(clippingNode, clippingNodeStyle);
    const parentElementStyle = positionedParentStyle || getComputedStyle(parentElement);
    const parentElementRect = parentElement.getBoundingClientRect();
    const [borderTop, borderLeft] = [parentElementStyle.borderTopWidth, parentElementStyle.borderLeftWidth].map(v => parseInt(v, 10) || 0);
    const relativeRect = {
        top: parentElementRect.top + borderTop,
        left: parentElementRect.left + borderLeft,
    };
    return pureCalculateAnchoredPosition(clippingRect, relativeRect, floatingElement.getBoundingClientRect(), anchorElement instanceof Element ? anchorElement.getBoundingClientRect() : anchorElement, getDefaultSettings(settings), { width: window.innerWidth, height: window.innerHeight });
}
function getPositionedParentAndClippingNode(element) {
    if (isOnTopLayer(element)) {
        return {
            positionedParent: document.body,
            clippingNode: document.body,
            positionedParentStyle: null,
            clippingNodeStyle: null,
        };
    }
    let positionedParent = null;
    let clippingNode = null;
    let positionedParentStyle = null;
    let clippingNodeStyle = null;
    let parentNode = element.parentNode;
    while (parentNode !== null && parentNode !== document.body) {
        if (parentNode instanceof HTMLElement) {
            const style = getComputedStyle(parentNode);
            if (!positionedParent && style.position !== 'static') {
                positionedParent = parentNode;
                positionedParentStyle = style;
            }
            if (!clippingNode && style.overflow !== 'visible') {
                clippingNode = parentNode;
                clippingNodeStyle = style;
            }
            if (positionedParent && clippingNode) {
                break;
            }
        }
        parentNode = parentNode.parentNode;
    }
    return {
        positionedParent: positionedParent !== null && positionedParent !== void 0 ? positionedParent : document.body,
        clippingNode: clippingNode !== null && clippingNode !== void 0 ? clippingNode : document.body,
        positionedParentStyle,
        clippingNodeStyle,
    };
}
function isOnTopLayer(element) {
    var _a;
    if (element.tagName === 'DIALOG') {
        return true;
    }
    try {
        if (element.matches(':popover-open') && /native code/.test((_a = document.body.showPopover) === null || _a === void 0 ? void 0 : _a.toString())) {
            return true;
        }
    }
    catch (_b) {
        return false;
    }
    return false;
}
function getClippingRect(clippingNode, cachedStyle = null) {
    const elemRect = clippingNode.getBoundingClientRect();
    const elemStyle = cachedStyle || getComputedStyle(clippingNode);
    const borderTop = parseInt(elemStyle.borderTopWidth, 10) || 0;
    const borderLeft = parseInt(elemStyle.borderLeftWidth, 10) || 0;
    const borderRight = parseInt(elemStyle.borderRightWidth, 10) || 0;
    const borderBottom = parseInt(elemStyle.borderBottomWidth, 10) || 0;
    return {
        top: elemRect.top + borderTop,
        left: elemRect.left + borderLeft,
        width: elemRect.width - borderRight - borderLeft,
        height: Math.max(elemRect.height - borderTop - borderBottom, clippingNode === document.body ? window.innerHeight : -Infinity),
    };
}
const positionDefaults = {
    side: 'outside-bottom',
    align: 'start',
    anchorOffset: 4,
    alignmentOffset: 4,
    allowOutOfBounds: false,
    displayInViewport: false,
};
function getDefaultSettings(settings = {}) {
    var _a, _b, _c, _d, _e, _f;
    const side = (_a = settings.side) !== null && _a !== void 0 ? _a : positionDefaults.side;
    const align = (_b = settings.align) !== null && _b !== void 0 ? _b : positionDefaults.align;
    return {
        side,
        align,
        anchorOffset: (_c = settings.anchorOffset) !== null && _c !== void 0 ? _c : (side === 'inside-center' ? 0 : positionDefaults.anchorOffset),
        alignmentOffset: (_d = settings.alignmentOffset) !== null && _d !== void 0 ? _d : (align !== 'center' && side.startsWith('inside') ? positionDefaults.alignmentOffset : 0),
        allowOutOfBounds: (_e = settings.allowOutOfBounds) !== null && _e !== void 0 ? _e : positionDefaults.allowOutOfBounds,
        displayInViewport: (_f = settings.displayInViewport) !== null && _f !== void 0 ? _f : positionDefaults.displayInViewport,
    };
}
function pureCalculateAnchoredPosition(viewportRect, relativePosition, floatingRect, anchorRect, { side, align, allowOutOfBounds, anchorOffset, alignmentOffset, displayInViewport }, visibleViewportSize) {
    let effectiveViewportRect = viewportRect;
    if (displayInViewport) {
        effectiveViewportRect = {
            top: 0,
            left: 0,
            width: visibleViewportSize.width,
            height: visibleViewportSize.height,
        };
    }
    const relativeViewportRect = {
        top: effectiveViewportRect.top - relativePosition.top,
        left: effectiveViewportRect.left - relativePosition.left,
        width: effectiveViewportRect.width,
        height: effectiveViewportRect.height,
    };
    let pos = calculatePosition(floatingRect, anchorRect, side, align, anchorOffset, alignmentOffset);
    let anchorSide = side;
    let anchorAlign = align;
    pos.top -= relativePosition.top;
    pos.left -= relativePosition.left;
    if (!allowOutOfBounds) {
        const alternateOrder = alternateOrders[side];
        let positionAttempt = 0;
        if (alternateOrder) {
            let prevSide = side;
            while (positionAttempt < alternateOrder.length &&
                shouldRecalculatePosition(prevSide, pos, relativeViewportRect, floatingRect)) {
                const nextSide = alternateOrder[positionAttempt++];
                prevSide = nextSide;
                pos = calculatePosition(floatingRect, anchorRect, nextSide, align, anchorOffset, alignmentOffset);
                pos.top -= relativePosition.top;
                pos.left -= relativePosition.left;
                anchorSide = nextSide;
            }
        }
        const alternateAlignment = alternateAlignments[align];
        let alignmentAttempt = 0;
        if (alternateAlignment) {
            let prevAlign = align;
            while (alignmentAttempt < alternateAlignment.length &&
                shouldRecalculateAlignment(prevAlign, pos, relativeViewportRect, floatingRect)) {
                const nextAlign = alternateAlignment[alignmentAttempt++];
                prevAlign = nextAlign;
                pos = calculatePosition(floatingRect, anchorRect, anchorSide, nextAlign, anchorOffset, alignmentOffset);
                pos.top -= relativePosition.top;
                pos.left -= relativePosition.left;
                anchorAlign = nextAlign;
            }
        }
        if (pos.top < relativeViewportRect.top) {
            pos.top = relativeViewportRect.top;
        }
        if (pos.left < relativeViewportRect.left) {
            pos.left = relativeViewportRect.left;
        }
        if (pos.left + floatingRect.width > effectiveViewportRect.width + relativeViewportRect.left) {
            pos.left = effectiveViewportRect.width + relativeViewportRect.left - floatingRect.width;
        }
        if (displayInViewport || (alternateOrder && positionAttempt < alternateOrder.length)) {
            if (pos.top + floatingRect.height > effectiveViewportRect.height + relativeViewportRect.top) {
                pos.top = Math.max(effectiveViewportRect.height + relativeViewportRect.top - floatingRect.height, 0);
            }
        }
    }
    return Object.assign(Object.assign({}, pos), { anchorSide, anchorAlign });
}
function calculatePosition(elementDimensions, anchorPosition, side, align, anchorOffset, alignmentOffset) {
    const anchorRight = anchorPosition.left + anchorPosition.width;
    const anchorBottom = anchorPosition.top + anchorPosition.height;
    let top = -1;
    let left = -1;
    if (side === 'outside-top') {
        top = anchorPosition.top - anchorOffset - elementDimensions.height;
    }
    else if (side === 'outside-bottom') {
        top = anchorBottom + anchorOffset;
    }
    else if (side === 'outside-left') {
        left = anchorPosition.left - anchorOffset - elementDimensions.width;
    }
    else if (side === 'outside-right') {
        left = anchorRight + anchorOffset;
    }
    if (side === 'outside-top' || side === 'outside-bottom') {
        if (align === 'start') {
            left = anchorPosition.left + alignmentOffset;
        }
        else if (align === 'center') {
            left = anchorPosition.left - (elementDimensions.width - anchorPosition.width) / 2 + alignmentOffset;
        }
        else {
            left = anchorRight - elementDimensions.width - alignmentOffset;
        }
    }
    if (side === 'outside-left' || side === 'outside-right') {
        if (align === 'start') {
            top = anchorPosition.top + alignmentOffset;
        }
        else if (align === 'center') {
            top = anchorPosition.top - (elementDimensions.height - anchorPosition.height) / 2 + alignmentOffset;
        }
        else {
            top = anchorBottom - elementDimensions.height - alignmentOffset;
        }
    }
    if (side === 'inside-top') {
        top = anchorPosition.top + anchorOffset;
    }
    else if (side === 'inside-bottom') {
        top = anchorBottom - anchorOffset - elementDimensions.height;
    }
    else if (side === 'inside-left') {
        left = anchorPosition.left + anchorOffset;
    }
    else if (side === 'inside-right') {
        left = anchorRight - anchorOffset - elementDimensions.width;
    }
    else if (side === 'inside-center') {
        left = (anchorRight + anchorPosition.left) / 2 - elementDimensions.width / 2 + anchorOffset;
    }
    if (side === 'inside-top' || side === 'inside-bottom') {
        if (align === 'start') {
            left = anchorPosition.left + alignmentOffset;
        }
        else if (align === 'center') {
            left = anchorPosition.left - (elementDimensions.width - anchorPosition.width) / 2 + alignmentOffset;
        }
        else {
            left = anchorRight - elementDimensions.width - alignmentOffset;
        }
    }
    else if (side === 'inside-left' || side === 'inside-right' || side === 'inside-center') {
        if (align === 'start') {
            top = anchorPosition.top + alignmentOffset;
        }
        else if (align === 'center') {
            top = anchorPosition.top - (elementDimensions.height - anchorPosition.height) / 2 + alignmentOffset;
        }
        else {
            top = anchorBottom - elementDimensions.height - alignmentOffset;
        }
    }
    return { top, left };
}
function shouldRecalculatePosition(side, currentPos, containerDimensions, elementDimensions) {
    if (side === 'outside-top' || side === 'outside-bottom') {
        return (currentPos.top < containerDimensions.top ||
            currentPos.top + elementDimensions.height > containerDimensions.height + containerDimensions.top);
    }
    else {
        return (currentPos.left < containerDimensions.left ||
            currentPos.left + elementDimensions.width > containerDimensions.width + containerDimensions.left);
    }
}
function shouldRecalculateAlignment(align, currentPos, containerDimensions, elementDimensions) {
    if (align === 'end') {
        return currentPos.left < containerDimensions.left;
    }
    else if (align === 'start' || align === 'center') {
        return (currentPos.left + elementDimensions.width > containerDimensions.left + containerDimensions.width ||
            currentPos.left < containerDimensions.left);
    }
}

export { getAnchoredPosition };
