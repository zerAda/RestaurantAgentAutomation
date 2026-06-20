import { AlertTriangle } from 'lucide-react';
import { useEntitlements } from '../hooks/useEntitlements';

// Explicit locked/error surface (ENT-01 criterion 1): when the entitlements fetch
// fails, hidden modules read as "error" — not silently as "unentitled". Renders
// nothing on the happy path. Mirrors ToastProvider's error styling.
export function EntitlementErrorBanner() {
  const { error } = useEntitlements();
  if (!error) return null;

  return (
    <div
      role="alert"
      className="flex items-start gap-3 px-4 py-3 rounded-xl bg-red-500/5 border border-red-500/20 backdrop-blur-sm text-red-400"
    >
      <AlertTriangle className="w-4 h-4 mt-0.5 flex-shrink-0" />
      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium text-white">Entitlements unavailable</p>
        <p className="text-xs text-neutral-400 mt-0.5">
          Some modules are hidden because their access could not be verified. Retry or check your connection.
        </p>
      </div>
    </div>
  );
}
