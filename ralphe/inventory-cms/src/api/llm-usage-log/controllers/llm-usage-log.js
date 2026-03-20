'use strict';
const { createCoreController } = require('@strapi/strapi').factories;
module.exports = createCoreController('api::llm-usage-log.llm-usage-log');
