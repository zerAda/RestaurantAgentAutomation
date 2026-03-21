import { useState, useEffect, useRef, type ReactNode } from 'react';

/**
 * Wraps tab content with a fade-slide entrance animation.
 * CSS-only: no framer-motion dependency.
 */
export function PageTransition({ children, activeKey }: { children: ReactNode; activeKey: string }) {
    const [displayed, setDisplayed] = useState<ReactNode>(children);
    const [phase, setPhase] = useState<'enter' | 'exit'>('enter');
    const prevKey = useRef(activeKey);

    useEffect(() => {
        if (activeKey !== prevKey.current) {
            Promise.resolve().then(() => setPhase('exit'));
            const t = setTimeout(() => {
                setDisplayed(children);
                setPhase('enter');
                prevKey.current = activeKey;
            }, 150); // exit duration
            return () => clearTimeout(t);
        } else {
            Promise.resolve().then(() => setDisplayed(children));
        }
    }, [activeKey, children]);

    return (
        <div
            className="w-full"
            style={{
                opacity: phase === 'enter' ? 1 : 0,
                transform: phase === 'enter' ? 'translateY(0)' : 'translateY(8px)',
                transition: 'opacity 200ms ease-out, transform 200ms ease-out',
            }}
        >
            {displayed}
        </div>
    );
}
