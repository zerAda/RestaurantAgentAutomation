import { z } from 'zod';

// Schema for Order Item
const OrderItemSchema = z.object({
  code: z.string(),
  qty: z.number().min(1).max(20),
  options: z.array(z.string()).optional()
});

// Schema for Order Context
const OrderContextSchema = z.object({
  totalCents: z.number().min(0),
  items: z.array(OrderItemSchema),
  serviceMode: z.enum(['sur_place', 'a_emporter', 'livraison']),
  minOrderCents: z.number().optional()
});

/**
 * Validates if an order can be placed.
 * @param context Order context
 * @returns Validation result
 */
export function validateOrder(context: unknown) {
  const result = OrderContextSchema.safeParse(context);
  
  if (!result.success) {
    return { 
      valid: false, 
      errors: result.error.errors.map(e => e.message).join(', ') 
    };
  }

  const { totalCents, minOrderCents, serviceMode } = result.data;
  
  if (serviceMode === 'livraison' && minOrderCents && totalCents < minOrderCents) {
    return {
      valid: false,
      reason: `TIMEOUT_MIN_ORDER: Minimum de commande non atteint (${(minOrderCents/100).toFixed(2)}€)`
    };
  }

  return { valid: true };
}

// Example usage if run directly
if (require.main === module) {
  console.log(validateOrder({
    totalCents: 1500,
    items: [{ code: 'P01', qty: 2 }],
    serviceMode: 'livraison',
    minOrderCents: 2000
  }));
}
