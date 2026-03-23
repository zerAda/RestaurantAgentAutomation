"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.requestContextStorage = void 0;
const async_hooks_1 = require("node:async_hooks");
exports.requestContextStorage = new async_hooks_1.AsyncLocalStorage();
exports.default = (_config, _ctx) => {
    return async (ctx, next) => {
        const requestId = ctx.get('x-request-id') || '';
        await exports.requestContextStorage.run({ requestId }, next);
    };
};
