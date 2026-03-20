import { Context } from 'koa';

export default (config: any, { strapi }: any) => {
    return async (ctx: Context, next: () => Promise<void>) => {
        // Inject token from cookie to Authorization header if missing
        if (!ctx.request.header.authorization) {
            const token = ctx.cookies.get('adminJwt');
            if (token) {
                ctx.request.header.authorization = `Bearer ${token}`;
            }
        }

        await next();

        // Intercept login success and set HttpOnly cookie
        if (ctx.request.method === 'POST' && ctx.request.path === '/admin/login') {
            if (ctx.response.status === 200 && ctx.response.body && (ctx.response.body as any).data?.token) {
                const token = (ctx.response.body as any).data.token;

                ctx.cookies.set('adminJwt', token, {
                    httpOnly: true,
                    secure: process.env.NODE_ENV === 'production',
                    // D-03 FIX: Reduced from 30 days to 24h. A restaurant terminal
                    // is a shared device — a 30-day session is a major security risk
                    // if a manager forgets to log out.
                    maxAge: 1000 * 60 * 60 * 24, // 24 hours
                    sameSite: 'strict',
                    path: '/',
                });

                // We keep the token in the JSON payload so the frontend can still use it for non-cookie fallback,
                // but emphasize using cookies.
            }
        }

        // Handle logout
        if (ctx.request.method === 'POST' && ctx.request.path === '/admin/logout') {
            ctx.cookies.set('adminJwt', '', { maxAge: 0, path: '/' });
        }
    };
};
