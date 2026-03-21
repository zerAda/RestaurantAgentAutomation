import { strapi } from './strapiClient';

export interface SystemConfig {
    kiosk_idle_timeout_sec: number;
    kiosk_default_service_mode: 'kiosk_sur_place' | 'kiosk_a_emporter' | 'sur_place' | 'a_emporter';
    kiosk_enabled: boolean;
}

const CACHE_KEY = 'kiosk_system_config';
const CACHE_TTL_MS = 5 * 60 * 1000;

export const configService = {
    getConfig: async (): Promise<SystemConfig | null> => {
        try {
            const cached = sessionStorage.getItem(CACHE_KEY);
            if (cached) {
                const { data, timestamp } = JSON.parse(cached);
                if (Date.now() - timestamp < CACHE_TTL_MS) {
                    return data;
                }
                sessionStorage.removeItem(CACHE_KEY);
            }

            const res = await strapi.get<{ kiosk_idle_timeout_sec: number; kiosk_default_service_mode: string; kiosk_enabled: boolean; }>('/api/system-config');

            const configData: SystemConfig = {
                kiosk_idle_timeout_sec: res.data?.kiosk_idle_timeout_sec ?? 120,
                kiosk_default_service_mode: res.data?.kiosk_default_service_mode as 'kiosk_sur_place' | 'kiosk_a_emporter' | 'sur_place' | 'a_emporter' ?? 'kiosk_sur_place',
                kiosk_enabled: res.data?.kiosk_enabled ?? true
            };

            // Map standard modes to kiosk modes if needed
            if (configData.kiosk_default_service_mode === 'sur_place') configData.kiosk_default_service_mode = 'kiosk_sur_place';
            if (configData.kiosk_default_service_mode === 'a_emporter') configData.kiosk_default_service_mode = 'kiosk_a_emporter';

            sessionStorage.setItem(CACHE_KEY, JSON.stringify({
                data: configData,
                timestamp: Date.now()
            }));

            return configData;
        } catch (err) {
            console.error('Failed to fetch system config', err);
            return {
                kiosk_idle_timeout_sec: 120,
                kiosk_default_service_mode: 'kiosk_sur_place',
                kiosk_enabled: true
            };
        }
    }
};
