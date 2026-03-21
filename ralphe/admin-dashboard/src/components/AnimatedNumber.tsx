import { useState, useEffect, useRef } from 'react';

/**
 * Animated number that counts up from 0 (or previous value) to `value`.
 * Pure CSS + requestAnimationFrame, no dependencies.
 */
export function AnimatedNumber({
    value,
    duration = 600,
    prefix = '',
    suffix = '',
    decimals = 0,
    className = '',
}: {
    value: number;
    duration?: number;
    prefix?: string;
    suffix?: string;
    decimals?: number;
    className?: string;
}) {
    const [display, setDisplay] = useState(value);
    const prevValue = useRef(value);
    const frameRef = useRef(0);

    useEffect(() => {
        const start = prevValue.current;
        const end = value;
        const diff = end - start;
        if (Math.abs(diff) < 0.01) {
            Promise.resolve().then(() => setDisplay(end));
            prevValue.current = end;
            return;
        }

        const startTime = performance.now();

        function animate(now: number) {
            const elapsed = now - startTime;
            const progress = Math.min(elapsed / duration, 1);
            // Ease-out cubic
            const eased = 1 - Math.pow(1 - progress, 3);
            setDisplay(start + diff * eased);

            if (progress < 1) {
                frameRef.current = requestAnimationFrame(animate);
            } else {
                prevValue.current = end;
            }
        }

        frameRef.current = requestAnimationFrame(animate);
        return () => cancelAnimationFrame(frameRef.current);
    }, [value, duration]);

    const formatted = decimals > 0 ? display.toFixed(decimals) : Math.round(display).toLocaleString();

    return <span className={className}>{prefix}{formatted}{suffix}</span>;
}
