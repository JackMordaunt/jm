"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});
Object.defineProperty(exports, "teamsHighContrastTheme", {
    enumerable: true,
    get: function() {
        return teamsHighContrastTheme;
    }
});
const _createHighContrastTheme = require("../../utils/createHighContrastTheme.cjs");
const _teamsFontFamilies = require("../../alias/teamsFontFamilies.cjs");
const teamsHighContrastTheme = {
    ...(0, _createHighContrastTheme.createHighContrastTheme)(),
    ..._teamsFontFamilies.fontFamilies
};
