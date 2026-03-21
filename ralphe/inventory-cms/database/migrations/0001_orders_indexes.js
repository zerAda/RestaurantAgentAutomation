/**
 * M-01 + M-02 DB Migration: Performance indexes on orders table
 * 
 * Without these, every KitchenView load does a full table scan on status,
 * and every AnalyticsView query sorts the entire orders table by date.
 * At 10,000+ orders, this becomes catastrophic.
 */
'use strict';

module.exports = {
  async up(knex) {
    const hasStatus = await knex.schema.hasColumn('orders', 'status');
    const hasCreatedAt = await knex.schema.hasColumn('orders', 'created_at');

    if (hasStatus) {
      // Index for KitchenView: filters by status
      const hasIdx1 = await knex.raw(`
        SELECT 1 FROM pg_indexes WHERE indexname = 'idx_orders_status'
      `).then(r => r.rows.length > 0).catch(() => false);
      
      if (!hasIdx1) {
        await knex.raw('CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_status ON orders (status)');
        console.log('[Migration 0001] Created idx_orders_status');
      }
    }

    if (hasCreatedAt) {
      // Index for AnalyticsView: sorts by created_at DESC
      const hasIdx2 = await knex.raw(`
        SELECT 1 FROM pg_indexes WHERE indexname = 'idx_orders_created_at'
      `).then(r => r.rows.length > 0).catch(() => false);
      
      if (!hasIdx2) {
        await knex.raw('CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_created_at ON orders (created_at DESC)');
        console.log('[Migration 0001] Created idx_orders_created_at');
      }

      // Composite index for status+date queries (most common query pattern)
      const hasIdx3 = await knex.raw(`
        SELECT 1 FROM pg_indexes WHERE indexname = 'idx_orders_status_created'
      `).then(r => r.rows.length > 0).catch(() => false);

      if (!hasIdx3) {
        await knex.raw('CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_status_created ON orders (status, created_at DESC)');
        console.log('[Migration 0001] Created idx_orders_status_created');
      }
    }
  },

  async down(knex) {
    await knex.raw('DROP INDEX IF EXISTS idx_orders_status');
    await knex.raw('DROP INDEX IF EXISTS idx_orders_created_at');
    await knex.raw('DROP INDEX IF EXISTS idx_orders_status_created');
    console.log('[Migration 0001] Dropped order indexes');
  },
};
