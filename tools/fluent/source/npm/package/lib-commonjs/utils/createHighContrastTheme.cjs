"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});
Object.defineProperty(exports, "createHighContrastTheme", {
    enumerable: true,
    get: function() {
        return createHighContrastTheme;
    }
});
const _highContrastColorPalette = require("../alias/highContrastColorPalette.cjs");
const _highContrastColor = require("../alias/highContrastColor.cjs");
const _index = require("../global/index.cjs");
const _shadows = require("./shadows.cjs");
const _durations = require("../global/durations.cjs");
const _curves = require("../global/curves.cjs");
const _spacings = require("../global/spacings.cjs");
const createHighContrastTheme = ()=>{
    const colorTokens = (0, _highContrastColor.generateColorTokens)();
    return {
        ..._index.borderRadius,
        ..._index.fontSizes,
        ..._index.lineHeights,
        ..._index.fontFamilies,
        ..._index.fontWeights,
        ..._index.strokeWidths,
        ..._spacings.horizontalSpacings,
        ..._spacings.verticalSpacings,
        ..._durations.durations,
        ..._curves.curves,
        ...colorTokens,
        ..._highContrastColorPalette.colorPaletteTokens,
        ..._highContrastColorPalette.colorStatusTokens,
        ...(0, _shadows.createShadowTokens)(colorTokens.colorNeutralShadowAmbient, colorTokens.colorNeutralShadowKey),
        ...(0, _shadows.createShadowTokens)(colorTokens.colorBrandShadowAmbient, colorTokens.colorBrandShadowKey, 'Brand')
    };
};
