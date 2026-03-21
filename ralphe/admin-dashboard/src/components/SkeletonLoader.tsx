/**
 * Quantum Skeleton Loaders
 * High-fidelity placeholders for the Pro SaaS OS.
 * Designed to minimize layout shift while maintaining the glassmorphic aesthetic.
 */

const shimmer = 'relative overflow-hidden before:absolute before:inset-0 before:-translate-x-full before:animate-[shimmer_2s_infinite] before:bg-gradient-to-r before:from-transparent before:via-white/[0.07] before:to-transparent';

export function SkeletonCard({ className = '' }: { className?: string }) {
    return (
        <div className={`quantum-card p-6 ${shimmer} ${className}`}>
            <div className="flex items-center gap-2 mb-4">
                <div className="w-4 h-4 rounded bg-white/5" />
                <div className="w-24 h-3 rounded bg-white/5" />
            </div>
            <div className="w-20 h-8 rounded-xl bg-white/5" />
        </div>
    );
}

export function SkeletonChart({ className = '' }: { className?: string }) {
    return (
        <div className={`quantum-card p-8 ${shimmer} ${className}`}>
            <div className="w-40 h-4 rounded bg-white/5 mb-8" />
            <div className="h-64 flex items-end gap-3 px-4">
                {[45, 75, 55, 90, 65, 80, 60, 40, 70, 85].map((h, i) => (
                    <div key={i} className="flex-1 rounded-t-xl bg-white/[0.03] transition-all" style={{ height: `${h}%` }} />
                ))}
            </div>
        </div>
    );
}

export function SkeletonRow({ className = '' }: { className?: string }) {
    return (
        <div className={`flex items-center gap-4 p-5 rounded-2xl bg-white/[0.02] border border-white/5 ${shimmer} ${className}`}>
            <div className="w-10 h-10 rounded-xl bg-white/5 flex-shrink-0" />
            <div className="flex-1 space-y-2">
                <div className="w-2/3 h-3 rounded bg-white/5" />
                <div className="w-1/3 h-2 rounded bg-white/10" />
            </div>
            <div className="w-16 h-6 rounded-lg bg-white/5" />
        </div>
    );
}

export function SkeletonKPIRow({ count = 4 }: { count?: number }) {
    return (
        <div className={`grid gap-4`} style={{ gridTemplateColumns: `repeat(${count}, 1fr)` }}>
            {Array.from({ length: count }).map((_, i) => (
                <SkeletonCard key={i} />
            ))}
        </div>
    );
}
