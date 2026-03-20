/**
 * M-04 DB Migration: Index on conversation_states.conversation_key
 *
 * W4_CORE loads state on EVERY message via:
 *   SELECT ... FROM conversation_state WHERE conversation_key=$1
 * Without an index, this is a full scan. At 1000+ concurrent conversations,
 * the DB will choke. This index makes it O(log n).
 */
'use strict';

module.exports = {
  async up(knex) {
    const tableExists = await knex.schema.hasTable('conversation_states');
    if (!tableExists) {
      console.log('[Migration 0003] conversation_states table not found, skipping');
      return;
    }

    const hasIdx = await knex.raw(`
      SELECT 1 FROM pg_indexes WHERE indexname = 'idx_conv_states_key'
    `).then(r => r.rows.length > 0).catch(() => false);

    if (!hasIdx) {
      await knex.raw('CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conv_states_key ON conversation_states (conversation_key)');
      console.log('[Migration 0003] Created idx_conv_states_key');
    }

    // Also index customer table for WhatsApp user lookups
    const hasCustomers = await knex.schema.hasTable('customers');
    if (hasCustomers) {
      const hasPhoneIdx = await knex.raw(`
        SELECT 1 FROM pg_indexes WHERE indexname = 'idx_customers_phone'
      `).then(r => r.rows.length > 0).catch(() => false);

      if (!hasPhoneIdx) {
        await knex.raw('CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_customers_phone ON customers (phone)');
        console.log('[Migration 0003] Created idx_customers_phone');
      }
    }
  },

  async down(knex) {
    await knex.raw('DROP INDEX IF EXISTS idx_conv_states_key');
    await knex.raw('DROP INDEX IF EXISTS idx_customers_phone');
    console.log('[Migration 0003] Dropped conversation_states and customers indexes');
  },
};
