import type { Core } from '@strapi/strapi';

export interface SeedProduct {
    name: string;
    category: 'burgers' | 'pizzas' | 'tacos' | 'salades' | 'boissons' | 'desserts' | 'specials';
    price: number;
    stock_quantity: number;
    marketing_name: string;
    description_multilang: { fr: string; ar: string; dz: string };
    available_extras?: any[];
    available_sauces?: any[];
    available_sizes?: any[];
    is_kiosk_visible: boolean;
    preparation_time_min: number;
}

export const RESTAURANT_MENU: SeedProduct[] = [
    // --- BURGERS ---
    {
        name: 'Bazooka Burger',
        category: 'burgers',
        price: 850,
        stock_quantity: 50,
        marketing_name: 'The Bazooka 💣',
        description_multilang: {
            fr: 'Double steak, triple cheddar, sauce secrète Ralphé. Un classique explosif.',
            ar: 'بوظوكة برجر - شريحتين لحم، جبنة شيدر ثلاثية و صلصة رالفي السرية.',
            dz: 'بازوكا برجر - زوج ستيك، طروبل شيدر، صوص رالفي. حاجة مهبولة.'
        },
        available_extras: [
            { name: 'Cheddar', price: 100, category: 'fromage' },
            { name: 'Bacon Beef', price: 150, category: 'viande' },
            { name: 'Œuf', price: 50, category: 'garniture' }
        ],
        available_sauces: [
            { name: 'Algérienne', price: 0, included_count: 1 },
            { name: 'Samurai', price: 0, included_count: 1 },
            { name: 'Sauce Ralphé', price: 50 }
        ],
        available_sizes: [
            { name: 'Normal', price_modifier: 0 },
            { name: 'Giant', price_modifier: 350 }
        ],
        is_kiosk_visible: true,
        preparation_time_min: 12
    },
    {
        name: 'Titanic Burger',
        category: 'burgers',
        price: 1200,
        stock_quantity: 30,
        marketing_name: 'The Titanic 🚢',
        description_multilang: {
            fr: 'Le plus grand burger de la ville. 4 steaks, oignons caramélisés et bacon.',
            ar: 'تيتانيك برجر - أكبر برجر في المدينة. 4 شرائح لحم بصل مكرمل ولحم مقدد.',
            dz: 'تيتانيك برجر - أكبر برجر في البلاد. 4 ستيكات، بصل معسل وشوية فاكسا.'
        },
        is_kiosk_visible: true,
        preparation_time_min: 20
    },
    // --- PIZZAS ---
    {
        name: 'Pizza Margherita',
        category: 'pizzas',
        price: 650,
        stock_quantity: 100,
        marketing_name: 'Classic Margherita 🇮🇹',
        description_multilang: {
            fr: 'Sauce tomate maison, mozzarella fior di latte, basilic frais et huile d\'olive.',
            ar: 'بيتزا مارغريتا - صلصة طماطم منزلية، موزاريلا و ريحان طازج.',
            dz: 'مارغريتا كلاسيك - صوص طوماط تاع الدار، فرماج قاصح وشوية حبق.'
        },
        available_sizes: [
            { name: 'Medium', price_modifier: 0 },
            { name: 'Large', price_modifier: 300 },
            { name: 'Mega', price_modifier: 600 }
        ],
        is_kiosk_visible: true,
        preparation_time_min: 15
    },
    {
        name: 'Pizza 4 Saisons',
        category: 'pizzas',
        price: 950,
        stock_quantity: 40,
        marketing_name: 'Les 4 Saisons 🍕',
        description_multilang: {
            fr: 'Champignons, poivrons, olives, jambon de dinde et artichauts.',
            ar: 'بيتزا الفصول الأربعة - فطر، فلفل، زيتون ولحم ديك رومي.',
            dz: 'بيتزا 4 صيزون - شمبينيون، فلفل، زيتون وداند.'
        },
        is_kiosk_visible: true,
        preparation_time_min: 18
    },
    // --- TACOS ---
    {
        name: 'Tacos Lyon Standard',
        category: 'tacos',
        price: 750,
        stock_quantity: 80,
        marketing_name: 'Tacos Lyon 🇫🇷',
        description_multilang: {
            fr: 'Double viande au choix, frites, sauce fromagère maison.',
            ar: 'تاكوس ليون - قطعتين لحم حسب اختيارك مع بطاطس مقلية وصلصة الجبن.',
            dz: 'تاكوس ليون - زوج فياند من اختيارك، فريت، وصوص فروماج عاقدة.'
        },
        available_sauces: [
            { name: 'Fromagère', price: 0, included_count: 1 },
            { name: 'Algérienne', price: 0 }
        ],
        is_kiosk_visible: true,
        preparation_time_min: 10
    },
    // --- BOISSONS ---
    {
        name: 'Coca Cola 33cl',
        category: 'boissons',
        price: 100,
        stock_quantity: 200,
        marketing_name: 'Coca Cola Classic',
        description_multilang: {
            fr: 'Boisson rafraîchissante 33cl.',
            ar: 'كوكا كولا 33 مل.',
            dz: 'كوكا كولا 33 سل باردة قلاصي.'
        },
        is_kiosk_visible: true,
        preparation_time_min: 1
    },
    {
        name: 'Eau Minérale 50cl',
        category: 'boissons',
        price: 50,
        stock_quantity: 500,
        marketing_name: 'Eau Pure',
        description_multilang: {
            fr: 'Eau minérale naturelle 50cl.',
            ar: 'مياه معدنية طبيعية 50 مل.',
            dz: 'ماء سعيدة 50 سل.'
        },
        is_kiosk_visible: true,
        preparation_time_min: 1
    },
    // --- DESSERTS ---
    {
        name: 'Tiramisu Maison',
        category: 'desserts',
        price: 450,
        stock_quantity: 20,
        marketing_name: 'Tiramisu Ralphé 🍰',
        description_multilang: {
            fr: 'Le vrai tiramisu italien, fait maison tous les matins.',
            ar: 'تيراميسو منزلي - التيراميسو الإيطالي الأصلي، يحضر يوميا.',
            dz: 'تيراميسو تاع الدار - حاجة بنينة وخدمة يدين.'
        },
        is_kiosk_visible: true,
        preparation_time_min: 2
    }
];

export async function seedRestaurantMenu(strapi: Core.Strapi) {
    strapi.log.info('Seeding professional restaurant menu...');

    for (const item of RESTAURANT_MENU) {
        try {
            const existing = await strapi.query('api::product.product').findOne({
                where: { name: item.name }
            });

            if (!existing) {
                await strapi.service('api::product.product').create({
                    data: {
                        ...item,
                        publishedAt: new Date()
                    }
                });
                strapi.log.info(`Product seeded: ${item.name}`);
            }
        } catch (err: any) {
            strapi.log.error(`Failed to seed product ${item.name}: ${err.message}`);
        }
    }

    strapi.log.info('Restaurant menu seeding completed.');
}
