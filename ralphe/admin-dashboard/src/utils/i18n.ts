export type Language = 'en' | 'fr' | 'ar';

interface Translations {
    [key: string]: {
        en: string;
        fr: string;
        ar: string;
    };
}

export const translations: Translations = {
    management: {
        en: "Management",
        fr: "Gestion",
        ar: "الإدارة"
    },
    stock_inventory: {
        en: "Stock Inventory",
        fr: "Inventaire des Stocks",
        ar: "مخزون السلع"
    },
    kitchen_display: {
        en: "Kitchen Display",
        fr: "Affichage Cuisine",
        ar: "شاشة المطبخ"
    },
    quick_adjust: {
        en: "Quick Adjust",
        fr: "Ajustement Rapide",
        ar: "تعديل سريع"
    },
    insights: {
        en: "Insights",
        fr: "Analyses",
        ar: "التحليلات"
    },
    live_analytics: {
        en: "Live Analytics",
        fr: "Analytique en Direct",
        ar: "تحليلات مباشرة"
    },
    fleet_status: {
        en: "Fleet Status",
        fr: "État de la Flotte",
        ar: "حالة الأسطول"
    },
    system_health: {
        en: "System Health",
        fr: "État du Système",
        ar: "صحة النظام"
    },
    all_services_online: {
        en: "All services online",
        fr: "Tous les services en ligne",
        ar: "جميع الخدمات متاحة"
    },
    operational_intelligence: {
        en: "Operational Intelligence",
        fr: "Intelligence Opérationnelle",
        ar: "الذكاء العملياتي"
    },
    delivery_fleet: {
        en: "Delivery Fleet",
        fr: "Flotte de Livraison",
        ar: "أسطول التوصيل"
    },
    creative_center: {
        en: "Creative Center",
        fr: "Centre Créatif",
        ar: "مركز الإبداع"
    },
    marketing: {
        en: "Marketing",
        fr: "Marketing",
        ar: "التسويق"
    },
    automation: {
        en: "Automation",
        fr: "Automation",
        ar: "الأتمتة"
    },
    workflows: {
        en: "Workflows",
        fr: "Flux de travail",
        ar: "سير العمل"
    },
    generate_ad: {
        en: "Generate Ad",
        fr: "Générer une Pub",
        ar: "إنشاء إعلان"
    },
    check_health: {
        en: "Check Health",
        fr: "Vérifier l'état",
        ar: "فحص الحالة"
    },
    run_sync: {
        en: "Run Sync",
        fr: "Lancer Sync",
        ar: "تشغيل المزامنة"
    },
    assets: {
        en: "Assets",
        fr: "Actifs",
        ar: "الأصول"
    },
    support_hub: {
        en: "Support Hub",
        fr: "Centre de Support",
        ar: "مركز الدعم"
    },
    customers: {
        en: "Customers",
        fr: "Clients",
        ar: "الزبائن"
    },
    loyalty_tiers: {
        en: "Loyalty Tiers",
        fr: "Niveaux Fidélité",
        ar: "مستويات الولاء"
    },
    brand_dna: {
        en: "Brand DNA",
        fr: "ADN de la Marque",
        ar: "هوية العلامة"
    },
    settings: {
        en: "Settings",
        fr: "Paramètres",
        ar: "الإعدادات"
    },
    tickets: {
        en: "Tickets",
        fr: "Tickets",
        ar: "التذاكر"
    }
};

export function getTranslation(key: string, lang: Language): string {
    return translations[key]?.[lang] || key;
}

export function setPageDirection(lang: Language) {
    const dir = lang === 'ar' ? 'rtl' : 'ltr';
    document.documentElement.dir = dir;
    document.documentElement.lang = lang;
}
