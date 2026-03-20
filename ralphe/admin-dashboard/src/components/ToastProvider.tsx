import { useState, useCallback, useEffect, createContext, useContext, type ReactNode } from 'react';
import { CheckCircle, AlertTriangle, Info, X, ShoppingBag } from 'lucide-react';

/* ── Types ── */
type ToastType = 'success' | 'error' | 'info' | 'order';

interface Toast {
    id: string;
    type: ToastType;
    title: string;
    message?: string;
    duration?: number;
}

interface ToastContextType {
    addToast: (toast: Omit<Toast, 'id'>) => void;
}

const ToastContext = createContext<ToastContextType>({ addToast: () => { } });

// eslint-disable-next-line react-refresh/only-export-components
export const useToast = () => useContext(ToastContext);

/* ── Icons & Colors ── */
const TOAST_STYLES: Record<ToastType, { icon: typeof CheckCircle; bg: string; border: string; iconColor: string }> = {
    success: { icon: CheckCircle, bg: 'bg-emerald-500/5', border: 'border-emerald-500/20', iconColor: 'text-emerald-400' },
    error: { icon: AlertTriangle, bg: 'bg-red-500/5', border: 'border-red-500/20', iconColor: 'text-red-400' },
    info: { icon: Info, bg: 'bg-blue-500/5', border: 'border-blue-500/20', iconColor: 'text-blue-400' },
    order: { icon: ShoppingBag, bg: 'bg-amber-500/5', border: 'border-amber-500/20', iconColor: 'text-amber-400' },
};

/* ── Toast Item ── */
function ToastItem({ toast, onDismiss }: { toast: Toast; onDismiss: (id: string) => void }) {
    const [phase, setPhase] = useState<'enter' | 'visible' | 'exit'>('enter');
    const style = TOAST_STYLES[toast.type];
    const Icon = style.icon;

    useEffect(() => {
        const enterTimer = setTimeout(() => setPhase('visible'), 10);
        const exitTimer = setTimeout(() => setPhase('exit'), toast.duration || 4000);
        const removeTimer = setTimeout(() => onDismiss(toast.id), (toast.duration || 4000) + 300);
        return () => { clearTimeout(enterTimer); clearTimeout(exitTimer); clearTimeout(removeTimer); };
    }, [toast.id, toast.duration, onDismiss]);

    return (
        <div
            className={`flex items-start gap-3 px-4 py-3 rounded-xl ${style.bg} border ${style.border} backdrop-blur-sm shadow-xl shadow-black/40 max-w-sm w-full pointer-events-auto`}
            style={{
                opacity: phase === 'visible' ? 1 : 0,
                transform: phase === 'enter' ? 'translateX(100%)' : phase === 'exit' ? 'translateX(100%)' : 'translateX(0)',
                transition: 'all 300ms cubic-bezier(0.16, 1, 0.3, 1)',
            }}
        >
            <Icon className={`w-4 h-4 mt-0.5 flex-shrink-0 ${style.iconColor}`} />
            <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-white">{toast.title}</p>
                {toast.message && <p className="text-xs text-neutral-400 mt-0.5">{toast.message}</p>}
            </div>
            <button onClick={() => { setPhase('exit'); setTimeout(() => onDismiss(toast.id), 300); }} className="text-neutral-600 hover:text-neutral-400 transition-colors p-0.5">
                <X className="w-3 h-3" />
            </button>
        </div>
    );
}

/* ── Provider ── */
export function ToastProvider({ children }: { children: ReactNode }) {
    const [toasts, setToasts] = useState<Toast[]>([]);

    const addToast = useCallback((toast: Omit<Toast, 'id'>) => {
        const id = `toast-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
        setToasts(prev => [...prev.slice(-4), { ...toast, id }]); // max 5 visible
    }, []);

    const dismiss = useCallback((id: string) => {
        setToasts(prev => prev.filter(t => t.id !== id));
    }, []);

    return (
        <ToastContext.Provider value={{ addToast }}>
            {children}
            {/* Toast container — fixed top-right */}
            <div className="fixed top-4 right-4 z-[60] flex flex-col gap-2 pointer-events-none">
                {toasts.map(toast => (
                    <ToastItem key={toast.id} toast={toast} onDismiss={dismiss} />
                ))}
            </div>
        </ToastContext.Provider>
    );
}
