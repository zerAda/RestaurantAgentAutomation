'use strict';
const { createCoreService } = require('@strapi/strapi').factories;
module.exports = createCoreService('api::llm-usage-log.llm-usage-log');
