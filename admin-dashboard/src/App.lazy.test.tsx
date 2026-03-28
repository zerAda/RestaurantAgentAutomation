import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';

const appSource = fs.readFileSync(path.resolve(__dirname, 'App.tsx'), 'utf-8');

const LAZY_COMPONENTS = [
  'StockView',
  'QuickAdjust',
  'KitchenView',
  'MarketingView',
  'AutomationView',
  'SupportView',
  'CustomerView',
  'BrandView',
  'AnalyticsView',
  'DashboardHome',
  'AiObservatoryView',
  'GrowthAgentView',
  'ControlPlaneView',
  'AuditLogView',
];

const EAGER_COMPONENTS = [
  'LoginView',
  'AppSwitcher',
  'AIChatBubble',
  'NotificationCenter',
];

describe('App.tsx — PERF-07: React.lazy() code splitting', () => {
  it('should declare each route-level view component with React.lazy()', () => {
    for (const name of LAZY_COMPONENTS) {
      expect(
        appSource,
        `Expected "const ${name} = lazy(" in App.tsx — ${name} must be lazy-loaded`
      ).toContain(`const ${name} = lazy(`);
    }
  });

  it('should keep app-shell components as eager imports', () => {
    for (const name of EAGER_COMPONENTS) {
      expect(
        appSource,
        `Expected "import { ${name} }" in App.tsx — ${name} must remain eagerly imported`
      ).toContain(`import { ${name} }`);
    }
  });

  it('should wrap routes in a <Suspense fallback= tag', () => {
    expect(
      appSource,
      'Expected <Suspense fallback= in App.tsx — lazy components must be wrapped in Suspense'
    ).toContain('<Suspense fallback=');
  });

  it('should use the locked fallback skeleton pattern from UI-SPEC (min-h-[60vh] and bg-white/5)', () => {
    expect(
      appSource,
      'Expected min-h-[60vh] in Suspense fallback — locked skeleton pattern from 06-UI-SPEC.md'
    ).toContain('min-h-[60vh]');

    expect(
      appSource,
      'Expected bg-white/5 in Suspense fallback — locked skeleton pattern from 06-UI-SPEC.md'
    ).toContain('bg-white/5');
  });
});
