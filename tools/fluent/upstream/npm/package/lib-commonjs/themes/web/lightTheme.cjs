"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});
Object.defineProperty(exports, "webLightTheme", {
    enumerable: true,
    get: function() {
        return webLightTheme;
    }
});
const _createLightTheme = require("../../utils/createLightTheme.cjs");
const _brandColors = require("../../global/brandColors.cjs");
const webLightTheme = (0, _createLightTheme.createLightTheme)(_brandColors.brandWeb);
