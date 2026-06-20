export default {
    /**
     * TEN-04: tenant_id is non-defaultable on the customer write path (parity with the
     * n8n data plane's NOT NULL tenant scoping). An absent tenant MUST throw — it is
     * never substituted with a fallback tenant value or a hardcoded tenant UUID.
     * Per-tenant phone uniqueness is enforced at the DB level by the
     * (tenant_id, phone) composite index (db/migrations-strapi/2026-06-20_strapi_order_customer_tenant.sql),
     * which replaces the old global phone unique.
     */
    async beforeCreate(event: any) {
        const { data } = event.params;

        const tenantId = (data.tenant_id || '').toString().trim();
        if (!tenantId) {
            throw new Error('tenant_id is required for a customer (non-defaultable, no default tenant).');
        }
    },
};
