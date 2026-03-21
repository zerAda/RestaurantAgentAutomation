export function maskPII(text: string | null | undefined): string {
    if (!text) return 'Anonymous';
    
    // If it's a phone number (likely starting with 213 or 0)
    if (/^\+?[0-9]{8,15}$/.test(text)) {
        return text.slice(0, 4) + '****' + text.slice(-3);
    }
    
    // If it's a name
    if (text.length > 3) {
        return text.charAt(0) + '***' + text.slice(-1);
    }
    
    return '***';
}
