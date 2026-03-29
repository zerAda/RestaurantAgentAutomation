import { useState, useEffect, useCallback } from 'react';
import {
  Search,
  RefreshCw,
  ChevronLeft,
  ChevronRight,
  Clock,
  CheckCircle2,
  XCircle,
  Loader2,
  Filter,
  Download,
  Activity,
} from 'lucide-react';
import { cn } from '../lib/utils';

/* ────────────────────────── types ────────────────────────── */

interface AuditRecord {
  id: string;
  workflow_name: string;
  workflow_id: string;
  execution_id: string;
  channel: string;
  status: 'started' | 'completed' | 'failed';
  started_at: string;
  completed_at: string | null;
  correlation_id: string;
  duration_ms: number | null;
  error_message: string | null;
  created_at: string;
}

interface AuditResponse {
  data: AuditRecord[];
  total: number;
  page: number;
  limit: number;
}

/* ────────────────────────── constants ────────────────────── */

const STATUS_MAP: Record<string, { label: string; color: string; icon: React.ElementType; bgClass: string }> = {
  started:   { label: 'Running',   color: 'text-amber-400',  icon: Loader2,      bgClass: 'bg-amber-400/10 border-amber-400/20' },
  completed: { label: 'Success',   color: 'text-emerald-400', icon: CheckCircle2, bgClass: 'bg-emerald-400/10 border-emerald-400/20' },
  failed:    { label: 'Failed',    color: 'text-red-400',     icon: XCircle,      bgClass: 'bg-red-400/10 border-red-400/20' },
};

const CHANNEL_COLORS: Record<string, string> = {
  whatsapp:  'bg-green-500/20 text-green-400 border-green-500/30',
  instagram: 'bg-pink-500/20 text-pink-400 border-pink-500/30',
  messenger: 'bg-blue-500/20 text-blue-400 border-blue-500/30',
  tiktok:    'bg-fuchsia-500/20 text-fuchsia-400 border-fuchsia-500/30',
  system:    'bg-zinc-500/20 text-zinc-400 border-zinc-500/30',
};

const ITEMS_PER_PAGE = 25;

/* ────────────────────────── helpers ──────────────────────── */

function formatDuration(ms: number | null): string {
  if (ms === null || ms === undefined) return '—';
  if (ms < 1000) return `${ms}ms`;
  if (ms < 60_000) return `${(ms / 1000).toFixed(1)}s`;
  return `${(ms / 60_000).toFixed(1)}m`;
}

function timeAgo(dateStr: string): string {
  const now = Date.now();
  const then = new Date(dateStr).getTime();
  const diff = now - then;
  if (diff < 60_000) return 'just now';
  if (diff < 3_600_000) return `${Math.floor(diff / 60_000)}m ago`;
  if (diff < 86_400_000) return `${Math.floor(diff / 3_600_000)}h ago`;
  return `${Math.floor(diff / 86_400_000)}d ago`;
}

/* ────────────────────────── component ────────────────────── */

export function AuditLogView() {
  const [records, setRecords] = useState<AuditRecord[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Filters
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [channelFilter, setChannelFilter] = useState<string>('all');

  // Auto-refresh
  const [autoRefresh, setAutoRefresh] = useState(true);

  const apiBase = import.meta.env.VITE_N8N_URL || '';

  const fetchAuditLogs = useCallback(async (silent = false) => {
    if (!silent) setLoading(true);
    else setRefreshing(true);

    try {
      const params = new URLSearchParams({
        page: page.toString(),
        limit: ITEMS_PER_PAGE.toString(),
      });
      if (statusFilter !== 'all') params.set('status', statusFilter);
      if (channelFilter !== 'all') params.set('channel', channelFilter);
      if (searchTerm.trim()) params.set('workflow_name', searchTerm.trim());

      const url = `${apiBase}/webhook/v1/internal/audit-log?${params}`;

      const res = await fetch(url, {
        headers: { 'Content-Type': 'application/json' },
      });

      if (!res.ok) throw new Error(`HTTP ${res.status}`);

      const json: AuditResponse = await res.json();
      setRecords(json.data || []);
      setTotal(json.total || 0);
      setError(null);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Unknown error';
      setError(msg);
      // Keep existing records on refresh failure
      if (!silent) setRecords([]);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [apiBase, page, statusFilter, channelFilter, searchTerm]);

  useEffect(() => {
    fetchAuditLogs();
  }, [fetchAuditLogs]);

  useEffect(() => {
    if (!autoRefresh) return;
    const interval = setInterval(() => fetchAuditLogs(true), 15_000);
    return () => clearInterval(interval);
  }, [autoRefresh, fetchAuditLogs]);

  const totalPages = Math.ceil(total / ITEMS_PER_PAGE);

  // Stats
  const successCount = records.filter(r => r.status === 'completed').length;
  const failedCount = records.filter(r => r.status === 'failed').length;
  const runningCount = records.filter(r => r.status === 'started').length;

  const handleExportCSV = () => {
    const headers = ['Workflow', 'Channel', 'Status', 'Duration', 'Correlation ID', 'Started At', 'Completed At'];
    const rows = records.map(r => [
      r.workflow_name,
      r.channel,
      r.status,
      formatDuration(r.duration_ms),
      r.correlation_id,
      r.started_at,
      r.completed_at || '',
    ]);
    const csv = [headers.join(','), ...rows.map(r => r.join(','))].join('\n');
    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `audit-log-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="space-y-8 animate-in fade-in slide-in-from-bottom-8 duration-700" id="audit-log-view">
      {/* ── Stats Strip ── */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <StatCard label="Total Executions" value={total.toLocaleString()} color="text-white" />
        <StatCard label="Successful" value={successCount.toString()} color="text-emerald-400" />
        <StatCard label="Failed" value={failedCount.toString()} color="text-red-400" />
        <StatCard label="Running" value={runningCount.toString()} color="text-amber-400" pulse={runningCount > 0} />
      </div>

      {/* ── Toolbar ── */}
      <div className="quantum-card p-4 flex flex-col md:flex-row gap-4 items-start md:items-center justify-between">
        <div className="flex flex-wrap gap-3 items-center flex-1">
          {/* Search */}
          <div className="relative flex-1 min-w-[200px] max-w-md">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-zinc-500" size={16} />
            <input
              type="text"
              placeholder="Search workflow..."
              value={searchTerm}
              onChange={(e) => { setSearchTerm(e.target.value); setPage(1); }}
              className="w-full pl-10 pr-4 py-2.5 bg-white/5 border border-white/10 rounded-xl text-sm text-white placeholder-zinc-500 focus:outline-none focus:border-brand-primary/50 focus:ring-1 focus:ring-brand-primary/20 transition-all"
              id="audit-search-input"
            />
          </div>

          {/* Status Filter */}
          <div className="flex items-center gap-2">
            <Filter size={14} className="text-zinc-500" />
            <select
              value={statusFilter}
              onChange={(e) => { setStatusFilter(e.target.value); setPage(1); }}
              className="bg-white/5 border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white focus:outline-none focus:border-brand-primary/50 appearance-none cursor-pointer"
              id="audit-status-filter"
            >
              <option value="all">All Status</option>
              <option value="started">Running</option>
              <option value="completed">Success</option>
              <option value="failed">Failed</option>
            </select>
          </div>

          {/* Channel Filter */}
          <select
            value={channelFilter}
            onChange={(e) => { setChannelFilter(e.target.value); setPage(1); }}
            className="bg-white/5 border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white focus:outline-none focus:border-brand-primary/50 appearance-none cursor-pointer"
            id="audit-channel-filter"
          >
            <option value="all">All Channels</option>
            <option value="whatsapp">WhatsApp</option>
            <option value="instagram">Instagram</option>
            <option value="messenger">Messenger</option>
            <option value="tiktok">TikTok</option>
            <option value="system">System</option>
          </select>
        </div>

        <div className="flex gap-2 items-center">
          {/* Auto refresh toggle */}
          <button
            onClick={() => setAutoRefresh(!autoRefresh)}
            className={cn(
              "px-3 py-2 rounded-xl text-xs font-bold uppercase tracking-wider border transition-all",
              autoRefresh
                ? "bg-brand-primary/10 border-brand-primary/30 text-brand-primary"
                : "bg-white/5 border-white/10 text-zinc-500"
            )}
            id="audit-auto-refresh"
          >
            <Activity size={14} className={cn("inline mr-1.5", autoRefresh && "animate-pulse")} />
            Live
          </button>

          {/* Manual Refresh */}
          <button
            onClick={() => fetchAuditLogs(true)}
            className="p-2.5 rounded-xl bg-white/5 border border-white/10 text-zinc-400 hover:text-white hover:bg-white/10 transition-all"
            disabled={refreshing}
            id="audit-refresh-btn"
          >
            <RefreshCw size={16} className={cn(refreshing && "animate-spin")} />
          </button>

          {/* Export */}
          <button
            onClick={handleExportCSV}
            className="p-2.5 rounded-xl bg-white/5 border border-white/10 text-zinc-400 hover:text-white hover:bg-white/10 transition-all"
            id="audit-export-btn"
          >
            <Download size={16} />
          </button>
        </div>
      </div>

      {/* ── Table ── */}
      <div className="quantum-card overflow-hidden">
        {loading ? (
          <div className="flex items-center justify-center py-20 gap-3 text-zinc-500">
            <Loader2 className="animate-spin" size={20} />
            <span className="text-sm font-medium">Loading audit trail…</span>
          </div>
        ) : error ? (
          <div className="flex flex-col items-center justify-center py-20 text-zinc-500 gap-3">
            <XCircle size={32} className="text-red-400/50" />
            <p className="text-sm">Failed to load audit data</p>
            <p className="text-xs text-zinc-600">{error}</p>
            <button
              onClick={() => fetchAuditLogs()}
              className="mt-2 px-4 py-2 rounded-xl bg-white/5 border border-white/10 text-xs font-bold text-white hover:bg-white/10 transition-all"
            >
              Retry
            </button>
          </div>
        ) : records.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-20 text-zinc-500 gap-3">
            <Activity size={32} className="text-zinc-700" />
            <p className="text-sm">No audit records found</p>
            <p className="text-xs text-zinc-600">Audit data will appear here once workflows execute.</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm" id="audit-log-table">
              <thead>
                <tr className="border-b border-white/5">
                  <th className="px-5 py-4 text-left text-[10px] font-black text-zinc-500 uppercase tracking-[0.15em]">Workflow</th>
                  <th className="px-5 py-4 text-left text-[10px] font-black text-zinc-500 uppercase tracking-[0.15em]">Channel</th>
                  <th className="px-5 py-4 text-left text-[10px] font-black text-zinc-500 uppercase tracking-[0.15em]">Status</th>
                  <th className="px-5 py-4 text-left text-[10px] font-black text-zinc-500 uppercase tracking-[0.15em]">Duration</th>
                  <th className="px-5 py-4 text-left text-[10px] font-black text-zinc-500 uppercase tracking-[0.15em]">Time</th>
                  <th className="px-5 py-4 text-left text-[10px] font-black text-zinc-500 uppercase tracking-[0.15em]">Correlation</th>
                </tr>
              </thead>
              <tbody>
                {records.map((record, i) => {
                  const statusInfo = STATUS_MAP[record.status] || STATUS_MAP.started;
                  const StatusIcon = statusInfo.icon;
                  const channelColor = CHANNEL_COLORS[record.channel] || CHANNEL_COLORS.system;

                  return (
                    <tr
                      key={record.id || i}
                      className="border-b border-white/[0.03] hover:bg-white/[0.03] transition-colors group"
                    >
                      {/* Workflow */}
                      <td className="px-5 py-4">
                        <div className="flex flex-col gap-1">
                          <span className="font-bold text-white group-hover:text-brand-primary transition-colors">
                            {record.workflow_name}
                          </span>
                          <span className="text-[10px] text-zinc-600 font-mono">
                            {record.execution_id?.slice(0, 12) || '—'}
                          </span>
                        </div>
                      </td>

                      {/* Channel */}
                      <td className="px-5 py-4">
                        <span className={cn("px-2.5 py-1 rounded-lg text-[10px] font-black uppercase tracking-wider border", channelColor)}>
                          {record.channel}
                        </span>
                      </td>

                      {/* Status */}
                      <td className="px-5 py-4">
                        <span className={cn("inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-[10px] font-black uppercase tracking-wider border", statusInfo.bgClass)}>
                          <StatusIcon size={12} className={cn(statusInfo.color, record.status === 'started' && 'animate-spin')} />
                          <span className={statusInfo.color}>{statusInfo.label}</span>
                        </span>
                      </td>

                      {/* Duration */}
                      <td className="px-5 py-4">
                        <span className="font-mono text-zinc-400 text-xs">
                          {formatDuration(record.duration_ms)}
                        </span>
                      </td>

                      {/* Time */}
                      <td className="px-5 py-4">
                        <div className="flex items-center gap-1.5 text-zinc-500">
                          <Clock size={12} />
                          <span className="text-xs">{timeAgo(record.started_at || record.created_at)}</span>
                        </div>
                      </td>

                      {/* Correlation ID */}
                      <td className="px-5 py-4">
                        <span className="text-[10px] font-mono text-zinc-600 bg-white/5 px-2 py-1 rounded">
                          {record.correlation_id?.slice(0, 16) || '—'}
                        </span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}

        {/* Pagination */}
        {totalPages > 1 && (
          <div className="flex items-center justify-between px-5 py-4 border-t border-white/5">
            <span className="text-xs text-zinc-500">
              Page {page} of {totalPages} · {total.toLocaleString()} records
            </span>
            <div className="flex gap-2">
              <button
                onClick={() => setPage(Math.max(1, page - 1))}
                disabled={page <= 1}
                className="p-2 rounded-lg bg-white/5 border border-white/10 text-zinc-400 hover:text-white disabled:opacity-30 disabled:cursor-not-allowed transition-all"
                id="audit-prev-page"
              >
                <ChevronLeft size={16} />
              </button>
              <button
                onClick={() => setPage(Math.min(totalPages, page + 1))}
                disabled={page >= totalPages}
                className="p-2 rounded-lg bg-white/5 border border-white/10 text-zinc-400 hover:text-white disabled:opacity-30 disabled:cursor-not-allowed transition-all"
                id="audit-next-page"
              >
                <ChevronRight size={16} />
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

/* ────────────────────────── stat card ────────────────────── */

function StatCard({ label, value, color, pulse = false }: { label: string; value: string; color: string; pulse?: boolean }) {
  return (
    <div className="quantum-card p-5 flex flex-col gap-2">
      <span className="text-[10px] font-black text-zinc-500 uppercase tracking-[0.15em]">{label}</span>
      <span className={cn("text-3xl font-black tracking-tighter", color, pulse && "animate-pulse")}>
        {value}
      </span>
    </div>
  );
}

export default AuditLogView;
