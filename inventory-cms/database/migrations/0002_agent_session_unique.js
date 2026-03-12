/**
 * M-03 DB Migration: Unique constraint on agent_sessions.session_id
 *
 * The agent-chat controller implements session upsert logic, but without
 * a DB-level unique constraint, concurrent requests can create duplicate
 * sessions. This migration adds the constraint as a safety net.
 */
'use strict';

module.exports = {
  async up(knex) {
    // Detect Strapi's table naming convention (may be agent_sessions or agent-sessions)
    const tableExists = await knex.schema.hasTable('agent_sessions');
    if (!tableExists) {
      console.log('[Migration 0002] agent_sessions table not found, skipping');
      return;
    }

    const hasCol = await knex.schema.hasColumn('agent_sessions', 'session_id');
    if (!hasCol) {
      console.log('[Migration 0002] session_id column not found, skipping');
      return;
    }

    // First deduplicate any existing duplicates (keep latest)
    await knex.raw(`
      DELETE FROM agent_sessions a
      USING agent_sessions b
      WHERE a.id < b.id
        AND a.session_id = b.session_id
    `).catch(() => console.log('[Migration 0002] Dedup skip (no duplicates or different schema)'));

    // Add unique constraint
    const hasConstraint = await knex.raw(`
      SELECT 1 FROM pg_indexes WHERE indexname = 'uq_agent_sessions_session_id'
    `).then(r => r.rows.length > 0).catch(() => false);

    if (!hasConstraint) {
      await knex.raw('CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_agent_sessions_session_id ON agent_sessions (session_id)');
      console.log('[Migration 0002] Created unique index on agent_sessions.session_id');
    }
  },

  async down(knex) {
    await knex.raw('DROP INDEX IF EXISTS uq_agent_sessions_session_id');
    console.log('[Migration 0002] Dropped unique index on agent_sessions.session_id');
  },
};
