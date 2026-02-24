import { useState } from 'react';

const DOMAIN = import.meta.env.VITE_DOMAIN || 'srv1258231.hstgr.cloud';

const APPS = [
  { label: 'Admin Dashboard', url: `https://admin.${DOMAIN}`, current: true },
  { label: 'Kiosk', url: `https://kiosk.${DOMAIN}`, current: false },
  { label: 'CMS Strapi', url: `https://cms.${DOMAIN}/admin`, current: false },
  { label: 'n8n Console', url: `https://console.${DOMAIN}`, current: false },
];

export function AppSwitcher() {
  const [open, setOpen] = useState(false);

  return (
    <div className="relative">
      <button
        onClick={() => setOpen(!open)}
        className="flex items-center gap-2 px-3 py-2 text-sm rounded-lg bg-zinc-100 dark:bg-zinc-700 hover:bg-zinc-200 dark:hover:bg-zinc-600 transition-colors w-full"
      >
        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
        </svg>
        <span>Switch App</span>
      </button>

      {open && (
        <div className="absolute left-0 top-full mt-1 w-56 bg-white dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-600 rounded-lg shadow-lg z-50">
          {APPS.map(app => (
            <a
              key={app.label}
              href={app.url}
              className={`block px-4 py-2.5 text-sm hover:bg-zinc-100 dark:hover:bg-zinc-700 transition-colors first:rounded-t-lg last:rounded-b-lg ${
                app.current ? 'font-semibold text-indigo-600 dark:text-indigo-400 bg-indigo-50 dark:bg-indigo-900/20' : ''
              }`}
            >
              {app.label}
              {app.current && <span className="ml-2 text-xs opacity-60">(current)</span>}
            </a>
          ))}
        </div>
      )}
    </div>
  );
}
