"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});
Object.defineProperty(exports, "createLightTheme", {
    enumerable: true,
    get: function() {
        return createLightTheme;
    }
});
const _lightColorPalette = require("../alias/lightColorPalette.cjs");
const _lightColor = require("../alias/lightColor.cjs");
const _index = require("../global/index.cjs");
const _shadows = require("./shadows.cjs");
const _durations = require("../global/durations.cjs");
const _curves = require("../global/curves.cjs");
const _spacings = require("../global/spacings.cjs");
const createLightTheme = (brand)=>{
    const colorTokens = (0, _lightColor.generateColorTokens)(brand);
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
        ..._lightColorPalette.colorPaletteTokens,
        ..._lightColorPalette.colorStatusTokens,
        ...(0, _shadows.createShadowTokens)(colorTokens.colorNeutralShadowAmbient, colorTokens.colorNeutralShadowKey),
        ...(0, _shadows.createShadowTokens)(colorTokens.colorBrandShadowAmbient, colorTokens.colorBrandShadowKey, 'Brand')
    };
};
