"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});
Object.defineProperty(exports, "createTeamsDarkTheme", {
    enumerable: true,
    get: function() {
        return createTeamsDarkTheme;
    }
});
const _darkColorPalette = require("../alias/darkColorPalette.cjs");
const _teamsDarkColor = require("../alias/teamsDarkColor.cjs");
const _index = require("../global/index.cjs");
const _shadows = require("./shadows.cjs");
const _durations = require("../global/durations.cjs");
const _curves = require("../global/curves.cjs");
const _spacings = require("../global/spacings.cjs");
const createTeamsDarkTheme = (brand)=>{
    const colorTokens = (0, _teamsDarkColor.generateColorTokens)(brand);
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
        ..._darkColorPalette.colorPaletteTokens,
        ..._darkColorPalette.colorStatusTokens,
        ...(0, _shadows.createShadowTokens)(colorTokens.colorNeutralShadowAmbient, colorTokens.colorNeutralShadowKey),
        ...(0, _shadows.createShadowTokens)(colorTokens.colorBrandShadowAmbient, colorTokens.colorBrandShadowKey, 'Brand')
    };
};
