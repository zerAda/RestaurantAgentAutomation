"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const request_id_1 = require("../src/middlewares/request-id");
const winston_1 = require("winston");
const isProduction = process.env.NODE_ENV === 'production';
exports.default = isProduction ? {
    // 'http' captures strapi.log.http() plus warn/error/info (npm levels 0-3)
    level: 'http',
    format: winston_1.format.combine(
        winston_1.format.timestamp(),
        winston_1.format((info) => {
            const store = request_id_1.requestContextStorage.getStore();
            return {
                ...info,
                service: 'strapi-cms',
                request_id: ((store === null || store === void 0 ? void 0 : store.requestId) !== null && (store === null || store === void 0 ? void 0 : store.requestId) !== void 0 ? store.requestId : ''),
            };
        })(),
        winston_1.format.json(),
    ),
} : {};
