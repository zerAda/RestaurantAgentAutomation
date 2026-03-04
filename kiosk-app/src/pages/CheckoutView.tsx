import React, { useState } from 'react';
import { useCart, type CartItem } from '../context/CartContext';
import { strapi } from '../services/strapiClient';

type ServiceMode = 'kiosk_sur_place' | 'kiosk_a_emporter';

const CheckoutView: React.FC = () => {
    const { items, clearCart, total } = useCart();
    const [step, setStep] = useState<'review' | 'mode' | 'confirm' | 'done'>('review');
    const [serviceMode, setServiceMode] = useState<ServiceMode>('kiosk_sur_place');
    const [isSubmitting, setIsSubmitting] = useState(false);
    const [orderId, setOrderId] = useState<string>('');
    const [error, setError] = useState<string>('');

    React.useEffect(() => {
        import('../services/configService').then(({ configService }) => {
            configService.getConfig().then(config => {
                if (config &&
                    (config.kiosk_default_service_mode === 'kiosk_sur_place' || config.kiosk_default_service_mode === 'kiosk_a_emporter')) {
                    setServiceMode(config.kiosk_default_service_mode);
                }
            });
        });
    }, []);

    if (items.length === 0 && step !== 'done') {
        return (
            <div style={{
                display: 'flex', flexDirection: 'column', alignItems: 'center',
                justifyContent: 'center', height: '100vh', background: '#0f0f0f',
                color: 'white', fontFamily: 'system-ui',
            }}>
                <div style={{ fontSize: '4rem', marginBottom: '1rem' }}>🛒</div>
                <h2 style={{ color: '#f59e0b' }}>Votre panier est vide</h2>
                <button onClick={() => window.location.href = '/'}
                    style={{
                        marginTop: '1rem', padding: '1rem 2rem', borderRadius: '1rem',
                        background: '#f59e0b', color: '#0f0f0f', border: 'none',
                        fontSize: '1.1rem', fontWeight: 700, cursor: 'pointer',
                    }}>
                    Voir le menu
                </button>
            </div>
        );
    }

    const handleSubmitOrder = async () => {
        setIsSubmitting(true);
        setError('');
        try {
            const orderItems = items.map((item: CartItem) => ({
                item_code: item.product.id,
                label: item.product.name,
                qty: item.quantity,
                unit_price_cents: item.product.price,
                line_total_cents: item.product.price * item.quantity,
            }));

            const res = await strapi.post<{ id: number }>('/api/orders', {
                channel: 'kiosk',
                service_mode: serviceMode,
                status: 'NEW',
                total_cents: total,
                order_items: orderItems,
            });

            const id = res?.data?.id;
            setOrderId(id ? `#${String(id).padStart(4, '0')}` : `#${Math.floor(Math.random() * 9000 + 1000)}`);
            clearCart();
            setStep('done');
        } catch (err: unknown) {
            const msg = err instanceof Error ? err.message : 'Erreur lors de la commande. Veuillez réessayer.';
            setError(msg);
        } finally {
            setIsSubmitting(false);
        }
    };

    const styles = {
        page: {
            minHeight: '100vh', background: '#0f0f0f', color: 'white',
            fontFamily: 'system-ui', padding: '2rem',
        } as React.CSSProperties,
        card: {
            background: '#1a1a2e', borderRadius: '1rem', padding: '1.5rem',
            marginBottom: '1rem',
        } as React.CSSProperties,
        btn: {
            width: '100%', padding: '1rem', borderRadius: '1rem',
            border: 'none', fontSize: '1.2rem', fontWeight: 700,
            cursor: 'pointer', marginTop: '1rem',
        } as React.CSSProperties,
        primary: { background: '#f59e0b', color: '#0f0f0f' } as React.CSSProperties,
        secondary: { background: '#2d2d44', color: '#e0e0e0' } as React.CSSProperties,
    };

    // Step: Review cart
    if (step === 'review') {
        return (
            <div style={styles.page}>
                <h1 style={{ color: '#f59e0b', marginBottom: '1.5rem' }}>🛒 Votre commande</h1>
                {items.map((item: CartItem, i: number) => (
                    <div key={i} style={{ ...styles.card, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <div>
                            <div style={{ fontWeight: 600, fontSize: '1.1rem' }}>{item.product.name}</div>
                            <div style={{ color: '#9ca3af', fontSize: '0.9rem' }}>x{item.quantity}</div>
                        </div>
                        <div style={{ color: '#f59e0b', fontWeight: 700, fontSize: '1.2rem' }}>
                            {item.product.price * item.quantity} DA
                        </div>
                    </div>
                ))}
                <div style={{ ...styles.card, display: 'flex', justifyContent: 'space-between', fontSize: '1.3rem', fontWeight: 700 }}>
                    <span>Total</span>
                    <span style={{ color: '#f59e0b' }}>{total} DA</span>
                </div>
                <button onClick={() => setStep('mode')} style={{ ...styles.btn, ...styles.primary }}>
                    Continuer →
                </button>
                <button onClick={() => window.location.href = '/'} style={{ ...styles.btn, ...styles.secondary }}>
                    ← Retour au menu
                </button>
            </div>
        );
    }

    // Step: Choose service mode
    if (step === 'mode') {
        return (
            <div style={styles.page}>
                <h1 style={{ color: '#f59e0b', marginBottom: '1.5rem' }}>🍽️ Sur place ou à emporter ?</h1>
                <button
                    onClick={() => { setServiceMode('kiosk_sur_place'); setStep('confirm'); }}
                    style={{
                        ...styles.card, ...styles.btn, display: 'flex', alignItems: 'center',
                        gap: '1rem', background: serviceMode === 'kiosk_sur_place' ? '#f59e0b' : '#1a1a2e',
                        color: serviceMode === 'kiosk_sur_place' ? '#0f0f0f' : 'white', fontSize: '1.3rem',
                    }}>
                    <span style={{ fontSize: '2rem' }}>🪑</span> Sur place
                </button>
                <button
                    onClick={() => { setServiceMode('kiosk_a_emporter'); setStep('confirm'); }}
                    style={{
                        ...styles.card, ...styles.btn, display: 'flex', alignItems: 'center',
                        gap: '1rem', background: serviceMode === 'kiosk_a_emporter' ? '#f59e0b' : '#1a1a2e',
                        color: serviceMode === 'kiosk_a_emporter' ? '#0f0f0f' : 'white', fontSize: '1.3rem',
                    }}>
                    <span style={{ fontSize: '2rem' }}>🛍️</span> À emporter
                </button>
                <button onClick={() => setStep('review')} style={{ ...styles.btn, ...styles.secondary }}>
                    ← Retour
                </button>
            </div>
        );
    }

    // Step: Confirm
    if (step === 'confirm') {
        return (
            <div style={styles.page}>
                <h1 style={{ color: '#f59e0b', marginBottom: '1.5rem' }}>✅ Confirmer la commande</h1>
                <div style={styles.card}>
                    <div style={{ marginBottom: '0.5rem' }}>
                        <strong>Mode:</strong> {serviceMode === 'kiosk_sur_place' ? '🪑 Sur place' : '🛍️ À emporter'}
                    </div>
                    <div style={{ marginBottom: '0.5rem' }}>
                        <strong>Articles:</strong> {items.length}
                    </div>
                    <div style={{ fontSize: '1.5rem', fontWeight: 700, color: '#f59e0b' }}>
                        Total: {total} DA
                    </div>
                </div>
                {error && (
                    <div style={{ background: '#dc262633', color: '#fca5a5', padding: '1rem', borderRadius: '0.5rem', marginBottom: '1rem' }}>
                        ⚠️ {error}
                    </div>
                )}
                <button
                    onClick={handleSubmitOrder}
                    disabled={isSubmitting}
                    style={{
                        ...styles.btn, ...styles.primary,
                        opacity: isSubmitting ? 0.6 : 1,
                    }}>
                    {isSubmitting ? '⏳ Envoi...' : '🎉 Commander'}
                </button>
                <button onClick={() => setStep('mode')} style={{ ...styles.btn, ...styles.secondary }}>
                    ← Retour
                </button>
            </div>
        );
    }

    // Step: Done
    return (
        <div style={{
            display: 'flex', flexDirection: 'column', alignItems: 'center',
            justifyContent: 'center', height: '100vh', background: '#0f0f0f',
            color: 'white', fontFamily: 'system-ui', textAlign: 'center', padding: '2rem',
        }}>
            <div style={{ fontSize: '5rem', marginBottom: '1rem' }}>🎉</div>
            <h1 style={{ color: '#f59e0b', marginBottom: '0.5rem' }}>Commande envoyée !</h1>
            <p style={{ fontSize: '2rem', fontWeight: 700, color: '#f59e0b', marginBottom: '0.5rem' }}>
                {orderId}
            </p>
            <p style={{ color: '#9ca3af', marginBottom: '2rem' }}>
                Votre commande est en cours de préparation.<br />
                Merci pour votre patience !
            </p>
            <button
                onClick={() => { window.location.href = '/'; }}
                style={{
                    padding: '1rem 3rem', borderRadius: '1rem',
                    background: '#f59e0b', color: '#0f0f0f', border: 'none',
                    fontSize: '1.2rem', fontWeight: 700, cursor: 'pointer',
                }}>
                Nouvelle commande
            </button>
        </div>
    );
};

export default CheckoutView;
