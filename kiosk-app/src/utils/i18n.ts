export type Language = 'en' | 'fr' | 'ar';

interface Translations {
    [key: string]: {
        en: string;
        fr: string;
        ar: string;
    };
}

export const translations: Translations = {
    diamond_selection: {
        en: "Diamond Selection",
        fr: "Sélection Diamant",
        ar: "اختيار دياموند"
    },
    pre_order: {
        en: "Pre-Order",
        fr: "Pré-commander",
        ar: "طلب مسبق"
    },
    diamond_session: {
        en: "Diamond Session",
        fr: "Session Diamant",
        ar: "جلسة دياموند"
    },
    secure_checkout: {
        en: "Secure Checkout initializing...",
        fr: "Initialisation du paiement sécurisé...",
        ar: "جاري تهيئة الدفع الآمن..."
    },
    explore: {
        en: "Explore",
        fr: "Explorer",
        ar: "استكشف"
    },
    cart_empty: {
        en: "Cart empty",
        fr: "Panier vide",
        ar: "السلة فارغة"
    },
    total: {
        en: "Total",
        fr: "Total",
        ar: "المجموع"
    },
    empty_cart: {
        en: "Empty Cart",
        fr: "Vider le panier",
        ar: "تفريغ السلة"
    },
    order_now: {
        en: "Order Now",
        fr: "Commander",
        ar: "اطلب الآن"
    },
    customize: {
        en: "Customize Your Order",
        fr: "Personnalisez votre commande",
        ar: "خصص طلبك"
    },
    add_to_cart: {
        en: "Add to Cart",
        fr: "Ajouter au panier",
        ar: "أضف إلى السلة"
    },
    extras: {
        en: "Extras & Sauces",
        fr: "Suppléments et Sauces",
        ar: "إضافات وصوصات"
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
